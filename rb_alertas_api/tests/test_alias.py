from app.comun.alias import alias_autor, alias_comentaristas, alias_miembro, mapa_alias


def test_alias_de_autor_es_fijo_por_reporte():
    # Valores ya publicados en la app: si cambian, los vecinos verían otros nombres.
    assert alias_autor(1) == "Suricata Intrépida 79"
    assert alias_autor(42) == "Suricata Protectora 70"
    assert alias_autor(1234) == "Suricata Valiente 23"


def test_alias_de_miembro_depende_del_grupo():
    assert alias_miembro(3, 7) == "Suricata Valiente 69"
    assert alias_miembro(10, 99) == "Suricata Vigía 13"
    assert alias_miembro(3, 7) != alias_miembro(4, 7)


def test_alias_de_comentaristas_no_repite_el_del_autor():
    alias = alias_comentaristas(42, 4)
    assert alias == ["Suricata Atenta 29", "Suricata Solidaria 66", "Suricata Serena 13", "Suricata Valiente 50"]
    assert alias_autor(42) not in alias
    assert len(set(alias_comentaristas(42, 200))) == 200


def test_mapa_alias_sigue_el_orden_de_llegada_y_el_autor_mantiene_su_alias():
    comentarios = [
        {"id_comentario": 3, "id_usuario": 9},
        {"id_comentario": 1, "id_usuario": 8},
        {"id_comentario": 2, "id_usuario": 5},
    ]
    assert mapa_alias(42, 5, comentarios) == {
        8: "Suricata Atenta 29",
        9: "Suricata Solidaria 66",
        5: "Suricata Protectora 70",
    }
