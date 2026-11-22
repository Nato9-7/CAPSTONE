"""Análisis del panel: series por día, ranking de calles y sectores en el tiempo (Neo4j simulado)."""

from datetime import date

import pytest

from app.servicios.grafo import analisis
from app.servicios.grafo.sincronizacion import calles_de_reportes, id_calle

HOY = date(2026, 11, 22)


@pytest.fixture
def grafo_falso(monkeypatch):
    """Reemplaza consultar_grafo: devuelve la respuesta registrada para la primera consulta que coincide."""
    respuestas: list[tuple[str, list[dict]]] = []

    def consultar(cypher: str, **_):
        for fragmento, filas in respuestas:
            if fragmento in cypher:
                return filas
        return []

    monkeypatch.setattr(analisis.conexion, "consultar_grafo", consultar)
    return respuestas


@pytest.mark.parametrize(
    ("actual", "anterior", "esperado"),
    [(3, 0, "nueva"), (0, 0, "igual"), (5, 2, "sube"), (1, 4, "baja"), (2, 2, "igual")],
)
def test_tendencia(actual, anterior, esperado):
    assert analisis.tendencia(actual, anterior) == esperado


def test_variacion_sin_periodo_anterior_es_none():
    assert analisis.variacion(4, 0) is None
    assert analisis.variacion(3, 2) == 50.0


def test_por_dia_rellena_dias_sin_hechos_y_separa_el_periodo_anterior(grafo_falso):
    grafo_falso.append(("RETURN r.dia AS dia", [
        {"dia": "2026-11-20", "categoria": "ROBO", "hechos": 2, "reportes": 3},
        {"dia": "2026-11-20", "categoria": "INCENDIO", "hechos": 1, "reportes": 1},
        {"dia": "2026-11-10", "categoria": "ROBO", "hechos": 4, "reportes": 4},  # período anterior
    ]))
    resultado = analisis.por_dia(7, None, None, hoy=HOY)

    assert [d["dia"] for d in resultado["dias"]][0] == "2026-11-16"
    assert len(resultado["dias"]) == 7
    dia_20 = next(d for d in resultado["dias"] if d["dia"] == "2026-11-20")
    assert dia_20["total"] == 3 and dia_20["por_categoria"] == {"ROBO": 2, "INCENDIO": 1}
    assert resultado["total"] == 3
    assert resultado["anterior"] == 4
    assert resultado["tendencia"] == "baja"
    assert resultado["dia_pico"] == {"dia": "2026-11-20", "total": 3}


def test_ranking_calles_ordena_por_hechos_y_calcula_tendencia(grafo_falso):
    calle_a = {"id": 1, "nombre": "Avenida Presidente Ibáñez", "latitud": -41.46, "longitud": -72.93}
    calle_b = {"id": 2, "nombre": "Tucapel", "latitud": -41.47, "longitud": -72.94}
    comun = {"comuna": "Puerto Montt", "nombre_categoria": "Robo", "color": "#c00", "ultimo": "2026-11-20T10:00:00"}
    grafo_falso.append(("EN_CALLE]->(c:Calle)", [
        {**comun, "calle": calle_a, "actual": True, "categoria": "ROBO", "hechos": 3, "reportes": 4},
        {**comun, "calle": calle_a, "actual": False, "categoria": "ROBO", "hechos": 1, "reportes": 1},
        {**comun, "calle": calle_b, "actual": True, "categoria": "ROBO", "hechos": 1, "reportes": 1},
        {**comun, "calle": {"id": 3, "nombre": "Solo antes"}, "actual": False, "categoria": "ROBO", "hechos": 2, "reportes": 2},
    ]))
    grafo_falso.append(("NOT (r)-[:EN_CALLE]->()", [{"total": 5}]))

    resultado = analisis.ranking_calles(30, "ROBO", None, limite=10, hoy=HOY)

    assert [c["nombre"] for c in resultado["calles"]] == ["Avenida Presidente Ibáñez", "Tucapel"]
    primera = resultado["calles"][0]
    assert (primera["total"], primera["anterior"], primera["tendencia"]) == (3, 1, "sube")
    assert resultado["calles"][1]["tendencia"] == "nueva"
    assert resultado["total_calles"] == 2  # la calle sin hechos en el período no entra
    assert resultado["reportes_sin_calle"] == 5


def test_sectores_reparte_los_hechos_en_tramos(grafo_falso):
    grafo_falso.append(("OCURRIO_EN]->(lugar)", [
        {"tipo": "Localidad", "id": 7, "nombre": "Tucapel", "comuna": "Puerto Montt", "dia": "2026-11-17", "hechos": 1},
        {"tipo": "Localidad", "id": 7, "nombre": "Tucapel", "comuna": "Puerto Montt", "dia": "2026-11-22", "hechos": 2},
        {"tipo": "Localidad", "id": 7, "nombre": "Tucapel", "comuna": "Puerto Montt", "dia": "2026-11-05", "hechos": 1},
    ]))
    resultado = analisis.sectores_en_el_tiempo(14, None, None, tramos=2, limite=10, hoy=HOY)

    assert resultado["tramos"] == [
        {"desde": "2026-11-09", "hasta": "2026-11-15"},
        {"desde": "2026-11-16", "hasta": "2026-11-22"},
    ]
    sector = resultado["sectores"][0]
    assert sector["serie"] == [0, 3]
    assert (sector["total"], sector["anterior"], sector["tendencia"]) == (3, 1, "sube")
    assert resultado["resumen"]["sube"] == 1


def test_calles_de_reportes_une_la_misma_calle_y_separa_comunas():
    reportes = [
        {"calle": "Tucapel", "id_comuna": 1, "latitud": -41.0, "longitud": -72.0},
        {"calle": " tucapel ", "id_comuna": 1, "latitud": -41.2, "longitud": -72.2},
        {"calle": "Tucapel", "id_comuna": 2, "latitud": -40.0, "longitud": -73.0},
        {"calle": None, "id_comuna": 1, "latitud": -41.0, "longitud": -72.0},
    ]
    calles = calles_de_reportes(reportes)

    assert len(calles) == 2
    misma = next(c for c in calles if c["id"] == id_calle("Tucapel", 1))
    assert misma["latitud"] == pytest.approx(-41.1)
    assert reportes[0]["id_calle"] == reportes[1]["id_calle"] != reportes[2]["id_calle"]
    assert "id_calle" not in reportes[3]
