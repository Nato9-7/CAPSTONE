"""Alertas recibidas por el vecino (pestaña Alertas de la app)."""

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query

from app.comun.formato import decimal, entero, iso
from app.db import consultar, ejecutar
from app.rutas.usuarios.zonas import tipo_de_nombre
from app.seguridad import usuario_actual

router = APIRouter()

# Los avisos de comentarios no van en esta pestaña: se marcan leídos al abrir
# la conversación del reporte.
_FILTRO_PESTANA = """
    n.id_usuario = %s
    AND n.motivo NOT IN ('COMENTARIO', 'RESPUESTA')
    AND r.estado <> 'DESCARTADO'
    -- El aviso de un reporte privado se oculta si su grupo se eliminó.
    AND (r.visibilidad = 'PUBLICO' OR g.activo = 1)
"""


def _notificacion_json(fila: dict) -> dict:
    """Mismos nombres de campo que /api/reportes/cercanos, para que la app
    reutilice el modelo que ya tiene en vez de inventar otro."""
    zona = None
    if fila["id_zona_segura"] is not None:
        zona = {
            "id_zona_segura": fila["id_zona_segura"],
            "nombre": fila["zona_nombre"],
            "tipo": tipo_de_nombre(fila["zona_nombre"] or ""),
            "radio_metros": entero(fila["zona_radio"]),
        }
    return {
        "id_notificacion": fila["id_notificacion"],
        "motivo": fila["motivo"],
        "distancia_metros": entero(fila["distancia_metros"]),
        "fecha_envio": iso(fila["fecha_envio"]),
        "fecha_lectura": iso(fila["fecha_lectura"]),
        "leida": fila["fecha_lectura"] is not None,
        # La zona puede venir vacía aunque el aviso sea de zona: fk_notif_zona es
        # ON DELETE SET NULL, así que una alerta vieja puede quedar sin zona.
        "zona": zona,
        # Solo en los avisos de motivo GRUPO.
        "grupo": {"id_grupo": fila["id_grupo"], "nombre": fila["grupo_nombre"]} if fila["id_grupo"] is not None else None,
        "reporte": {
            "id_reporte": fila["id_reporte"],
            "categoria_codigo": fila["categoria_codigo"],
            "categoria": fila["categoria"],
            "color_hex": fila["color_hex"],
            "latitud": decimal(fila["latitud"]),
            "longitud": decimal(fila["longitud"]),
            "direccion": fila["direccion"],
            "descripcion": fila["descripcion"],
            "estado": fila["estado"],
            "fecha_creacion": iso(fila["fecha_creacion"]),
            "total_confirmaciones": fila["total_confirmaciones"],
            "total_desmentidos": fila["total_desmentidos"],
            "zona": fila["reporte_zona"],
        },
    }


@router.get("/")
def listar_notificaciones(
    usuario: dict = Depends(usuario_actual),
    limite: int = Query(50, ge=1, le=200),
    solo_no_leidas: bool = Query(False),
):
    """Alertas recibidas por el usuario, de la más reciente a la más antigua."""
    condicion_leidas = "AND n.fecha_lectura IS NULL" if solo_no_leidas else ""
    filas = consultar(
        f"""
        SELECT n.id_notificacion, n.motivo, n.distancia_metros,
               n.fecha_envio, n.fecha_lectura,
               n.id_zona_segura, z.nombre AS zona_nombre, z.radio_metros AS zona_radio,
               n.id_grupo, g.nombre AS grupo_nombre,
               r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
               c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
               ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               CASE
                   WHEN r.estado IN ('PENDIENTE', 'VALIDADO')
                        AND r.fecha_expiracion IS NOT NULL
                        AND r.fecha_expiracion <= NOW() THEN 'EXPIRADO'
                   ELSE r.estado
               END AS estado,
               r.fecha_creacion, r.total_confirmaciones, r.total_desmentidos,
               COALESCE(l.nombre, cm.nombre) AS reporte_zona
        FROM notificacion n
        JOIN reporte r ON r.id_reporte = n.id_reporte
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        LEFT JOIN zona_segura z ON z.id_zona_segura = n.id_zona_segura
        LEFT JOIN grupo g ON g.id_grupo = n.id_grupo
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        WHERE {_FILTRO_PESTANA}
          {condicion_leidas}
        ORDER BY n.fecha_envio DESC
        LIMIT %s
        """,
        (usuario["id_usuario"], limite),
    )
    no_leidas = consultar(
        f"""
        SELECT COUNT(*) AS total
        FROM notificacion n
        JOIN reporte r ON r.id_reporte = n.id_reporte
        LEFT JOIN grupo g ON g.id_grupo = n.id_grupo
        WHERE {_FILTRO_PESTANA}
          AND n.fecha_lectura IS NULL
        """,
        (usuario["id_usuario"],),
    )
    return {
        "total": len(filas),
        "no_leidas": no_leidas[0]["total"] if no_leidas else 0,
        "notificaciones": [_notificacion_json(f) for f in filas],
    }


@router.post("/{id_notificacion}/leida", status_code=204)
def marcar_leida(
    id_notificacion: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Marca una alerta como leída. Si ya lo estaba, no se pisa la fecha original."""
    filas = consultar(
        "SELECT id_notificacion FROM notificacion WHERE id_notificacion = %s AND id_usuario = %s",
        (id_notificacion, usuario["id_usuario"]),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="La alerta no existe")
    ejecutar(
        """
        UPDATE notificacion SET fecha_lectura = NOW()
        WHERE id_notificacion = %s AND id_usuario = %s AND fecha_lectura IS NULL
        """,
        (id_notificacion, usuario["id_usuario"]),
    )
    return None


@router.post("/leidas", status_code=204)
def marcar_todas_leidas(usuario: dict = Depends(usuario_actual)):
    """Para el gesto de "marcar todo como leído" al abrir la pestaña Alertas."""
    ejecutar(
        """
        UPDATE notificacion SET fecha_lectura = NOW()
        WHERE id_usuario = %s AND fecha_lectura IS NULL
          AND motivo NOT IN ('COMENTARIO', 'RESPUESTA')
        """,
        (usuario["id_usuario"],),
    )
    return None
