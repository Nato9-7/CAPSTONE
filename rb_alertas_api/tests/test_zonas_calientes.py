import mysql.connector.pooling as pooling

# Las rutas importan app.db, que abre MySQL al cargarse; en las pruebas no hace falta.
pooling.MySQLConnectionPool.__init__ = lambda self, **k: None

from app.rutas import admin  # noqa: E402

ROBO = {"id": 1, "codigo": "ROBO", "nombre": "Robo o asalto", "color": "#C2410C"}
ACCIDENTE = {"id": 2, "codigo": "ACCIDENTE", "nombre": "Accidente de tránsito", "color": "#B91C1C"}


def fila(lugar_id, nombre, categoria, hechos, reportes):
    # Así responde la consulta Cypher: una fila por lugar y categoría.
    return {
        "tipo": "Localidad",
        "lugar": {"id": lugar_id, "nombre": nombre},
        "comuna": "Puerto Montt",
        "categoria": categoria,
        "total": hechos,
        "reportes": reportes,
    }


def test_cuenta_hechos_y_guarda_los_reportes(monkeypatch):
    consultas = []

    def falso(cypher, **parametros):
        consultas.append(cypher)
        return [
            # Mirasol: 3 robos, pero uno lo reportaron 4 vecinos -> 6 reportes.
            fila(1, "Mirasol", ROBO, 3, 6),
            fila(1, "Mirasol", ACCIDENTE, 1, 1),
            # Pelluco: 5 robos distintos.
            fila(2, "Pelluco", ROBO, 5, 5),
        ]

    monkeypatch.setattr(admin.grafo, "consultar_grafo", falso)
    lugares = admin._zonas_calientes(None, None)

    # El ranking es por hechos: Pelluco (5) va antes que Mirasol (4), aunque
    # Mirasol tenga más reportes (7).
    assert [l["datos"]["nombre"] for l in lugares] == ["Pelluco", "Mirasol"]
    mirasol = lugares[1]
    assert (mirasol["total"], mirasol["reportes"]) == (4, 7)
    assert mirasol["por_categoria"][0] == {
        "id": 1, "codigo": "ROBO", "nombre": "Robo o asalto", "color": "#C2410C", "total": 3, "reportes": 6,
    }
    assert mirasol["intensidad"] == 0.8

    # La consulta junta los reportes del mismo Incidente.
    assert "Incidente" in consultas[0] and "count(DISTINCT coalesce(inc.id, r.id))" in consultas[0]


def test_nodo_del_lugar_lleva_hechos_y_reportes(monkeypatch):
    monkeypatch.setattr(admin.grafo, "consultar_grafo", lambda c, **p: [fila(1, "Mirasol", ROBO, 2, 5)])
    nodo = admin._nodo_lugar(admin._zonas_calientes("ROBO", None)[0])
    assert (nodo["datos"]["total"], nodo["datos"]["reportes"]) == (2, 5)
