"""Puntos geográficos para las consultas espaciales de MySQL."""

# Con SRID 4326 MySQL lee el WKT como latitud-longitud; se fija el orden.
PUNTO_SQL = "ST_GeomFromText(%s, 4326, 'axis-order=long-lat')"


def punto_wkt(latitud: float, longitud: float) -> str:
    """Punto en WKT (longitud primero), para usar como parámetro de PUNTO_SQL."""
    return f"POINT({longitud} {latitud})"
