"""Moderación de reportes desde el panel.

Igual que en el resto de la API, el autor se muestra con su alias: el panel puede
suspender a quien reportó sin conocer su nombre.
"""

import logging
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.comun.alias import alias_autor, mapa_alias
from app.comun.archivos import borrar_archivos
from app.comun.cache import cache_mapa
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


Estado = Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO", "EXPIRADO"]

# Estado que ve el panel: un reporte activo (pendiente o validado) cuya vigencia
# terminó está EXPIRADO, aunque en la tabla siga con su estado anterior.
ESTADO_EFECTIVO = """CASE WHEN r.estado IN ('PENDIENTE', 'VALIDADO')
                          AND r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()
                     THEN 'EXPIRADO' ELSE r.estado END"""

# A qué estados puede pasar un reporte desde el panel, según su estado efectivo.
# Resuelto es final; un descartado por error se puede restaurar mientras siga vigente,
# y uno expirado solo se puede descartar (p. ej. era falso y no debe contar en el análisis).
TRANSICIONES: dict[str, tuple[str, ...]] = {
    "PENDIENTE": ("VALIDADO", "RESUELTO", "DESCARTADO"),
    "VALIDADO": ("RESUELTO", "DESCARTADO"),
    "DESCARTADO": ("PENDIENTE",),
    "EXPIRADO": ("DESCARTADO",),
    "RESUELTO": (),
}


def estado_efectivo(estado: str, vencido: bool) -> str:
    return "EXPIRADO" if vencido and estado in ("PENDIENTE", "VALIDADO") else estado


def condiciones_busqueda(q, categoria, comuna, desde, hasta) -> tuple[list[str], list]:
    """Filtros del listado: #número o texto, categoría, comuna y rango de fechas."""
    condiciones, parametros = [], []
    texto = (q or "").strip()
    if texto:
        numero = texto.lstrip("#")
        if numero.isdigit():
            condiciones.append("r.id_reporte = %s")
            parametros.append(int(numero))
        else:
            patron = f"%{texto}%"
            condiciones.append("(r.descripcion LIKE %s OR r.direccion_referencia LIKE %s OR l.nombre LIKE %s)")
            parametros += [patron, patron, patron]
    if categoria:
        condiciones.append("c.codigo = %s")
        parametros.append(categoria)
    if comuna:
        condiciones.append("r.id_comuna = %s")
        parametros.append(comuna)
    if desde:
        condiciones.append("r.fecha_creacion >= %s")
        parametros.append(desde)
    if hasta:
        condiciones.append("r.fecha_creacion < DATE_ADD(%s, INTERVAL 1 DAY)")
        parametros.append(hasta)
    return condiciones, parametros


_TABLAS_REPORTE = """
    FROM reporte r
    JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
    LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
    LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
"""


@router.get("/reportes")
def listar_reportes(
    estado: Estado | None = None,
    q: str | None = Query(None, max_length=80, description="#número o texto de la descripción o dirección"),
    categoria: str | None = Query(None, pattern=r"^[A-Z_]{1,40}$"),
    comuna: int | None = Query(None, ge=1),
    desde: date | None = None,
    hasta: date | None = None,
    orden: Literal["recientes", "prioridad"] = "recientes",
    pagina: int = Query(1, ge=1),
    limite: int = Query(25, ge=1, le=100),
    id_reporte: int | None = Query(None, ge=1),
):
    """Reportes del panel con su estado efectivo, paginados.

    - `estado` filtra por el estado efectivo (EXPIRADO incluye los activos vencidos).
    - `orden=prioridad` deja primero los que más necesitan revisión: más denuncias
      pendientes y más desmentidos.
    - `conteos` trae cuántos hay en cada estado con los mismos filtros (sin el de estado),
      para los contadores de las pestañas.
    - Con `id_reporte` trae solo ese (para moderarlo desde el mapa del panel).
    """
    condiciones, parametros = condiciones_busqueda(q, categoria, comuna, desde, hasta)
    if id_reporte:
        condiciones.append("r.id_reporte = %s")
        parametros.append(id_reporte)
    base = " AND ".join(condiciones) or "TRUE"

    conteos = {e: 0 for e in TRANSICIONES}
    for fila in consultar(
        f"SELECT {ESTADO_EFECTIVO} AS estado, COUNT(*) AS total {_TABLAS_REPORTE} WHERE {base} GROUP BY 1",
        tuple(parametros),
    ):
        conteos[fila["estado"]] = int(fila["total"])

    filtro, valores = base, list(parametros)
    if estado:
        filtro += f" AND {ESTADO_EFECTIVO} = %s"
        valores.append(estado)
    orden_sql = (
        "denuncias_pendientes DESC, r.total_desmentidos DESC, r.fecha_creacion DESC"
        if orden == "prioridad" else "r.fecha_creacion DESC"
    )
    filas = consultar(
        f"""
        SELECT r.id_reporte, c.nombre AS categoria, c.codigo AS categoria_codigo, c.color_hex,
               {ESTADO_EFECTIVO} AS estado, r.visibilidad, r.descripcion, r.direccion_referencia AS direccion,
               COALESCE(l.nombre, cm.nombre) AS zona, cm.nombre AS comuna,
               r.fecha_creacion, r.fecha_expiracion,
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
               ) AS comentarios_ocultos,
               (
                   SELECT COUNT(*) FROM denuncia d
                   WHERE d.id_reporte = r.id_reporte AND d.estado = 'PENDIENTE'
               ) AS denuncias_pendientes
        {_TABLAS_REPORTE}
        WHERE {filtro}
        ORDER BY {orden_sql}
        LIMIT %s OFFSET %s
        """,
        (*valores, limite, (pagina - 1) * limite),
    )
    for fila in filas:
        fila["autor"] = alias_autor(fila["id_reporte"])
        fila["acciones"] = list(TRANSICIONES[fila["estado"]])
    total = conteos[estado] if estado else sum(conteos.values())
    return {"reportes": filas, "total": total, "pagina": pagina, "por_pagina": limite, "conteos": conteos}


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
    cache_mapa.vaciar()
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
        cursor.execute(
            "SELECT estado, (fecha_expiracion IS NOT NULL AND fecha_expiracion <= NOW()) AS vencido "
            "FROM reporte WHERE id_reporte = %s FOR UPDATE",
            (id_reporte,),
        )
        fila = cursor.fetchone()
        if fila is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        actual = estado_efectivo(fila["estado"], bool(fila["vencido"]))
        if datos.estado not in TRANSICIONES[actual]:
            raise HTTPException(
                status_code=409, detail=f"Un reporte {actual.lower()} no puede pasar a {datos.estado.lower()}"
            )
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
