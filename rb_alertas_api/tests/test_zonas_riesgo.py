from datetime import datetime, timedelta

from app.servicios import zonas_riesgo

INICIO = datetime(2026, 11, 1, 22, 0)
NOMBRES = {
    "ROBO": "Robo o asalto", "ACCIDENTE": "Accidente de tránsito", "INCENDIO": "Incendio",
    "MASCOTA": "Mascota perdida", "VIAL": "Problema en la vía",
}


GRAVEDAD = {"ROBO": 4, "ACCIDENTE": 4, "INCENDIO": 5, "MASCOTA": 1, "VIAL": 2}


def reporte(id_reporte, dias=0, norte_metros=0, categoria="ROBO", hora=None):
    fecha = INICIO - timedelta(days=dias)
    if hora is not None:
        fecha = fecha.replace(hour=hora)
    return {
        "id_reporte": id_reporte,
        "categoria_codigo": categoria,
        "categoria": NOMBRES[categoria],
        "color_hex": "#C2410C",
        "latitud": -41.4693 + norte_metros / 111_195,
        "longitud": -72.9424,
        "fecha_creacion": fecha,
        "nivel_gravedad": GRAVEDAD[categoria],
    }


def test_categorias_que_marcan_riesgo():
    assert zonas_riesgo.tipo_riesgo("ROBO") == "SEGURIDAD"
    assert zonas_riesgo.tipo_riesgo("SOSPECHOSO") == "SEGURIDAD"
    assert zonas_riesgo.tipo_riesgo("ACCIDENTE") == "VIAL"
    assert zonas_riesgo.tipo_riesgo("VIAL") == "VIAL"
    assert zonas_riesgo.tipo_riesgo("INCENDIO") is None
    assert zonas_riesgo.tipo_riesgo("MASCOTA") is None
    assert zonas_riesgo.tipo_riesgo("EMERGENCIA") is None


def test_un_solo_robo_no_es_zona():
    assert zonas_riesgo.calcular([reporte(1)]) == []


def test_robos_repetidos_cerca_forman_zona_de_noche():
    zonas = zonas_riesgo.calcular([reporte(1, dias=1), reporte(2, dias=5, norte_metros=100)])
    assert len(zonas) == 1
    z = zonas[0]
    assert (z["tipo"], z["nivel"], z["total_incidentes"]) == ("SEGURIDAD", "MEDIO", 2)
    assert z["por_categoria"][0]["total"] == 2
    assert "sobre todo de noche" in z["recomendacion"]
    assert z["radio_metros"] >= zonas_riesgo.RADIO_MINIMO_DIBUJO


def test_vecinos_reportando_el_mismo_robo_cuentan_una_vez():
    # Mismo robo reportado 3 veces en minutos: un incidente, no alcanza para zona.
    mismos = [reporte(i, norte_metros=i * 20) for i in range(1, 4)]
    assert zonas_riesgo.calcular(mismos) == []


def test_cuatro_robos_es_nivel_alto_y_recomienda_evitar():
    robos = [reporte(i, dias=i * 3, norte_metros=i * 40, hora=15) for i in range(1, 5)]
    z = zonas_riesgo.calcular(robos)[0]
    assert z["nivel"] == "ALTO"
    assert z["recomendacion"].startswith("Evita transitar por aquí.")


def test_robos_lejanos_no_se_juntan():
    assert zonas_riesgo.calcular([reporte(1, dias=1), reporte(2, dias=4, norte_metros=2000)]) == []


def test_accidentes_y_robos_son_zonas_separadas_seguridad_primero():
    filas = [
        reporte(1, dias=1, categoria="ACCIDENTE"), reporte(2, dias=6, categoria="ACCIDENTE"),
        reporte(3, dias=2), reporte(4, dias=8),
        reporte(5, dias=3, categoria="INCENDIO"), reporte(6, dias=9, categoria="INCENDIO"),
    ]
    zonas = zonas_riesgo.calcular(filas)
    assert [z["tipo"] for z in zonas] == ["SEGURIDAD", "VIAL"]
    assert "velocidad" in zonas[1]["recomendacion"]


def calor(filas):
    return zonas_riesgo.puntos_calor(filas, ahora=INICIO)


def test_calor_cuenta_las_categorias_de_las_zonas_y_junta_los_cercanos():
    filas = [
        reporte(1, dias=1), reporte(2, dias=1, norte_metros=10),     # mismo robo, 2 reportes
        reporte(3, dias=5, norte_metros=120),                         # otro robo cerca
        reporte(4, dias=2, categoria="ACCIDENTE", norte_metros=200),  # accidente cerca
        reporte(5, dias=3, categoria="VIAL", norte_metros=50),        # problema en la vía cerca
        reporte(6, dias=3, categoria="INCENDIO", norte_metros=60),    # no cuenta
    ]
    [mancha] = calor(filas)
    # Cuatro hechos cercanos en una sola mancha: dos robos, un accidente y un problema vial.
    assert (mancha["peso"], mancha["robos"], mancha["accidentes"], mancha["viales"]) == (4, 2, 1, 1)
    # Coordenadas redondeadas a la celda, no las del reporte.
    assert mancha["latitud"] == round(round(mancha["latitud"] / 0.001) * 0.001, 6)


def test_calor_ignora_otras_categorias():
    filas = [reporte(1, dias=1, categoria="INCENDIO"), reporte(2, dias=1, categoria="MASCOTA", norte_metros=20)]
    assert calor(filas) == []


def test_calor_no_muestra_manchas_de_un_solo_hecho():
    # Robos cercanos de distintos días son hechos distintos; el de 3 km queda solo.
    filas = [reporte(1, dias=1, norte_metros=3000), reporte(2, dias=1), reporte(3, dias=2, norte_metros=100)]
    [mancha] = calor(filas)
    assert mancha["peso"] == 2


def test_la_intensidad_pesa_gravedad_y_antiguedad():
    # Hoy: robo y accidente valen 1 cada uno.
    assert calor([reporte(1), reporte(2, categoria="ACCIDENTE", norte_metros=50)])[0]["intensidad"] == 2
    # Un problema en la vía (gravedad 2) vale la mitad que un robo.
    assert calor([reporte(1), reporte(2, categoria="VIAL", norte_metros=50)])[0]["intensidad"] == 1.5
    # A los 15 días un hecho pesa la mitad; a los 30, un cuarto.
    assert calor([reporte(1, dias=15), reporte(2, dias=30, norte_metros=50)])[0]["intensidad"] == 0.75


def test_las_manchas_se_ordenan_por_intensidad_y_crecen_con_los_hechos():
    filas = [
        reporte(1, dias=40), reporte(2, dias=41, norte_metros=50), reporte(3, dias=42, norte_metros=100),
        reporte(4, norte_metros=3000), reporte(5, dias=1, norte_metros=3050),
    ]
    reciente, antigua = calor(filas)
    # Dos robos de hoy pesan más que tres de hace 40 días.
    assert (reciente["peso"], antigua["peso"]) == (2, 3)
    assert reciente["intensidad"] > antigua["intensidad"]
    assert antigua["radio_metros"] > reciente["radio_metros"]
