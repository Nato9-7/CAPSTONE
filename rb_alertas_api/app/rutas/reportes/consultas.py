"""Listados de reportes: mapa, alertas cercanas, zonas de riesgo, mapa de calor e historial propio."""

import mysql.connector
from fastapi import APIRouter, Depends, Query

from app.comun.geo import PUNTO_SQL, punto_wkt
from app.db import consultar
from app.seguridad import usuario_actual, usuario_opcional
from app.servicios import incidentes, zonas_riesgo

router = APIRouter()

# Radio de alertas cercanas cuando el usuario no tiene preferencia guardada
# (usuario_preferencia.radio_alerta_metros) ni lo pide explícitamente.
RADIO_ALERTA_POR_DEFECTO_METROS = 2000

# Reportes que se consideran para zonas de riesgo y mapa de calor.
MAXIMO_REPORTES_RECIENTES = 3000

_COLUMNAS_MAPA = """
    r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
    c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
    ST_Longitude(r.ubicacion) AS longitud,
    r.direccion_referencia AS direccion, r.descripcion, r.estado,
    r.fecha_creacion, r.total_confirmaciones, r.total_desmentidos
"""

_VIGENTE_Y_PUBLICO = """
    r.estado IN ('PENDIENTE', 'VALIDADO')
    AND r.visibilidad = 'PUBLICO'
    AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())
"""


def _radio_alerta_metros(usuario: dict | None, radio_km: float | None) -> int:
    """Radio a consultar: el que pide el cliente, si no el del usuario, si no el estándar."""
    if radio_km is not None:
        return int(radio_km * 1000)
    if usuario is not None:
        try:
            filas = consultar(
                "SELECT radio_alerta_metros FROM usuario_preferencia WHERE id_usuario = %s",
                (usuario["id_usuario"],),
            )
        except mysql.connector.Error:
            # Sin tabla de preferencias la pantalla igual funciona con el radio estándar.
            filas = []
        if filas and filas[0]["radio_alerta_metros"]:
            return int(filas[0]["radio_alerta_metros"])
    return RADIO_ALERTA_POR_DEFECTO_METROS


def _reportes_recientes(dias: int) -> list[dict]:
    """Reportes públicos de los últimos `dias` para zonas de riesgo y mapa de calor.

    Incluye los ya resueltos o expirados (un robo de hace dos semanas sigue
    diciendo algo del lugar), pero no los descartados por la comunidad.
    """
    return consultar(
        """
        SELECT r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria, c.color_hex,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.fecha_creacion
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.estado <> 'DESCARTADO'
          AND r.visibilidad = 'PUBLICO'
          AND r.fecha_creacion >= NOW() - INTERVAL %s DAY
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (dias, MAXIMO_REPORTES_RECIENTES),
    )


@router.get("/categorias")
def listar_categorias():
    return consultar(
        """
        SELECT id_categoria, codigo, nombre, icono, color_hex
        FROM categoria_incidente
        WHERE activa = 1
        ORDER BY id_categoria
        """
    )


@router.get("/")
def listar_reportes(limite: int = Query(200, ge=1, le=500)):
    """Incidentes vigentes para dibujar en el mapa, del más reciente al más antiguo.

    Los reportes del mismo hecho se juntan en uno solo (ver app/servicios/incidentes.py):
    cada elemento trae total_reportes e ids_reportes.
    """
    filas = consultar(
        f"""
        SELECT {_COLUMNAS_MAPA}
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE {_VIGENTE_Y_PUBLICO}
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (limite,),
    )
    return incidentes.resumir(filas)


@router.get("/cercanos")
def listar_reportes_cercanos(
    usuario: dict | None = Depends(usuario_opcional),
    latitud: float = Query(ge=-90, le=90),
    longitud: float = Query(ge=-180, le=180),
    radio_km: float | None = Query(None, gt=0, le=50),
    limite: int = Query(50, ge=1, le=200),
):
    """Reportes vigentes alrededor del punto, del más reciente al más antiguo.

    Alimenta la pantalla Alertas: cada fila trae la distancia en metros al punto
    consultado para poder mostrar "a 500 m" sin recalcular en el cliente.

    Sin `radio_km`, se usa el radio que el usuario guardó en sus preferencias;
    si no tiene sesión o no lo ha configurado, RADIO_ALERTA_POR_DEFECTO_METROS.
    La respuesta devuelve el radio aplicado para poder mostrarlo en pantalla.
    """
    radio_metros = _radio_alerta_metros(usuario, radio_km)
    punto = punto_wkt(latitud, longitud)
    reportes = consultar(
        f"""
        SELECT {_COLUMNAS_MAPA},
               ST_Distance(r.ubicacion, {PUNTO_SQL}) AS distancia_metros
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE {_VIGENTE_Y_PUBLICO}
          AND ST_Distance(r.ubicacion, {PUNTO_SQL}) <= %s
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (punto, punto, radio_metros, limite),
    )
    # Un elemento por incidente: varios vecinos reportando lo mismo es una sola alerta.
    agrupados = incidentes.resumir(reportes)
    return {
        "radio_metros": radio_metros,
        "total": len(agrupados),
        "reportes": agrupados,
    }


@router.get("/zonas-riesgo")
def listar_zonas_riesgo(dias: int = Query(60, ge=7, le=365)):
    """Zonas donde se repiten robos, asaltos o accidentes, para marcarlas en el mapa.

    Ver app/servicios/zonas_riesgo.py.
    """
    return {"dias": dias, "zonas": zonas_riesgo.calcular(_reportes_recientes(dias))}


@router.get("/calor")
def mapa_de_calor(
    dias: int = Query(60, ge=1, le=365),
    categoria: str | None = Query(None, pattern=r"^[A-Z_]{1,40}$"),
):
    """Hechos por celda de ~110 m para dibujar el mapa de calor.

    Sin `categoria`, robos, accidentes y demás categorías de riesgo; con ella,
    solo esa. Los reportes del mismo hecho cuentan una vez.
    """
    return {"dias": dias, "puntos": zonas_riesgo.puntos_calor(_reportes_recientes(dias), categoria)}


@router.get("/mios")
def listar_mis_reportes(
    usuario: dict = Depends(usuario_actual),
    limite: int = Query(100, ge=1, le=300),
):
    """Historial de reportes de quien consulta, del más reciente al más antiguo.

    `estado_visual` traduce el estado de la BD a lo que ve el usuario:
    RESUELTA, DESCARTADA, VENCIDA (vigencia cumplida sin resolver) o ACTIVA.
    """
    return consultar(
        """
        SELECT r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
               c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
               ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               r.estado, r.fecha_creacion, r.fecha_expiracion,
               r.total_confirmaciones, r.total_desmentidos,
               COALESCE(l.nombre, cm.nombre) AS zona,
               CASE
                   WHEN r.estado = 'RESUELTO' THEN 'RESUELTA'
                   WHEN r.estado = 'DESCARTADO' THEN 'DESCARTADA'
                   WHEN r.estado = 'EXPIRADO' THEN 'VENCIDA'
                   WHEN r.fecha_expiracion IS NOT NULL
                        AND r.fecha_expiracion <= NOW() THEN 'VENCIDA'
                   ELSE 'ACTIVA'
               END AS estado_visual,
               (
                   SELECT i.url_archivo FROM reporte_imagen i
                   WHERE i.id_reporte = r.id_reporte
                   ORDER BY i.orden LIMIT 1
               ) AS imagen
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        WHERE r.id_usuario = %s
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (usuario["id_usuario"], limite),
    )
