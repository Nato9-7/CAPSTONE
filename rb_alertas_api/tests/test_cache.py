from app.comun import cache as modulo
from app.comun.cache import CacheTemporal


def test_reutiliza_el_valor_hasta_que_vence(monkeypatch):
    reloj = [100.0]
    monkeypatch.setattr(modulo.time, "monotonic", lambda: reloj[0])
    llamadas = []
    cache = CacheTemporal(segundos=300)

    def calcular():
        llamadas.append(1)
        return len(llamadas)

    assert cache.obtener("calor", calcular) == 1
    reloj[0] += 299
    assert cache.obtener("calor", calcular) == 1
    reloj[0] += 2
    assert cache.obtener("calor", calcular) == 2


def test_vaciar_obliga_a_recalcular():
    cache = CacheTemporal(segundos=300)
    assert cache.obtener("zonas", lambda: "antes") == "antes"
    cache.vaciar()
    assert cache.obtener("zonas", lambda: "despues") == "despues"


def test_cada_clave_guarda_su_valor():
    cache = CacheTemporal(segundos=300)
    cache.obtener(("calor", 60), lambda: "60 días")
    assert cache.obtener(("calor", 30), lambda: "30 días") == "30 días"
