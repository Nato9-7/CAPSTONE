"""Comuna y localidad a las que pertenece un punto del mapa."""

import mysql.connector

from app.comun.geo import PUNTO_SQL
from app.db import consultar

# Radio máximo desde el centroide de una comuna operativa para asignarle un reporte.
RADIO_MAXIMO_COMUNA_METROS = 40_000


def _primer_id(sql: str, parametros: tuple, columna: str) -> int | None:
    try:
        filas = consultar(sql, parametros)
    except mysql.connector.Error:
        # Sin polígonos/centroides cargados o función espacial no soportada:
        # se sigue con el siguiente criterio.
        return None
    return filas[0][columna] if filas else None


def resolver_comuna(punto_wkt: str) -> int | None:
    """Comuna cuyo límite contiene el punto; si no, la operativa cuyo centroide esté a menos de
    RADIO_MAXIMO_COMUNA_METROS. None si el punto queda fuera de toda comuna con cobertura."""
    id_comuna = _primer_id(
        f"SELECT id_comuna FROM comuna WHERE limite IS NOT NULL AND ST_Contains(limite, {PUNTO_SQL}) LIMIT 1",
        (punto_wkt,),
        "id_comuna",
    )
    if id_comuna is not None:
        return id_comuna
    return _primer_id(
        f"""
        SELECT id_comuna FROM comuna
        WHERE operativa = 1 AND centroide IS NOT NULL
          AND ST_Distance(centroide, {PUNTO_SQL}) <= %s
        ORDER BY ST_Distance(centroide, {PUNTO_SQL})
        LIMIT 1
        """,
        (punto_wkt, RADIO_MAXIMO_COMUNA_METROS, punto_wkt),
        "id_comuna",
    )


def resolver_localidad(punto_wkt: str, id_comuna: int) -> int | None:
    return _primer_id(
        f"""
        SELECT id_localidad FROM localidad
        WHERE id_comuna = %s AND activa = 1 AND limite IS NOT NULL
          AND ST_Contains(limite, {PUNTO_SQL})
        LIMIT 1
        """,
        (id_comuna, punto_wkt),
        "id_localidad",
    )
