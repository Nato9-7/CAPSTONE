from app.servicios.analisis_grafo import calcular_reputacion, detectar_coordinacion


def reporte(id_reporte, autor, estado="PENDIENTE"):
    return {"id_reporte": id_reporte, "id_usuario": autor, "estado": estado}


def voto(votante, id_reporte, tipo="CONFIRMA"):
    return {"id_usuario": votante, "id_reporte": id_reporte, "tipo_voto": tipo}


def test_detecta_par_que_se_confirma_mutuamente():
    # 1 y 2 se confirman todo entre ellos; 3 vota normal.
    reportes = [reporte(10, 1), reporte(11, 1), reporte(20, 2), reporte(21, 2), reporte(30, 3)]
    votos = [voto(1, 20), voto(1, 21), voto(2, 10), voto(2, 11), voto(3, 10), voto(3, 20)]
    grupos = detectar_coordinacion(reportes, votos)
    assert len(grupos) == 1
    assert grupos[0]["miembros"] == [1, 2]
    assert grupos[0]["confirmaciones_internas"] == 4
    assert grupos[0]["reciprocidad"] == 1.0
    assert grupos[0]["nivel"] == "ALTO"


def test_votos_cruzados_aislados_no_son_sospechosos():
    # Un solo intercambio (2 confirmaciones) no llega al mínimo.
    reportes = [reporte(10, 1), reporte(20, 2)]
    votos = [voto(1, 20), voto(2, 10)]
    assert detectar_coordinacion(reportes, votos) == []


def test_quien_confirma_a_muchos_no_es_sospechoso():
    # 1 y 2 se confirman, pero 1 y 2 también confirman a muchos otros: reciprocidad baja.
    reportes = [reporte(10, 1), reporte(20, 2), reporte(11, 1), reporte(21, 2)] + [
        reporte(100 + i, 10 + i) for i in range(10)
    ]
    votos = [voto(1, 20), voto(1, 21), voto(2, 10), voto(2, 11)] + [
        voto(v, 100 + i) for i in range(10) for v in (1, 2)
    ]
    assert detectar_coordinacion(reportes, votos) == []


def test_reputacion_neutra_para_cuenta_nueva():
    rep = calcular_reputacion([1], [], [])
    assert rep[1]["puntaje"] == 50


def test_reportes_descartados_bajan_y_validados_suben():
    reportes = [reporte(1, 1, "DESCARTADO"), reporte(2, 1, "DESCARTADO"), reporte(3, 2, "RESUELTO"), reporte(4, 2, "VALIDADO")]
    rep = calcular_reputacion([1, 2], reportes, [])
    assert rep[1]["puntaje"] < 50 < rep[2]["puntaje"]


def test_confirmaciones_suben_y_desmentidos_bajan():
    reportes = [reporte(1, 1), reporte(2, 2)]
    votos = [voto(3, 1), voto(4, 1), voto(3, 2, "DESMIENTE"), voto(4, 2, "DESMIENTE")]
    rep = calcular_reputacion([1, 2, 3, 4], reportes, votos)
    assert rep[1]["puntaje"] > 50 > rep[2]["puntaje"]
    assert rep[1]["confirmaciones_recibidas"] == 2 and rep[2]["desmentidos_recibidos"] == 2


def test_votos_de_cuentas_sospechosas_valen_menos():
    reportes = [reporte(1, 1), reporte(2, 2)]
    votos = [voto(3, 1), voto(4, 2)]
    normal = calcular_reputacion([1, 2, 3, 4], reportes, votos)
    con_sospecha = calcular_reputacion([1, 2, 3, 4], reportes, votos, sospechosos={4})
    assert con_sospecha[2]["puntaje"] < normal[2]["puntaje"]
    assert con_sospecha[1]["puntaje"] >= normal[1]["puntaje"] - 1


def test_reportes_e_incidentes_se_etiquetan_con_la_calle():
    from app.servicios.grafo.red import nodo

    assert nodo("Reporte", {"id": 17, "direccion": "Tucapel, Puerto Montt"})["etiqueta"] == "Tucapel"
    assert nodo("Reporte", {"id": 18, "direccion": None})["etiqueta"] == "Sin dirección"
    assert nodo("Incidente", {"id": 16, "direccion": "Av. Diego Portales 123, Puerto Montt"})["etiqueta"] == (
        "Incidente en Av. Diego Portales 123"
    )
    assert nodo("Incidente", {"id": 3})["etiqueta"] == "Incidente sin dirección"
