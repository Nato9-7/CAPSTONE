"""El "chat" del grupo: los reportes que sus miembros compartieron en él."""

from fastapi import APIRouter, Depends, Path as PathParam, Query

from app.comun.alias import alias_autor
from app.comun.formato import iso
from app.db import consultar
from app.seguridad import usuario_actual
from app.servicios.grupos import membresia

router = APIRouter()


def _reporte_json(fila: dict, id_usuario: int) -> dict:
    return {
        "id_reporte": fila["id_reporte"],
        "autor": alias_autor(fila["id_reporte"]),
        "es_mio": fila["id_usuario"] == id_usuario,
        "visibilidad": fila["visibilidad"],
        "categoria_codigo": fila["categoria_codigo"],
        "categoria": fila["categoria"],
        "color_hex": fila["color_hex"],
        "latitud": float(fila["latitud"]),
        "longitud": float(fila["longitud"]),
        "direccion": fila["direccion"],
        "descripcion": fila["descripcion"],
        "estado": fila["estado"],
        "fecha_creacion": iso(fila["fecha_creacion"]),
        "fecha_publicacion": iso(fila["fecha_publicacion"]),
        "total_comentarios": int(fila["total_comentarios"]),
        "imagen": fila["imagen"],
    }


@router.get("/{id_grupo}/reportes")
def listar_reportes_grupo(
    id_grupo: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
    antes_de: int | None = Query(None, ge=1, description="id_reporte del último reporte recibido, para paginar"),
    limite: int = Query(30, ge=1, le=100),
):
    """Los reportes compartidos en el grupo, del más reciente al más antiguo.

    El autor aparece con el mismo alias que en el detalle del reporte, así la
    tarjeta del chat y la conversación del reporte coinciden.
    """
    id_usuario = usuario["id_usuario"]
    membresia(id_grupo, id_usuario)
    condicion_pagina = "AND gr.id_reporte < %s" if antes_de else ""
    parametros = (id_grupo, antes_de, limite) if antes_de else (id_grupo, limite)
    filas = consultar(
        f"""
        SELECT r.id_reporte, r.id_usuario, r.visibilidad,
               c.codigo AS categoria_codigo, c.nombre AS categoria, c.color_hex,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               CASE
                   WHEN r.estado IN ('PENDIENTE', 'VALIDADO')
                        AND r.fecha_expiracion IS NOT NULL
                        AND r.fecha_expiracion <= NOW() THEN 'EXPIRADO'
                   ELSE r.estado
               END AS estado,
               r.fecha_creacion, gr.fecha_publicacion,
               (SELECT COUNT(*) FROM comentario co
                 WHERE co.id_reporte = r.id_reporte AND co.estado = 'PUBLICADO') AS total_comentarios,
               (SELECT i.url_archivo FROM reporte_imagen i
                 WHERE i.id_reporte = r.id_reporte ORDER BY i.orden LIMIT 1) AS imagen
        FROM grupo_reporte gr
        JOIN reporte r ON r.id_reporte = gr.id_reporte
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE gr.id_grupo = %s AND r.estado <> 'DESCARTADO'
          {condicion_pagina}
        ORDER BY gr.id_reporte DESC
        LIMIT %s
        """,
        parametros,
    )
    return [_reporte_json(fila, id_usuario) for fila in filas]
