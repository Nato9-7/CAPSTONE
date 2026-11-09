"""Nodos y aristas en el formato que dibuja el explorador del panel."""

TIPOS_NODO = (
    "Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura", "Coordinacion", "Incidente", "Grupo",
)

# Relaciones que unen vecinos y reportes en una misma comunidad. Lugares y
# categorías no cuentan: unirían a todos por igual.
_RELACIONES_DE_COMUNIDAD = (
    "CREO", "VOTO", "CONFIRMA_A", "DESMIENTE_A", "AGRUPA", "MIEMBRO_DE", "INTEGRA", "COMPARTIDO_EN",
)

# Cierre de las consultas Cypher que devuelven relaciones en filas (a)-[rel]->(b).
PROYECCION_RELACION = """
RETURN labels(startNode(rel))[0] AS tipo_a, properties(startNode(rel)) AS a,
       type(rel) AS tipo_rel, properties(rel) AS datos_rel,
       labels(endNode(rel))[0] AS tipo_b, properties(endNode(rel)) AS b
"""


def _etiqueta(tipo: str, datos: dict) -> str:
    if tipo == "Usuario":
        return datos.get("alias") or f"Vecino {datos.get('id')}"
    if tipo == "Reporte":
        return f"#{datos.get('id')}"
    if tipo == "Coordinacion":
        return f"Grupo de {datos.get('tamano', '?')} cuentas"
    if tipo == "Incidente":
        return f"Incidente #{datos.get('id')}"
    return str(datos.get("nombre") or datos.get("id"))


def nodo(tipo: str, datos: dict) -> dict:
    return {"clave": f"{tipo}:{datos['id']}", "tipo": tipo, "etiqueta": _etiqueta(tipo, datos), "datos": datos}


def arista(origen: str, destino: str, tipo: str, datos: dict | None = None) -> dict:
    return {"origen": origen, "destino": destino, "tipo": tipo, "datos": datos or {}}


def armar_red(filas: list[dict], extra_nodos: list[dict] | None = None) -> dict:
    """Nodos y aristas sin repetir a partir de filas (a)-[rel]->(b)."""
    nodos: dict[str, dict] = {n["clave"]: n for n in (extra_nodos or [])}
    aristas = []
    for fila in filas:
        a, b = nodo(fila["tipo_a"], fila["a"]), nodo(fila["tipo_b"], fila["b"])
        nodos.setdefault(a["clave"], a)
        nodos.setdefault(b["clave"], b)
        aristas.append(arista(a["clave"], b["clave"], fila["tipo_rel"], fila["datos_rel"]))
    return {"nodos": list(nodos.values()), "aristas": aristas}


def marcar_comunidades(red: dict) -> None:
    """Marca cada nodo con su comunidad: grupos de vecinos y reportes unidos por votos o creación.

    Se numeran de la más grande a la más chica; las de un solo nodo quedan sin comunidad.
    """
    padre: dict[str, str] = {}

    def raiz(x: str) -> str:
        padre.setdefault(x, x)
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x

    for a in red["aristas"]:
        if a["tipo"] in _RELACIONES_DE_COMUNIDAD:
            padre[raiz(a["origen"])] = raiz(a["destino"])
    tamanos: dict[str, int] = {}
    for n in red["nodos"]:
        tamanos[raiz(n["clave"])] = tamanos.get(raiz(n["clave"]), 0) + 1
    grandes = sorted((r for r, t in tamanos.items() if t > 1), key=lambda r: -tamanos[r])
    orden = {r: i for i, r in enumerate(grandes)}
    for n in red["nodos"]:
        n["comunidad"] = orden.get(raiz(n["clave"]))


def anillos(foco: str, aristas: list[dict], niveles: int = 2) -> dict[str, int]:
    """Distancia en pasos desde el nodo en foco, hasta `niveles` pasos."""
    anillo = {foco: 0}
    for nivel in range(1, niveles + 1):
        for a in aristas:
            for desde, hacia in ((a["origen"], a["destino"]), (a["destino"], a["origen"])):
                if anillo.get(desde) == nivel - 1 and hacia not in anillo:
                    anillo[hacia] = nivel
    return anillo
