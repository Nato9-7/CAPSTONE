"""Dónde ocurre más: lugares con cuántos hechos de cada categoría tuvieron.

Un lugar es la localidad del reporte o, si no tiene, su comuna. Los reportes
descartados no cuentan: eran falsos o no correspondían.
"""

from datetime import datetime, timedelta

from app.servicios.grafo import conexion
from app.servicios.grafo.red import nodo

CODIGO_CATEGORIA = r"^[A-Z_]{1,40}$"


def desde_dias(dias: int | None) -> str | None:
    """Fecha ISO de hace `dias` días, para filtrar la actividad reciente (None = toda la historia)."""
    if not dias:
        return None
    return (datetime.now() - timedelta(days=dias)).isoformat()


def _categoria(fila: dict) -> dict:
    return {
        "id": fila["categoria"]["id"],
        "codigo": fila["categoria"].get("codigo"),
        "nombre": fila["categoria"].get("nombre"),
        "color": fila["categoria"].get("color"),
        "total": fila["total"],
        "reportes": fila["reportes"],
    }


def zonas_calientes(categoria: str | None, desde: str | None) -> list[dict]:
    """Lugares con su total de hechos y el desglose por categoría, del que tiene más al que menos.

    Cuenta hechos, no reportes: si cinco vecinos reportaron el mismo robo, el
    grafo los tiene bajo un mismo Incidente y suma uno (igual que las zonas de
    riesgo del mapa). Un reporte sin Incidente es un hecho por sí solo.
    `reportes` guarda el total de reportes para mostrarlo como referencia.
    """
    filas = conexion.consultar_grafo(
        """
        MATCH (r:Reporte)-[:OCURRIO_EN]->(lugar), (r)-[:ES_DE]->(cat:Categoria)
        WHERE r.estado <> 'DESCARTADO'
          AND ($desde IS NULL OR r.fecha_creacion >= $desde)
          AND ($categoria IS NULL OR cat.codigo = $categoria)
        OPTIONAL MATCH (inc:Incidente)-[:AGRUPA]->(r)
        WITH lugar, cat, count(DISTINCT coalesce(inc.id, r.id)) AS total, count(r) AS reportes
        OPTIONAL MATCH (lugar)-[:PERTENECE_A]->(comuna:Comuna)
        RETURN labels(lugar)[0] AS tipo, properties(lugar) AS lugar, comuna.nombre AS comuna,
               properties(cat) AS categoria, total, reportes
        """,
        categoria=categoria,
        desde=desde,
    )
    lugares: dict[str, dict] = {}
    for f in filas:
        lugar = lugares.setdefault(
            f"{f['tipo']}:{f['lugar']['id']}",
            {"tipo": f["tipo"], "datos": f["lugar"], "comuna": f["comuna"], "total": 0, "reportes": 0, "por_categoria": []},
        )
        lugar["total"] += f["total"]
        lugar["reportes"] += f["reportes"]
        lugar["por_categoria"].append(_categoria(f))

    lista = sorted(lugares.values(), key=lambda l: (-l["total"], str(l["datos"].get("nombre"))))
    maximo = lista[0]["total"] if lista else 1
    for lugar in lista:
        lugar["por_categoria"].sort(key=lambda c: -c["total"])
        # 0 a 1: qué tan "caliente" es el lugar comparado con el que tiene más.
        lugar["intensidad"] = round(lugar["total"] / maximo, 3)
    return lista


def nodo_lugar(lugar: dict) -> dict:
    datos = {
        **lugar["datos"],
        "total": lugar["total"],
        "reportes": lugar["reportes"],
        "intensidad": lugar["intensidad"],
        "comuna": lugar["comuna"],
        "por_categoria": lugar["por_categoria"],
    }
    return nodo(lugar["tipo"], datos)
