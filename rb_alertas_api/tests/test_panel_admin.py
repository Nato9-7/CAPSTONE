"""Reglas del panel: estado efectivo, transiciones permitidas, datos ocultos y calle de Nominatim."""

import pytest

from app.comun import enmascarar
from app.rutas.admin.reportes import TRANSICIONES, condiciones_busqueda, estado_efectivo
from app.servicios.geocodificacion import calle_de_direccion


@pytest.mark.parametrize(
    ("estado", "vencido", "esperado"),
    [
        ("PENDIENTE", True, "EXPIRADO"),
        ("VALIDADO", True, "EXPIRADO"),
        ("RESUELTO", True, "RESUELTO"),
        ("DESCARTADO", True, "DESCARTADO"),
        ("PENDIENTE", False, "PENDIENTE"),
    ],
)
def test_estado_efectivo(estado, vencido, esperado):
    assert estado_efectivo(estado, vencido) == esperado


def test_resuelto_es_final_y_expirado_solo_se_descarta():
    assert TRANSICIONES["RESUELTO"] == ()
    assert TRANSICIONES["EXPIRADO"] == ("DESCARTADO",)
    # Nunca se ofrece volver al mismo estado.
    assert all(estado not in destinos for estado, destinos in TRANSICIONES.items())


def test_busqueda_por_numero_o_por_texto():
    condiciones, parametros = condiciones_busqueda("#8329", None, None, None, None)
    assert condiciones == ["r.id_reporte = %s"] and parametros == [8329]

    condiciones, parametros = condiciones_busqueda("robo", "ROBO", 3, None, None)
    assert len(condiciones) == 3
    assert parametros == ["%robo%", "%robo%", "%robo%", "ROBO", 3]


def test_enmascarar_datos_personales():
    assert enmascarar.rut("20983086-8") == "2098••••-8"
    assert enmascarar.rut("20.983.086-8") == "2098••••-8"
    assert enmascarar.correo("renatodiazs@outlook.com") == "re••••@outlook.com"
    assert enmascarar.correo("a@b.cl") == "a••••@b.cl"
    assert enmascarar.telefono("+56989877562") == "••••••••7562"
    assert enmascarar.rut(None) is None and enmascarar.telefono("") == ""


def test_calle_de_direccion_prefiere_la_via():
    assert calle_de_direccion({"road": "Tucapel", "suburb": "Centro"}) == "Tucapel"
    assert calle_de_direccion({"pedestrian": "Paseo Talca"}) == "Paseo Talca"
    assert calle_de_direccion({"suburb": "Centro", "city": "Puerto Montt"}) is None
