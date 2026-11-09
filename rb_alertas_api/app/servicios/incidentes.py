"""Agrupa reportes parecidos en un solo incidente.

Varios vecinos suelen reportar el mismo hecho (un choque, un incendio). Dos reportes
son del mismo incidente si son de la misma categoría, están a menos de
DISTANCIA_MAXIMA_METROS y se crearon con menos de HORAS_MAXIMAS de diferencia. La
regla se encadena: si A se parece a B y B a C, los tres son un incidente.

No se guarda nada en la base: se calcula al consultar, así un reporte nuevo se une
al incidente al instante. El incidente se identifica con el id de su primer reporte.
"""

import math
import os
from datetime import datetime, timedelta

DISTANCIA_MAXIMA_METROS = float(os.getenv("INCIDENTE_DISTANCIA_METROS", "300"))
HORAS_MAXIMAS = float(os.getenv("INCIDENTE_HORAS", "3"))

_RADIO_TIERRA_METROS = 6_371_000


def distancia_metros(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distancia sobre la superficie de la Tierra (fórmula del haversine)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * _RADIO_TIERRA_METROS * math.asin(math.sqrt(a))


def _fecha(valor) -> datetime:
    if isinstance(valor, datetime):
        return valor
    return datetime.fromisoformat(str(valor))


def _parecidos(a: dict, b: dict) -> bool:
    return (
        a["categoria_codigo"] == b["categoria_codigo"]
        and abs(_fecha(a["fecha_creacion"]) - _fecha(b["fecha_creacion"])) <= timedelta(hours=HORAS_MAXIMAS)
        and distancia_metros(float(a["latitud"]), float(a["longitud"]),
                             float(b["latitud"]), float(b["longitud"])) <= DISTANCIA_MAXIMA_METROS
    )


def agrupar(reportes: list[dict]) -> list[list[dict]]:
    """Grupos de reportes del mismo incidente, cada uno ordenado del más antiguo al más nuevo.

    Cada reporte necesita id_reporte, categoria_codigo, latitud, longitud y fecha_creacion.
    Los grupos salen ordenados por su reporte más reciente (primero lo más nuevo).
    """
    padre = list(range(len(reportes)))

    def raiz(i: int) -> int:
        while padre[i] != i:
            padre[i] = padre[padre[i]]
            i = padre[i]
        return i

    for i in range(len(reportes)):
        for j in range(i + 1, len(reportes)):
            if _parecidos(reportes[i], reportes[j]):
                padre[raiz(i)] = raiz(j)

    grupos: dict[int, list[dict]] = {}
    for i, reporte in enumerate(reportes):
        grupos.setdefault(raiz(i), []).append(reporte)
    ordenados = [
        sorted(g, key=lambda r: (_fecha(r["fecha_creacion"]), r["id_reporte"]))
        for g in grupos.values()
    ]
    ordenados.sort(key=lambda g: _fecha(g[-1]["fecha_creacion"]), reverse=True)
    return ordenados


def resumir(reportes: list[dict]) -> list[dict]:
    """Un elemento por incidente, con la forma de un reporte para no romper la app.

    Toma los datos del primer reporte (el que abre el detalle) y agrega:
    id_incidente, total_reportes, ids_reportes, la fecha del reporte más reciente
    (ultima_actividad) y la suma de confirmaciones y desmentidos.
    """
    resultado = []
    for grupo in agrupar(reportes):
        primero = dict(grupo[0])
        primero["id_incidente"] = grupo[0]["id_reporte"]
        primero["total_reportes"] = len(grupo)
        primero["ids_reportes"] = [r["id_reporte"] for r in grupo]
        primero["ultima_actividad"] = grupo[-1]["fecha_creacion"]
        for campo in ("total_confirmaciones", "total_desmentidos"):
            if campo in primero:
                primero[campo] = sum(int(r.get(campo) or 0) for r in grupo)
        if "distancia_metros" in primero:
            primero["distancia_metros"] = min(float(r["distancia_metros"]) for r in grupo)
        resultado.append(primero)
    return resultado


def grupo_de(id_reporte: int, reportes: list[dict]) -> list[dict]:
    """El grupo (incidente) que contiene a id_reporte, o lista vacía si no está."""
    for grupo in agrupar(reportes):
        if any(r["id_reporte"] == id_reporte for r in grupo):
            return grupo
    return []
