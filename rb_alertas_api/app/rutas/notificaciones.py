from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query

from app.db import consultar, ejecutar
from app.seguridad import usuario_actual
from app.rutas.zonas import tipo_de_nombre

router = APIRouter()


def _fila_a_json(fila: dict) -> dict:
    """Mismos nombres de campo que /api/reportes/cercanos, para que la app
    reutilice el modelo que ya tiene en vez de inventar otro."""
    zona = None
    if fila["id_zona_segura"] is not None:
        zona = {
            "id_zona_segura": fila["id_zona_segura"],
            "nombre": fila["zona_nombre"],
            "tipo": tipo_de_nombre(fila["zona_nombre"] or ""),
            "radio_metros": int(fila["zona_radio"]) if fila["zona_radio"] is not None else None,
        }
    return {
        "id_notificacion": fila["id_notificacion"],
        "motivo": fila["motivo"],
        "distancia_metros": int(fila["distancia_metros"]) if fila["distancia_metros"] is not None else None,
        "fecha_envio": fila["fecha_envio"].isoformat() if fila["fecha_envio"] else None,
        "fecha_lectura": fila["fecha_lectura"].isoformat() if fila["fecha_lectura"] else None,
        "leida": fila["fecha_lectura"] is not None,
        # La zona viaja aunque se haya borrado: fk_notif_zona es ON DELETE SET NULL,
        # asi que una alerta vieja puede quedar sin zona y la app muestra solo el reporte.
        "zona": zona,
        "reporte": {
            "id_reporte": fila["id_reporte"],
            "categoria_codigo": fila["categoria_codigo"],
            "categoria": fila["categoria"],
            "color_hex": fila["color_hex"],
            "latitud": float(fila["latitud"]) if fila["latitud"] is not None else None,
            "longitud": float(fila["longitud"]) if fila["longitud"] is not None else None,
            "direccion": fila["direccion"],
            "descripcion": fila["descripcion"],
            "estado": fila["estado"],
            "fecha_creacion": fila["fecha_creacion"].isoformat() if fila["fecha_creacion"] else None,
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
    """Alertas recibidas por el usuario, de la mas reciente a la mas antigua.
    """
    condicion_leidas = "AND n.fecha_lectura IS NULL" if solo_no_leidas else ""
    filas = consultar(
        f"""
        SELECT n.id_notificacion, n.motivo, n.distancia_metros,
               n.fecha_envio, n.fecha_lectura,
               n.id_zona_segura, z.nombre AS zona_nombre, z.radio_metros AS zona_radio,
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
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        WHERE n.id_usuario = %s
          AND r.estado <> 'DESCARTADO'
          {condicion_leidas}
        ORDER BY n.fecha_envio DESC
        LIMIT %s
        """,
        (usuario["id_usuario"], limite),
    )

    no_leidas = consultar(
        """
        SELECT COUNT(*) AS total
        FROM notificacion n
        JOIN reporte r ON r.id_reporte = n.id_reporte
        WHERE n.id_usuario = %s AND n.fecha_lectura IS NULL AND r.estado <> 'DESCARTADO'
        """,
        (usuario["id_usuario"],),
    )

    return {
        "total": len(filas),
        "no_leidas": no_leidas[0]["total"] if no_leidas else 0,
        "notificaciones": [_fila_a_json(f) for f in filas],
    }


@router.post("/{id_notificacion}/leida", status_code=204)
def marcar_leida(
    id_notificacion: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Marca una alerta como leida. Si ya lo estaba, no se pisa la fecha original."""
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
    """Para el gesto de "marcar todo como leido" al abrir la pestana Alertas."""
    ejecutar(
        "UPDATE notificacion SET fecha_lectura = NOW() WHERE id_usuario = %s AND fecha_lectura IS NULL",
        (usuario["id_usuario"],),
    )
    return None
