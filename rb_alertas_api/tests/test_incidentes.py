from datetime import datetime, timedelta

from app.servicios import incidentes

INICIO = datetime(2026, 11, 1, 20, 0)


def reporte(id_reporte, minutos=0, norte_metros=0, categoria="ROBO", confirmaciones=0):
    # 1 grado de latitud son ~111.2 km.
    return {
        "id_reporte": id_reporte,
        "categoria_codigo": categoria,
        "latitud": -41.4693 + norte_metros / 111_195,
        "longitud": -72.9424,
        "fecha_creacion": INICIO + timedelta(minutes=minutos),
        "total_confirmaciones": confirmaciones,
        "total_desmentidos": 0,
    }


def ids(grupos):
    return [[r["id_reporte"] for r in g] for g in grupos]


def test_distancia_metros():
    assert abs(incidentes.distancia_metros(-41.4693, -72.9424, -41.4693 + 1000 / 111_195, -72.9424) - 1000) < 5


def test_mismo_hecho_cerca_y_al_mismo_tiempo_se_agrupa():
    grupos = incidentes.agrupar([reporte(1), reporte(2, minutos=20, norte_metros=120)])
    assert ids(grupos) == [[1, 2]]


def test_otra_categoria_no_se_agrupa():
    grupos = incidentes.agrupar([reporte(1), reporte(2, categoria="ACCIDENTE")])
    assert sorted(ids(grupos)) == [[1], [2]]


def test_lejos_no_se_agrupa():
    grupos = incidentes.agrupar([reporte(1), reporte(2, norte_metros=900)])
    assert sorted(ids(grupos)) == [[1], [2]]


def test_horas_despues_no_se_agrupa():
    grupos = incidentes.agrupar([reporte(1), reporte(2, minutos=5 * 60)])
    assert sorted(ids(grupos)) == [[1], [2]]


def test_la_regla_se_encadena():
    # 1 y 3 están a 500 m, pero 2 está a 250 m de cada uno: los tres son un incidente.
    grupos = incidentes.agrupar([reporte(1), reporte(2, norte_metros=250), reporte(3, norte_metros=500)])
    assert ids(grupos) == [[1, 2, 3]]


def test_resumir_suma_y_usa_el_primer_reporte():
    resumen = incidentes.resumir([
        reporte(7, minutos=30, norte_metros=50, confirmaciones=2),
        reporte(5, confirmaciones=1),
        reporte(9, norte_metros=5000),
    ])
    assert len(resumen) == 2
    incidente = next(r for r in resumen if r["total_reportes"] == 2)
    assert incidente["id_incidente"] == 5 and incidente["id_reporte"] == 5
    assert incidente["ids_reportes"] == [5, 7]
    assert incidente["total_confirmaciones"] == 3
    assert incidente["ultima_actividad"] == INICIO + timedelta(minutes=30)


def test_grupo_de():
    datos = [reporte(1), reporte(2, minutos=10), reporte(3, norte_metros=4000)]
    assert [r["id_reporte"] for r in incidentes.grupo_de(2, datos)] == [1, 2]
    assert incidentes.grupo_de(99, datos) == []
