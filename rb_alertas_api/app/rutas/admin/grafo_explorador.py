"""Red de lugares del panel.

- nivel=calle: sectores → tramos de calle → categorías (tres niveles).
- nivel=sector: sectores → categorías.
"""

from typing import Literal

from fastapi import APIRouter, Query

from app.rutas.admin.errores import grafo_disponible
from app.servicios import grafo
from app.servicios.grafo.red import arista, nodo
from app.servicios.grafo.zonas import CODIGO_CATEGORIA, desde_dias, nodo_lugar, zonas_calientes

router = APIRouter()

Nivel = Literal["calle", "sector"]


@router.get("/grafo/zonas")
def ranking_zonas(
    categoria: str | None = Query(None, pattern=CODIGO_CATEGORIA),
    dias: int | None = Query(None, ge=1, le=3650),
    nivel: Nivel = "calle",
    limite: int = Query(20, ge=1, le=200),
):
    """Ranking de los lugares con más hechos (de una categoría, p. ej. ROBO, o de todas)."""
    with grafo_disponible():
        lugares = zonas_calientes(categoria, desde_dias(dias), nivel)[:limite]
    return [
        {**nodo_lugar(l), "total": l["total"], "reportes": l["reportes"], "comuna": l["comuna"], "por_categoria": l["por_categoria"]}
        for l in lugares
    ]


@router.get("/grafo/red")
def red_de_lugares(
    dias: int | None = Query(None, ge=1, le=3650),
    categoria: str | None = Query(None, pattern=CODIGO_CATEGORIA),
    nivel: Nivel = "calle",
    sector: int | None = Query(None, ge=1, description="Id de la localidad (sector)"),
    limite: int = Query(40, ge=5, le=200),
):
    """Los lugares con más hechos unidos a las categorías de lo que pasó ahí.

    El peso de cada unión es cuántos hechos de esa categoría hubo en el lugar, así se
    ve de un vistazo qué calles concentran robos, accidentes, etc. y cuáles comparten problemas.
    Con nivel=calle, cada tramo se une además a su sector (peso = hechos del tramo).
    """
    with grafo_disponible():
        lugares = zonas_calientes(categoria, desde_dias(dias), nivel, sector)[:limite]
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

    sectores: dict[str, dict] = {}
    if nivel == "calle":
        for lugar, nodo_de_lugar in zip(lugares, nodos):
            id_sector = lugar["datos"].get("id_localidad")
            if not id_sector:
                continue
            clave = f"Localidad:{id_sector}"
            sec = sectores.setdefault(clave, nodo("Localidad", {
                "id": id_sector, "nombre": lugar["datos"].get("sector"), "comuna": lugar["comuna"], "total": 0,
            }))
            sec["datos"]["total"] += lugar["total"]
            aristas.append(arista(clave, nodo_de_lugar["clave"], "CONTIENE", {"peso": lugar["total"]}))
    return {
        "nodos": nodos + list(categorias.values()) + list(sectores.values()),
        "aristas": aristas,
        "sincronizacion": grafo.ultima_sincronizacion,
    }
