"""Análisis de la red de vecinos para el panel de administración.

Se calcula sobre quién confirma o desmiente los reportes de quién:

1. Cuentas coordinadas: vecinos que se confirman los reportes entre ellos mucho más
   que a los demás (posibles cuentas falsas que se inflan los reportes).
2. Reputación (0 a 100): una confirmación vale más si viene de un vecino confiable
   (PageRank sobre la red de confirmaciones), y se combina con cuántos de sus
   reportes terminaron validados o resueltos frente a los descartados.

Son funciones puras: reciben filas de MySQL y devuelven resultados, sin tocar la base.
"""

import math
from collections import defaultdict

# Cuentas coordinadas: confirmaciones dentro del grupo y qué parte de todas las que
# dan sus miembros se quedan dentro del grupo.
MINIMO_CONFIRMACIONES_INTERNAS = 3
RECIPROCIDAD_SOSPECHOSA = 0.6
RECIPROCIDAD_ALTA = 0.8

# Reputación.
AMORTIGUACION = 0.85          # PageRank estándar
ITERACIONES = 50
PESO_VOTO_SOSPECHOSO = 0.25   # los votos de cuentas coordinadas valen menos
REPORTES_BUENOS = ("VALIDADO", "RESUELTO")


def _apoyos(reportes: list[dict], votos: list[dict]) -> tuple[dict, dict]:
    """(confirmaciones, desmentidos)[votante][autor] = cuántas veces, sin votos a uno mismo."""
    autor = {r["id_reporte"]: r["id_usuario"] for r in reportes}
    confirma: dict = defaultdict(lambda: defaultdict(int))
    desmiente: dict = defaultdict(lambda: defaultdict(int))
    for v in votos:
        a = autor.get(v["id_reporte"])
        if a is None or a == v["id_usuario"]:
            continue
        destino = confirma if v["tipo_voto"] == "CONFIRMA" else desmiente
        destino[v["id_usuario"]][a] += 1
    return confirma, desmiente


def detectar_coordinacion(reportes: list[dict], votos: list[dict]) -> list[dict]:
    """Grupos de cuentas que se confirman mutuamente, del más sospechoso al menos.

    Dos vecinos quedan unidos si cada uno confirmó al menos un reporte del otro; los
    grupos son los conjuntos conectados por esas uniones. Se informan solo los que
    tienen MINIMO_CONFIRMACIONES_INTERNAS y cuya reciprocidad (confirmaciones dentro
    del grupo / todas las que dan sus miembros) llega a RECIPROCIDAD_SOSPECHOSA.
    """
    confirma, _ = _apoyos(reportes, votos)
    padre: dict[int, int] = {}

    def raiz(x: int) -> int:
        padre.setdefault(x, x)
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x

    for a, destinos in confirma.items():
        for b in destinos:
            if confirma.get(b, {}).get(a):
                padre[raiz(a)] = raiz(b)

    miembros: dict[int, list[int]] = defaultdict(list)
    for x in list(padre):
        miembros[raiz(x)].append(x)

    grupos = []
    for lista in miembros.values():
        if len(lista) < 2:
            continue
        dentro = set(lista)
        internas = sum(n for a in lista for b, n in confirma.get(a, {}).items() if b in dentro)
        totales = sum(n for a in lista for n in confirma.get(a, {}).values())
        reciprocidad = internas / totales if totales else 0.0
        if internas < MINIMO_CONFIRMACIONES_INTERNAS or reciprocidad < RECIPROCIDAD_SOSPECHOSA:
            continue
        grupos.append({
            "id": min(lista),
            "miembros": sorted(lista),
            "confirmaciones_internas": internas,
            "confirmaciones_totales": totales,
            "reciprocidad": round(reciprocidad, 3),
            "nivel": "ALTO" if reciprocidad >= RECIPROCIDAD_ALTA else "MEDIO",
        })
    grupos.sort(key=lambda g: (g["reciprocidad"], g["confirmaciones_internas"]), reverse=True)
    return grupos


def _pagerank(nodos: list[int], aristas: dict) -> dict[int, float]:
    """PageRank con pesos; la confianza fluye del que confirma hacia el autor."""
    n = len(nodos)
    if n == 0:
        return {}
    rango = {x: 1 / n for x in nodos}
    salida = {x: sum(aristas.get(x, {}).values()) for x in nodos}
    for _ in range(ITERACIONES):
        sin_salida = sum(rango[x] for x in nodos if not salida[x])
        nuevo = {x: (1 - AMORTIGUACION) / n + AMORTIGUACION * sin_salida / n for x in nodos}
        for a in nodos:
            if salida[a]:
                for b, peso in aristas.get(a, {}).items():
                    if b in nuevo:
                        nuevo[b] += AMORTIGUACION * rango[a] * peso / salida[a]
        rango = nuevo
    return rango


def calcular_reputacion(
    ids_usuarios: list[int],
    reportes: list[dict],
    votos: list[dict],
    sospechosos: set[int] | None = None,
) -> dict[int, dict]:
    """Puntaje de 0 a 100 por vecino, con sus componentes para explicarlo en el panel.

    - respaldo (0 a 1): confirmaciones recibidas menos desmentidos, cada voto pesado
      por la confianza (PageRank) de quien vota. Sin votos queda en 0.5.
    - historial (0 a 1): (validados o resueltos + 1) / (esos + descartados + 2).
      Sin reportes cerrados queda en 0.5.
    - puntaje = 100 × (respaldo + historial) / 2. Una cuenta nueva parte en 50.
    """
    sospechosos = sospechosos or set()
    confirma, desmiente = _apoyos(reportes, votos)

    def peso(votante: int) -> float:
        return PESO_VOTO_SOSPECHOSO if votante in sospechosos else 1.0

    aristas = {a: {b: n * peso(a) for b, n in destinos.items()} for a, destinos in confirma.items()}
    rango = _pagerank(ids_usuarios, aristas)
    n = len(ids_usuarios) or 1

    recibidas_conf: dict[int, float] = defaultdict(float)
    recibidas_desm: dict[int, float] = defaultdict(float)
    cuenta_conf: dict[int, int] = defaultdict(int)
    cuenta_desm: dict[int, int] = defaultdict(int)
    for votante, destinos in confirma.items():
        for autor, veces in destinos.items():
            recibidas_conf[autor] += veces * peso(votante) * rango.get(votante, 1 / n) * n
            cuenta_conf[autor] += veces
    for votante, destinos in desmiente.items():
        for autor, veces in destinos.items():
            recibidas_desm[autor] += veces * peso(votante) * rango.get(votante, 1 / n) * n
            cuenta_desm[autor] += veces

    buenos: dict[int, int] = defaultdict(int)
    malos: dict[int, int] = defaultdict(int)
    for r in reportes:
        if r["estado"] in REPORTES_BUENOS:
            buenos[r["id_usuario"]] += 1
        elif r["estado"] == "DESCARTADO":
            malos[r["id_usuario"]] += 1

    resultado = {}
    for u in ids_usuarios:
        # Dos confirmaciones de vecinos promedio llevan el respaldo a ~0.88.
        respaldo = 0.5 + 0.5 * math.tanh((recibidas_conf[u] - recibidas_desm[u]) / 2)
        historial = (buenos[u] + 1) / (buenos[u] + malos[u] + 2)
        resultado[u] = {
            "puntaje": round(100 * (respaldo + historial) / 2),
            "respaldo": round(respaldo, 3),
            "historial": round(historial, 3),
            "confianza": round(rango.get(u, 0) * n, 3),
            "confirmaciones_recibidas": cuenta_conf[u],
            "desmentidos_recibidos": cuenta_desm[u],
            "reportes_buenos": buenos[u],
            "reportes_descartados": malos[u],
        }
    return resultado
