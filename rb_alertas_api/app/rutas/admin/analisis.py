"""Análisis del panel (Neo4j): cuándo y dónde ocurren los hechos.

Cada ruta compara los últimos `dias` días con los `dias` anteriores. Los filtros
`categoria` (p. ej. ROBO), `comuna` (id) y `sector` (id de localidad) son opcionales
y se combinan. Una "calle" es un tramo: la calle dentro de un sector.
"""

from fastapi import APIRouter, Query

from app.rutas.admin.errores import grafo_disponible
from app.servicios import grafo
from app.servicios.grafo import analisis
from app.servicios.grafo.zonas import CODIGO_CATEGORIA

router = APIRouter(prefix="/analisis")

_DIAS = Query(30, ge=7, le=365, description="Largo del período, en días")
_CATEGORIA = Query(None, pattern=CODIGO_CATEGORIA)
_COMUNA = Query(None, ge=1)
_SECTOR = Query(None, ge=1, description="Id de la localidad (sector)")


@router.get("/por-dia")
def hechos_por_dia(
    dias: int = _DIAS, categoria: str | None = _CATEGORIA, comuna: int | None = _COMUNA, sector: int | None = _SECTOR
):
    """Hechos por día con el desglose por categoría, el día con más hechos y la comparación
    con el período anterior."""
    with grafo_disponible():
        return {**analisis.por_dia(dias, categoria, comuna, sector=sector), "sincronizacion": grafo.ultima_sincronizacion}


@router.get("/calles")
def calles_con_mas_hechos(
    dias: int = _DIAS,
    categoria: str | None = _CATEGORIA,
    comuna: int | None = _COMUNA,
    sector: int | None = _SECTOR,
    limite: int = Query(15, ge=1, le=100),
):
    """Ranking de tramos de calle por hechos en el período, con tendencia y desglose por
    categoría, y el mismo ranking agrupado por sector (`por_sector`)."""
    with grafo_disponible():
        return analisis.ranking_calles(dias, categoria, comuna, limite, sector=sector)


@router.get("/sectores")
def sectores_en_el_tiempo(
    dias: int = _DIAS,
    categoria: str | None = _CATEGORIA,
    comuna: int | None = _COMUNA,
    sector: int | None = _SECTOR,
    tramos: int = Query(6, ge=2, le=12),
    limite: int = Query(15, ge=1, le=100),
):
    """Sectores con su evolución en tramos iguales del período: nuevos, en alza, a la baja o estables."""
    with grafo_disponible():
        return analisis.sectores_en_el_tiempo(dias, categoria, comuna, tramos, limite, sector=sector)


@router.get("/filtros")
def filtros_disponibles():
    """Categorías, comunas y sectores para los filtros del análisis."""
    with grafo_disponible():
        return {
            "categorias": analisis.categorias(set()),
            "comunas": analisis.comunas_con_reportes(),
            "sectores": analisis.sectores_con_reportes(),
        }
