"""Nodos y aristas en el formato que dibuja la red de lugares del panel."""


def calle(direccion: str | None) -> str | None:
    """Solo la calle de la dirección de referencia ("Tucapel, Puerto Montt" -> "Tucapel")."""
    primera = (direccion or "").split(",")[0].strip()
    return primera or None


def _etiqueta(tipo: str, datos: dict) -> str:
    if tipo == "Usuario":
        return datos.get("alias") or f"Vecino {datos.get('id')}"
    if tipo == "Reporte":
        return datos.get("calle") or calle(datos.get("direccion")) or "Sin dirección"
    if tipo == "Incidente":
        lugar = calle(datos.get("direccion"))
        return f"Incidente en {lugar}" if lugar else "Incidente sin dirección"
    return str(datos.get("nombre") or datos.get("id"))


def nodo(tipo: str, datos: dict) -> dict:
    return {"clave": f"{tipo}:{datos['id']}", "tipo": tipo, "etiqueta": _etiqueta(tipo, datos), "datos": datos}


def arista(origen: str, destino: str, tipo: str, datos: dict | None = None) -> dict:
    return {"origen": origen, "destino": destino, "tipo": tipo, "datos": datos or {}}
