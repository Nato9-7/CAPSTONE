"""Moderación de reportes desde el panel.

Igual que en el resto de la API, el autor se muestra con su alias: el panel puede
suspender a quien reportó sin conocer su nombre.
"""

import logging
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.comun.alias import alias_autor, mapa_alias
from app.comun.archivos import borrar_archivos
from app.db import consultar, transaccion
from app.seguridad import usuario_admin
from app.servicios import grafo, moderacion
from app.servicios.comentarios import comentarios_de_reporte
from app.servicios.reportes import cambiar_estado

router = APIRouter()
log = logging.getLogger("rb_alertas.admin")


class CambioEstadoReporte(BaseModel):
    estado: Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


@router.get("/reportes")
def listar_reportes(
    estado: Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO", "EXPIRADO"] | None = None,
    limite: int = Query(100, ge=1, le=300),
    id_reporte: int | None = Query(None, ge=1),
):
    """Todos los reportes (no solo los vigentes), del más reciente al más antiguo.
    Con id_reporte trae solo ese (para moderarlo desde el mapa del panel)."""
    condiciones, parametros = [], []
    if estado:
        condiciones.append("r.estado = %s")
        parametros.append(estado)
    if id_reporte:
        condiciones.append("r.id_reporte = %s")
        parametros.append(id_reporte)
    filtro = "WHERE " + " AND ".join(condiciones) if condiciones else ""
    filas = consultar(
        f"""
        SELECT r.id_reporte, c.nombre AS categoria, c.codigo AS categoria_codigo, c.color_hex,
               r.estado, r.visibilidad, r.descripcion, r.direccion_referencia AS direccion,
               COALESCE(l.nombre, cm.nombre) AS zona,
               r.fecha_creacion, r.fecha_expiracion,
               (r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()) AS vencido,
               r.total_confirmaciones, r.total_desmentidos,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               (
                   SELECT i.url_archivo FROM reporte_imagen i
                   WHERE i.id_reporte = r.id_reporte
                   ORDER BY i.orden LIMIT 1
               ) AS imagen,
               (
                   SELECT COUNT(*) FROM comentario co
                   WHERE co.id_reporte = r.id_reporte AND co.estado = 'PUBLICADO'
               ) AS total_comentarios,
               (
                   SELECT COUNT(*) FROM comentario co
                   WHERE co.id_reporte = r.id_reporte AND co.estado = 'OCULTO'
               ) AS comentarios_ocultos
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        {filtro}
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (*parametros, limite),
    )
    for fila in filas:
        fila["vencido"] = bool(fila["vencido"])
        fila["autor"] = alias_autor(fila["id_reporte"])
    return filas


def _archivos_del_reporte(cursor, id_reporte: int) -> list[str]:
    """Evidencias del reporte y fotos de sus comentarios."""
    cursor.execute("SELECT url_archivo FROM reporte_imagen WHERE id_reporte = %s", (id_reporte,))
    archivos = [f["url_archivo"] for f in cursor.fetchall()]
    cursor.execute(
        """
        SELECT i.url_archivo FROM comentario_imagen i
        JOIN comentario c ON c.id_comentario = i.id_comentario
        WHERE c.id_reporte = %s
        """,
        (id_reporte,),
    )
    return archivos + [f["url_archivo"] for f in cursor.fetchall()]


@router.delete("/reportes/{id_reporte}")
def eliminar_reporte(id_reporte: int = PathParam(ge=1), admin: dict = Depends(usuario_admin)):
    """Elimina el reporte para siempre: sus votos, comentarios, avisos e historial se borran
    en cascada (claves foráneas ON DELETE CASCADE) y sus fotos se borran del disco.

    Como el historial del reporte desaparece con él, la eliminación queda en el registro
    de la API (quién, cuándo y qué reporte).
    """
    with transaccion() as cursor:
        cursor.execute("SELECT id_reporte, estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (id_reporte,))
        reporte = cursor.fetchone()
        if reporte is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        archivos = _archivos_del_reporte(cursor, id_reporte)
        cursor.execute("DELETE FROM reporte WHERE id_reporte = %s", (id_reporte,))
    # Los archivos se borran después de confirmar: si la BD fallara, las fotos siguen ahí.
    borrados = borrar_archivos(archivos)
    log.warning(
        "Reporte #%s (estado %s) eliminado por el admin #%s; %s archivos borrados",
        id_reporte, reporte["estado"], admin["id_usuario"], borrados,
    )
    grafo.sincronizar_sin_fallar()
    return {"id_reporte": id_reporte, "eliminado": True, "archivos_borrados": borrados}


@router.patch("/reportes/{id_reporte}/estado")
def cambiar_estado_reporte(
    datos: CambioEstadoReporte,
    id_reporte: int = PathParam(ge=1),
    admin: dict = Depends(usuario_admin),
):
    """Modera un reporte (p. ej. descartar uno falso); el cambio queda en reporte_estado_historial."""
    motivo = (datos.motivo or "").strip()
    motivo = f"Panel de administración: {motivo}" if motivo else "Cambio desde el panel de administración"

    with transaccion() as cursor:
        cursor.execute("SELECT estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (id_reporte,))
        fila = cursor.fetchone()
        if fila is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        if fila["estado"] == datos.estado:
            raise HTTPException(status_code=409, detail=f"El reporte ya está {datos.estado.lower()}")
        cambiar_estado(cursor, id_reporte, fila["estado"], datos.estado, admin["id_usuario"], motivo)
        if datos.estado == "DESCARTADO":
            moderacion.cerrar_denuncias(cursor, "reporte", id_reporte, "ATENDIDA", admin["id_usuario"])
    return {"id_reporte": id_reporte, "estado": datos.estado}


@router.post("/reportes/{id_reporte}/suspender-autor")
def suspender_autor(id_reporte: int = PathParam(ge=1)):
    """Suspende a quien creó el reporte sin revelar su identidad en el panel."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_usuario FROM reporte WHERE id_reporte = %s", (id_reporte,))
        reporte = cursor.fetchone()
        if reporte is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        moderacion.suspender_autor(cursor, reporte["id_usuario"], "Quien creó este reporte ya está suspendido")
    return {"id_reporte": id_reporte, "autor": alias_autor(id_reporte), "estado_autor": "SUSPENDIDO"}


@router.get("/reportes/{id_reporte}/comentarios")
def listar_comentarios_reporte(id_reporte: int = PathParam(ge=1)):
    """Todos los comentarios del reporte (también ocultos y eliminados), con alias como en la app."""
    reporte = consultar("SELECT id_usuario FROM reporte WHERE id_reporte = %s", (id_reporte,))
    if not reporte:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    filas = comentarios_de_reporte(id_reporte)
    alias = mapa_alias(id_reporte, reporte[0]["id_usuario"], filas)
    return [
        {
            "id_comentario": f["id_comentario"],
            "id_comentario_padre": f["id_comentario_padre"],
            "autor": alias.get(f["id_usuario"]),
            "contenido": f["contenido"],
            "imagen": f["imagen"],
            "estado": f["estado"],
            "fecha_creacion": f["fecha_creacion"],
        }
        for f in filas
    ]
