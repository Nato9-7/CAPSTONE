import mysql.connector

from app.comun.sql import MENSAJE_ERROR_GENERICO, error_bd, es_duplicado, marcas


def test_marcas():
    assert marcas(1) == "%s"
    assert marcas(3) == "%s, %s, %s"


def test_duplicado():
    assert es_duplicado(mysql.connector.Error(msg="Duplicate entry", errno=1062))
    assert not es_duplicado(mysql.connector.Error(msg="otro", errno=1452))


def test_error_interno_no_llega_al_cliente():
    error = mysql.connector.Error(msg="Cannot add or update a child row: fk_reporte_usuario", errno=1452, sqlstate="23000")
    respuesta = error_bd(error)
    assert respuesta.status_code == 400
    assert respuesta.detail == MENSAJE_ERROR_GENERICO
    assert error_bd(error, "No se pudo guardar el reporte").detail == "No se pudo guardar el reporte"


def test_mensaje_de_trigger_si_llega_al_cliente():
    error = mysql.connector.Error(msg="Ya votaste este reporte", errno=1644, sqlstate="45000")
    assert error_bd(error).detail == "Ya votaste este reporte"
