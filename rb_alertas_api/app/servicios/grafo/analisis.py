"""Análisis del panel sobre el grafo de Neo4j: cuándo y dónde ocurren los hechos.

Todas las cifras cuentan HECHOS, no reportes: si cinco vecinos reportaron el mismo
robo, el grafo los tiene bajo un mismo Incidente y suma uno (igual que el mapa).
Los reportes descartados no cuentan: eran falsos o no correspondían.

Cada análisis compara el período pedido (los últimos N días) con los N días
anteriores, para decir si un lugar o una categoría va en alza o a la baja.
"""

from datetime import date, timedelta

from app.servicios.grafo import conexion

# Variación mínima (en hechos) para decir que algo sube o baja y no que se mantiene.
UMBRAL_CAMBIO = 1

# Filtros comunes a todas las consultas; $desde es el inicio del período anterior.
_FILTRO = """
    r.estado <> 'DESCARTADO' AND r.dia >= $desde
    AND ($categoria IS NULL OR r.categoria_codigo = $categoria)
    AND ($comuna IS NULL OR r.id_comuna = $comuna)
    AND ($sector IS NULL OR r.id_localidad = $sector)
"""

# Nombre para los tramos sin sector (el punto quedó fuera de las localidades conocidas).
SIN_SECTOR = "Sector sin identificar"
# Cuántos tramos de calle se muestran dentro de cada sector en el ranking agrupado.
CALLES_POR_SECTOR = 5


def _periodo(dias: int, hoy: date | None = None) -> tuple[date, date, date]:
    """(inicio del período anterior, inicio del período actual, hoy)."""
    hoy = hoy or date.today()
    inicio = hoy - timedelta(days=dias - 1)
    return inicio - timedelta(days=dias), inicio, hoy


def tendencia(actual: int, anterior: int) -> str:
    """nueva | sube | baja | igual, comparando el período actual con el anterior."""
    if anterior == 0:
        return "nueva" if actual > 0 else "igual"
    if actual - anterior >= UMBRAL_CAMBIO:
        return "sube"
    if anterior - actual >= UMBRAL_CAMBIO:
        return "baja"
    return "igual"


def variacion(actual: int, anterior: int) -> float | None:
    """Cambio porcentual respecto del período anterior (None si antes no hubo hechos)."""
    if anterior == 0:
        return None
    return round((actual - anterior) / anterior * 100, 1)


def categorias(codigos: set[str]) -> list[dict]:
    filas = conexion.consultar_grafo(
        "MATCH (c:Categoria) RETURN c.codigo AS codigo, c.nombre AS nombre, c.color AS color ORDER BY c.nombre"
    )
    return [f for f in filas if not codigos or f["codigo"] in codigos]


def por_dia(
    dias: int, categoria: str | None, comuna: int | None, hoy: date | None = None, *, sector: int | None = None
) -> dict:
    """Hechos por día del período, con el desglose por categoría y el total del período anterior."""
    desde_anterior, desde, hoy = _periodo(dias, hoy)
    filas = conexion.consultar_grafo(
        f"""
        MATCH (r:Reporte) WHERE {_FILTRO}
        OPTIONAL MATCH (inc:Incidente)-[:AGRUPA]->(r)
        RETURN r.dia AS dia, r.categoria_codigo AS categoria,
               count(DISTINCT coalesce(inc.id, r.id)) AS hechos, count(r) AS reportes
        """,
        desde=desde_anterior.isoformat(), categoria=categoria, comuna=comuna, sector=sector,
    )
    serie = {
        (desde + timedelta(days=i)).isoformat(): {"total": 0, "reportes": 0, "por_categoria": {}}
        for i in range(dias)
    }
    anterior = 0
    codigos: set[str] = set()
    for f in filas:
        if f["dia"] < desde.isoformat():
            anterior += f["hechos"]
            continue
        dia = serie.get(f["dia"])
        if dia is None:  # fechas futuras por hora del servidor: se ignoran
            continue
        dia["total"] += f["hechos"]
        dia["reportes"] += f["reportes"]
        dia["por_categoria"][f["categoria"]] = dia["por_categoria"].get(f["categoria"], 0) + f["hechos"]
        codigos.add(f["categoria"])

    total = sum(d["total"] for d in serie.values())
    pico = max(serie.items(), key=lambda kv: kv[1]["total"], default=(None, {"total": 0}))
    return {
        "desde": desde.isoformat(),
        "hasta": hoy.isoformat(),
        "dias": [{"dia": dia, **datos} for dia, datos in serie.items()],
        "total": total,
        "anterior": anterior,
        "tendencia": tendencia(total, anterior),
        "variacion": variacion(total, anterior),
        "promedio_diario": round(total / dias, 2),
        "dia_pico": {"dia": pico[0], "total": pico[1]["total"]} if pico[1]["total"] else None,
        "categorias": categorias(codigos),
    }


def ranking_calles(
    dias: int,
    categoria: str | None,
    comuna: int | None,
    limite: int,
    hoy: date | None = None,
    *,
    sector: int | None = None,
) -> dict:
    """Tramos de calle (calle dentro de un sector) con más hechos, con su tendencia y categorías.

    Además de la lista, `por_sector` agrupa los tramos por su sector: el total del
    sector (suma de sus calles) y sus calles con más hechos, para el ranking agrupado.
    """
    desde_anterior, desde, _ = _periodo(dias, hoy)
    filas = conexion.consultar_grafo(
        f"""
        MATCH (r:Reporte)-[:EN_CALLE]->(c:Calle) WHERE {_FILTRO}
        OPTIONAL MATCH (inc:Incidente)-[:AGRUPA]->(r)
        OPTIONAL MATCH (c)-[:EN_COMUNA]->(com:Comuna)
        WITH c, com, r, r.dia >= $actual AS actual, coalesce(inc.id, r.id) AS hecho
        RETURN properties(c) AS calle, com.nombre AS comuna, actual,
               r.categoria_codigo AS categoria, r.categoria AS nombre_categoria, r.color AS color,
               count(DISTINCT hecho) AS hechos, count(r) AS reportes, max(r.fecha_creacion) AS ultimo
        """,
        desde=desde_anterior.isoformat(), actual=desde.isoformat(), categoria=categoria, comuna=comuna,
        sector=sector,
    )
    calles: dict[int, dict] = {}
    for f in filas:
        c = calles.setdefault(f["calle"]["id"], {
            "id": f["calle"]["id"], "nombre": f["calle"]["nombre"], "comuna": f["comuna"],
            "sector": f["calle"].get("sector"), "id_sector": f["calle"].get("id_localidad"),
            "latitud": f["calle"].get("latitud"), "longitud": f["calle"].get("longitud"),
            "total": 0, "reportes": 0, "anterior": 0, "ultimo": None, "por_categoria": {},
        })
        if not f["actual"]:
            c["anterior"] += f["hechos"]
            continue
        c["total"] += f["hechos"]
        c["reportes"] += f["reportes"]
        c["ultimo"] = max(filter(None, (c["ultimo"], f["ultimo"])), default=None)
        cat = c["por_categoria"].setdefault(
            f["categoria"], {"codigo": f["categoria"], "nombre": f["nombre_categoria"], "color": f["color"], "total": 0}
        )
        cat["total"] += f["hechos"]

    lista = []
    for c in calles.values():
        if c["total"] == 0:
            continue
        c["por_categoria"] = sorted(c["por_categoria"].values(), key=lambda x: -x["total"])
        c["tendencia"] = tendencia(c["total"], c["anterior"])
        c["variacion"] = variacion(c["total"], c["anterior"])
        lista.append(c)
    lista.sort(key=lambda c: (-c["total"], -c["reportes"], c["nombre"]))
    por_sector = agrupar_por_sector(lista)

    sin_calle = conexion.consultar_grafo(
        f"""
        MATCH (r:Reporte) WHERE {_FILTRO} AND r.dia >= $actual AND NOT (r)-[:EN_CALLE]->()
        RETURN count(r) AS total
        """,
        desde=desde_anterior.isoformat(), actual=desde.isoformat(), categoria=categoria, comuna=comuna,
        sector=sector,
    )
    return {
        "calles": lista[:limite],
        "total_calles": len(lista),
        "por_sector": por_sector,
        "reportes_sin_calle": sin_calle[0]["total"],
    }


def agrupar_por_sector(calles: list[dict]) -> list[dict]:
    """Agrupa tramos ya ordenados por su sector y marca el puesto de cada uno dentro del suyo.

    El total del sector es la suma de sus calles (solo hechos con calle identificada).
    Los sectores se ordenan por total; dentro de cada uno, las calles quedan en el orden recibido.
    """
    sectores: dict[int | None, dict] = {}
    for c in calles:
        s = sectores.setdefault(c.get("id_sector"), {
            "id": c.get("id_sector"), "nombre": c.get("sector") or SIN_SECTOR, "comuna": c.get("comuna"),
            "total": 0, "anterior": 0, "calles": [],
        })
        s["total"] += c["total"]
        s["anterior"] += c["anterior"]
        s["calles"].append(c)
    lista = []
    for s in sectores.values():
        for puesto, c in enumerate(s["calles"], start=1):
            c["puesto_en_sector"] = puesto
            c["calles_en_sector"] = len(s["calles"])
        s["total_calles"] = len(s["calles"])
        s["calles"] = s["calles"][:CALLES_POR_SECTOR]
        s["tendencia"] = tendencia(s["total"], s["anterior"])
        s["variacion"] = variacion(s["total"], s["anterior"])
        lista.append(s)
    # El grupo "sin sector" va al final: no es un lugar comparable con los demás.
    lista.sort(key=lambda s: (s["id"] is None, -s["total"], s["nombre"]))
    return lista


def sectores_en_el_tiempo(
    dias: int,
    categoria: str | None,
    comuna: int | None,
    tramos: int,
    limite: int,
    hoy: date | None = None,
    *,
    sector: int | None = None,
) -> dict:
    """Sectores (localidad o, si no hay, comuna) con sus hechos en `tramos` partes iguales del período.

    La serie por tramos muestra la forma de la evolución (cuándo se concentró), y la
    comparación con el período anterior dice si el sector es nuevo, sube, baja o se mantiene.
    """
    desde_anterior, desde, hoy = _periodo(dias, hoy)
    tramos = max(1, min(tramos, dias))
    filas = conexion.consultar_grafo(
        f"""
        MATCH (r:Reporte)-[:OCURRIO_EN]->(lugar) WHERE {_FILTRO}
        OPTIONAL MATCH (inc:Incidente)-[:AGRUPA]->(r)
        OPTIONAL MATCH (lugar)-[:PERTENECE_A]->(com:Comuna)
        RETURN labels(lugar)[0] AS tipo, lugar.id AS id, lugar.nombre AS nombre, com.nombre AS comuna,
               r.dia AS dia, count(DISTINCT coalesce(inc.id, r.id)) AS hechos
        """,
        desde=desde_anterior.isoformat(), categoria=categoria, comuna=comuna, sector=sector,
    )
    largo_tramo = dias / tramos
    limites = [desde + timedelta(days=round(i * largo_tramo)) for i in range(tramos)]
    sectores: dict[str, dict] = {}
    for f in filas:
        s = sectores.setdefault(f"{f['tipo']}:{f['id']}", {
            "clave": f"{f['tipo']}:{f['id']}", "tipo": f["tipo"], "id": f["id"], "nombre": f["nombre"],
            "comuna": f["comuna"], "serie": [0] * tramos, "total": 0, "anterior": 0,
        })
        dia = date.fromisoformat(f["dia"])
        if dia < desde:
            s["anterior"] += f["hechos"]
            continue
        if dia > hoy:
            continue
        indice = max(i for i, inicio in enumerate(limites) if inicio <= dia)
        s["serie"][indice] += f["hechos"]
        s["total"] += f["hechos"]

    lista = []
    for s in sectores.values():
        if s["total"] == 0 and s["anterior"] == 0:
            continue
        s["tendencia"] = tendencia(s["total"], s["anterior"])
        s["variacion"] = variacion(s["total"], s["anterior"])
        lista.append(s)
    # Primero los que más preocupan: más hechos ahora y, a igualdad, los que más subieron.
    lista.sort(key=lambda s: (-s["total"], -(s["total"] - s["anterior"]), s["nombre"] or ""))
    return {
        "tramos": [
            {"desde": inicio.isoformat(), "hasta": (limites[i + 1] - timedelta(days=1) if i + 1 < tramos else hoy).isoformat()}
            for i, inicio in enumerate(limites)
        ],
        "sectores": lista[:limite],
        "resumen": {t: sum(1 for s in lista if s["tendencia"] == t) for t in ("nueva", "sube", "baja", "igual")},
    }


def sectores_con_reportes() -> list[dict]:
    """Sectores (localidades) que tienen reportes, con su comuna, para el filtro del panel."""
    return conexion.consultar_grafo(
        """
        MATCH (:Reporte)-[:OCURRIO_EN]->(l:Localidad)-[:PERTENECE_A]->(c:Comuna)
        RETURN DISTINCT l.id AS id, l.nombre AS nombre, c.id AS id_comuna
        ORDER BY nombre
        """
    )


def comunas_con_reportes() -> list[dict]:
    """Comunas que tienen reportes en el grafo, para el filtro del panel."""
    return conexion.consultar_grafo(
        """
        MATCH (r:Reporte)
        WITH DISTINCT r.id_comuna AS id WHERE id IS NOT NULL
        MATCH (c:Comuna {id: id})
        RETURN c.id AS id, c.nombre AS nombre ORDER BY c.nombre
        """
    )
