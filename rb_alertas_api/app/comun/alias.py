"""Nombres de fantasía con que la API muestra a las personas.

Por seguridad, el nombre real de quien reporta, comenta o integra un grupo nunca
sale de la API (evita represalias contra quien denuncia). Cada alias se deriva de
un hash: es siempre el mismo al recargar y no permite deducir el id del usuario.
"""

import hashlib

ADJETIVOS_SURICATA = (
    "Vigía", "Centinela", "Valiente", "Atenta", "Curiosa", "Veloz", "Guardiana", "Exploradora",
    "Solidaria", "Despierta", "Alerta", "Intrépida", "Astuta", "Serena", "Audaz", "Protectora",
)


def _semilla(texto: str) -> int:
    return int.from_bytes(hashlib.sha256(texto.encode()).digest()[:8], "big")


def _alias(semilla: int, paso: int = 0) -> str:
    # Saltos coprimos con 16 adjetivos y 90 números: el par no se repite en 720
    # pasos y los números no salen correlativos (no delatan el orden de llegada).
    adjetivo = ADJETIVOS_SURICATA[(semilla + paso * 5) % len(ADJETIVOS_SURICATA)]
    numero = 10 + (semilla // len(ADJETIVOS_SURICATA) + paso * 37) % 90
    return f"Suricata {adjetivo} {numero}"


def alias_autor(id_reporte: int) -> str:
    """Alias fijo por reporte, p. ej. «Suricata Centinela 42».

    Sale del id del reporte y no del usuario: dos reportes de la misma persona tienen
    alias distintos, así nadie puede juntar sus reportes para adivinar quién es.
    """
    return _alias(_semilla(f"alias-reporte:{id_reporte}"))


def alias_miembro(id_grupo: int, id_usuario: int) -> str:
    """Alias fijo del vecino dentro de un grupo.

    Depende del grupo, así el mismo vecino tiene alias distintos en grupos
    distintos y no se le puede seguir de un grupo a otro.
    """
    return _alias(_semilla(f"alias-grupo:{id_grupo}:{id_usuario}"))


def alias_comentaristas(id_reporte: int, cantidad: int) -> list[str]:
    """Alias de quienes comentan un reporte, en orden de llegada a la conversación.

    Depende del reporte y del orden en que cada persona comentó por primera vez (no
    de su id): es fijo dentro del reporte, distinto entre reportes y no permite juntar
    los comentarios de alguien en reportes distintos. Nunca repite el alias del autor.
    """
    semilla = _semilla(f"alias-comentario:{id_reporte}")
    reservado = alias_autor(id_reporte)
    alias, paso = [], 0
    while len(alias) < cantidad:
        nombre = _alias(semilla, paso)
        paso += 1
        if nombre != reservado:
            alias.append(nombre)
    return alias


def mapa_alias(id_reporte: int, id_autor_reporte: int, comentarios: list[dict]) -> dict[int, str]:
    """id_usuario -> alias. `comentarios` son todos los del reporte (en cualquier estado)."""
    orden = []
    for fila in sorted(comentarios, key=lambda f: f["id_comentario"]):
        if fila["id_usuario"] != id_autor_reporte and fila["id_usuario"] not in orden:
            orden.append(fila["id_usuario"])
    mapa = dict(zip(orden, alias_comentaristas(id_reporte, len(orden))))
    # Si quien reportó comenta, aparece con el mismo alias del reporte.
    mapa[id_autor_reporte] = alias_autor(id_reporte)
    return mapa
