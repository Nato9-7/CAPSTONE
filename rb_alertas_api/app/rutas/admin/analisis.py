"""Análisis del panel (Neo4j): cuándo y dónde ocurren los hechos.

Cada ruta compara los últimos `dias` días con los `dias` anteriores. Los filtros
`categoria` (p. ej. ROBO) y `comuna` (id) son opcionales y se combinan.
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


@router.get("/por-dia")
def hechos_por_dia(dias: int = _DIAS, categoria: str | None = _CATEGORIA, comuna: int | None = _COMUNA):
    """Hechos por día con el desglose por categoría, el día con más hechos y la comparación
    con el período anterior."""
    with grafo_disponible():
        return {**analisis.por_dia(dias, categoria, comuna), "sincronizacion": grafo.ultima_sincronizacion}


@router.get("/calles")
def calles_con_mas_hechos(
    dias: int = _DIAS,
    categoria: str | None = _CATEGORIA,
    comuna: int | None = _COMUNA,
    limite: int = Query(15, ge=1, le=100),
):
    """Ranking de calles por hechos en el período, con tendencia y desglose por categoría."""
    with grafo_disponible():
        return analisis.ranking_calles(dias, categoria, comuna, limite)


@router.get("/sectores")
def sectores_en_el_tiempo(
    dias: int = _DIAS,
    categoria: str | None = _CATEGORIA,
    comuna: int | None = _COMUNA,
    tramos: int = Query(6, ge=2, le=12),
    limite: int = Query(15, ge=1, le=100),
):
    """Sectores con su evolución en tramos iguales del período: nuevos, en alza, a la baja o estables."""
    with grafo_disponible():
        return analisis.sectores_en_el_tiempo(dias, categoria, comuna, tramos, limite)


@router.get("/filtros")
def filtros_disponibles():
    """Categorías y comunas para los filtros del análisis."""
    with grafo_disponible():
        return {"categorias": analisis.categorias(set()), "comunas": analisis.comunas_con_reportes()}
