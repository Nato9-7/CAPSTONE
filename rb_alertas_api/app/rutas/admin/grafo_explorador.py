"""Explorador de la red del panel: red completa, dónde ocurre más, búsqueda, camino y foco."""

from typing import Literal

from fastapi import APIRouter, HTTPException, Path as PathParam, Query

from app.rutas.admin.errores import grafo_disponible
from app.servicios import grafo
from app.servicios.grafo.red import (
    PROYECCION_RELACION,
    TIPOS_NODO,
    anillos,
    arista,
    armar_red,
    marcar_comunidades,
    nodo,
)
from app.servicios.grafo.zonas import CODIGO_CATEGORIA, desde_dias, nodo_lugar, zonas_calientes

router = APIRouter()

MAXIMO_RELACIONES_FOCO = 90
MAXIMO_PASOS_CAMINO = 8

# Relaciones que agrega cada capa pedida en modo=completa.
_RELACIONES_POR_CAPA = {
    "lugares": ["OCURRIO_EN"],
    "categorias": ["ES_DE"],
    "zonas": ["TIENE_ZONA", "ALERTO_A"],
    "incidentes": ["AGRUPA"],
    "sospechosos": ["MIEMBRO_DE"],
    "grupos": ["COMPARTIDO_EN"],
}

# Solo relaciones reales: los grupos sospechosos e incidentes los calcula el sistema
# y no cuentan como camino, salvo que uno de los extremos sea justamente uno de ellos.
_RELACIONES_CAMINO = ["CREO", "VOTO", "OCURRIO_EN", "ES_DE", "PERTENECE_A", "TIENE_ZONA", "ALERTO_A", "INTEGRA", "COMPARTIDO_EN"]


@router.get("/grafo/zonas")
def ranking_zonas(
    categoria: str | None = Query(None, pattern=CODIGO_CATEGORIA),
    dias: int | None = Query(None, ge=1, le=3650),
    limite: int = Query(20, ge=1, le=200),
):
    """Ranking de los lugares con más reportes (de una categoría, p. ej. ROBO, o de todas)."""
    with grafo_disponible():
        lugares = zonas_calientes(categoria, desde_dias(dias))[:limite]
    return [
        {**nodo_lugar(l), "total": l["total"], "reportes": l["reportes"], "comuna": l["comuna"], "por_categoria": l["por_categoria"]}
        for l in lugares
    ]


def _red_de_zonas(categoria: str | None, desde: str | None, limite: int) -> dict:
    """Lugares unidos a las categorías de lo que pasó ahí; el peso es cuántos hechos hubo."""
    lugares = zonas_calientes(categoria, desde)[:limite]
    nodos = [nodo_lugar(l) for l in lugares]
    categorias: dict[str, dict] = {}
    aristas = []
    for lugar, nodo_de_lugar in zip(lugares, nodos):
        for c in lugar["por_categoria"]:
            clave = f"Categoria:{c['id']}"
            cat = categorias.setdefault(clave, nodo("Categoria", {
                "id": c["id"], "codigo": c["codigo"], "nombre": c["nombre"], "color": c["color"], "total": 0,
            }))
            cat["datos"]["total"] += c["total"]
            aristas.append(arista(nodo_de_lugar["clave"], clave, "OCURREN", {"peso": c["total"]}))
    return {"nodos": nodos + list(categorias.values()), "aristas": aristas}


def _red_de_vecinos(desde: str | None, categoria: str | None, limite: int) -> dict:
    """Vecinos unidos por quién confirma o desmiente a quién; el peso es cuántas veces lo hizo.

    Con `categoria`, solo cuentan los votos y reportes de esa categoría (p. ej. ROBO).
    """
    filas = grafo.consultar_grafo(
        """
        MATCH (a:Usuario)-[v:VOTO]->(r:Reporte)<-[:CREO]-(b:Usuario)
        WHERE a <> b AND ($desde IS NULL OR r.fecha_creacion >= $desde)
          AND ($categoria IS NULL OR r.categoria_codigo = $categoria)
        WITH a, b, sum(CASE v.tipo WHEN 'CONFIRMA' THEN 1 ELSE 0 END) AS confirma,
                   sum(CASE v.tipo WHEN 'DESMIENTE' THEN 1 ELSE 0 END) AS desmiente
        ORDER BY confirma + desmiente DESC LIMIT $limite
        RETURN 'Usuario' AS tipo_a, properties(a) AS a,
               CASE WHEN confirma >= desmiente THEN 'CONFIRMA_A' ELSE 'DESMIENTE_A' END AS tipo_rel,
               {peso: confirma + desmiente, confirma: confirma, desmiente: desmiente} AS datos_rel,
               'Usuario' AS tipo_b, properties(b) AS b
        """,
        desde=desde,
        categoria=categoria,
        limite=limite,
    )
    # También los vecinos que reportaron sin recibir votos, para que la red esté completa.
    solos = grafo.consultar_grafo(
        """
        MATCH (u:Usuario)-[:CREO]->(r:Reporte)
        WHERE NOT u.es_admin AND ($desde IS NULL OR r.fecha_creacion >= $desde)
          AND ($categoria IS NULL OR r.categoria_codigo = $categoria)
        RETURN DISTINCT properties(u) AS u LIMIT $limite
        """,
        desde=desde,
        categoria=categoria,
        limite=limite,
    )
    return armar_red(filas, [nodo("Usuario", f["u"]) for f in solos])


def _red_completa(capas: set[str], desde: str | None, categoria: str | None, limite: int) -> dict:
    """Vecinos y reportes recientes (de `categoria`, si se pide), más las relaciones de las capas pedidas."""
    tipos = ["CREO", "VOTO"] + [rel for capa, rels in _RELACIONES_POR_CAPA.items() if capa in capas for rel in rels]
    filas = grafo.consultar_grafo(
        f"""
        MATCH (r:Reporte)
        WHERE ($desde IS NULL OR r.fecha_creacion >= $desde)
          AND ($categoria IS NULL OR r.categoria_codigo = $categoria)
        WITH r ORDER BY r.fecha_creacion DESC LIMIT $limite
        WITH collect(r) AS reportes
        UNWIND reportes AS r
        MATCH (r)-[rel:{"|".join(tipos)}]-(x)
        WITH DISTINCT rel
        {PROYECCION_RELACION}
        """,
        desde=desde,
        categoria=categoria,
        limite=limite,
    )
    if "sospechosos" in capas:
        filas += grafo.consultar_grafo("MATCH ()-[rel:MIEMBRO_DE]->() " + PROYECCION_RELACION)
    if "grupos" in capas:
        filas += grafo.consultar_grafo("MATCH ()-[rel:INTEGRA]->(:Grupo) " + PROYECCION_RELACION)
    return armar_red(filas)


@router.get("/grafo/red")
def red_completa(
    modo: Literal["vecinos", "completa", "zonas"] = "vecinos",
    dias: int | None = Query(None, ge=1, le=3650),
    capas: str = Query("lugares,incidentes,sospechosos,grupos", max_length=100),
    categoria: str | None = Query(None, pattern=CODIGO_CATEGORIA),
    limite: int = Query(300, ge=10, le=1000),
):
    """La red para el explorador del panel.

    - modo=vecinos: solo vecinos, unidos por quién confirma o desmiente a quién.
    - modo=completa: vecinos y reportes, más las capas pedidas (lugares, categorias,
      zonas, incidentes, sospechosos, grupos).
    - modo=zonas: dónde ocurre más. Lugares unidos a las categorías de lo que pasó
      ahí; el peso es cuántos hechos hubo (no reportes).
    `categoria` (p. ej. ROBO o ACCIDENTE) deja solo los reportes de esa categoría en cualquier modo.
    `dias` limita a la actividad de los últimos N días (sin él, toda la historia).
    """
    desde = desde_dias(dias)
    with grafo_disponible():
        if modo == "zonas":
            red = _red_de_zonas(categoria, desde, limite)
        elif modo == "vecinos":
            red = _red_de_vecinos(desde, categoria, limite)
        else:
            red = _red_completa({c.strip() for c in capas.split(",") if c.strip()}, desde, categoria, limite)
    marcar_comunidades(red)
    return {**red, "sincronizacion": grafo.ultima_sincronizacion}


@router.get("/grafo/buscar")
def buscar_en_grafo(q: str = Query(min_length=1, max_length=60)):
    """Vecinos por seudónimo, reportes o incidentes por número, y lugares o categorías por nombre."""
    texto = q.strip().lstrip("#").lower()
    numero = int(texto) if texto.isdigit() else -1
    with grafo_disponible():
        filas = grafo.consultar_grafo(
            """
            CALL () {
                MATCH (u:Usuario) WHERE toLower(u.alias) CONTAINS $texto
                RETURN 'Usuario' AS tipo, properties(u) AS n, 0 AS orden LIMIT 8
                UNION
                MATCH (r:Reporte) WHERE r.id = $numero
                RETURN 'Reporte' AS tipo, properties(r) AS n, 1 AS orden
                UNION
                MATCH (i:Incidente) WHERE i.id = $numero
                RETURN 'Incidente' AS tipo, properties(i) AS n, 2 AS orden
                UNION
                MATCH (l) WHERE (l:Localidad OR l:Comuna OR l:Categoria OR l:Grupo) AND toLower(l.nombre) CONTAINS $texto
                RETURN labels(l)[0] AS tipo, properties(l) AS n, 3 AS orden LIMIT 8
            }
            RETURN tipo, n ORDER BY orden LIMIT 15
            """,
            texto=texto,
            numero=numero,
        )
    return [nodo(f["tipo"], f["n"]) for f in filas]


@router.get("/grafo/camino")
def camino_mas_corto(
    desde: str = Query(pattern=r"^[A-Za-z]+:\d+$"),
    hasta: str = Query(pattern=r"^[A-Za-z]+:\d+$"),
):
    """El camino más corto entre dos elementos (hasta 8 pasos), con shortestPath de Neo4j."""
    (tipo_a, id_a), (tipo_b, id_b) = (c.split(":") for c in (desde, hasta))
    # Cypher no acepta la etiqueta como parámetro: va en el texto, por eso solo se
    # aceptan los valores fijos de TIPOS_NODO.
    if tipo_a not in TIPOS_NODO or tipo_b not in TIPOS_NODO:
        raise HTTPException(status_code=422, detail="Tipo de nodo no válido")
    if desde == hasta:
        raise HTTPException(status_code=422, detail="Elige dos elementos distintos")

    relaciones = list(_RELACIONES_CAMINO)
    if "Coordinacion" in (tipo_a, tipo_b):
        relaciones.append("MIEMBRO_DE")
    if "Incidente" in (tipo_a, tipo_b):
        relaciones.append("AGRUPA")

    with grafo_disponible():
        filas = grafo.consultar_grafo(
            f"""
            MATCH (a:{tipo_a} {{id: $id_a}}), (b:{tipo_b} {{id: $id_b}})
            MATCH p = shortestPath((a)-[:{"|".join(relaciones)}*..{MAXIMO_PASOS_CAMINO}]-(b))
            UNWIND relationships(p) AS rel
            {PROYECCION_RELACION}
            """,
            id_a=int(id_a),
            id_b=int(id_b),
        )
    if not filas:
        raise HTTPException(status_code=404, detail="Esos dos elementos no están conectados")
    return {**armar_red(filas), "pasos": len(filas)}


@router.get("/grafo/nodo/{tipo}/{id_nodo}")
def foco_grafo(
    tipo: Literal[
        "Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura", "Coordinacion", "Incidente", "Grupo"
    ],
    id_nodo: int = PathParam(ge=1),
):
    """El elemento en foco y lo conectado hasta 2 pasos, con el anillo de cada nodo (0, 1 o 2)."""
    with grafo_disponible():
        centro = grafo.consultar_grafo(f"MATCH (n:{tipo} {{id: $id}}) RETURN properties(n) AS n", id=id_nodo)
        if not centro:
            raise HTTPException(status_code=404, detail="Ese elemento no está en el grafo")
        # Primero las relaciones directas y después las del segundo anillo, así el
        # tope de relaciones nunca deja fuera el primer anillo.
        filas = grafo.consultar_grafo(
            f"""
            MATCH (n:{tipo} {{id: $id}})-[r1]-(x)
            WITH n, collect(DISTINCT r1) AS primeras, collect(DISTINCT x) AS vecinos
            UNWIND vecinos AS x
            OPTIONAL MATCH (x)-[r2]-(y) WHERE y <> n
            WITH primeras, collect(DISTINCT r2) AS segundas
            UNWIND primeras + segundas AS rel
            WITH DISTINCT rel LIMIT $maximo
            {PROYECCION_RELACION}
            """,
            id=id_nodo,
            maximo=MAXIMO_RELACIONES_FOCO,
        )
    foco = nodo(tipo, centro[0]["n"])
    red = armar_red(filas, [foco])
    anillo = anillos(foco["clave"], red["aristas"])
    visibles = [{**n, "anillo": anillo[n["clave"]]} for n in red["nodos"] if n["clave"] in anillo]
    claves = {n["clave"] for n in visibles}
    return {
        "foco": foco["clave"],
        "nodos": visibles,
        "aristas": [a for a in red["aristas"] if a["origen"] in claves and a["destino"] in claves],
        "sincronizacion": grafo.ultima_sincronizacion,
    }
