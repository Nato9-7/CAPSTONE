"""Datos personales parcialmente ocultos para el panel (minimización, Ley 21.719).

El panel lista cuentas con estos valores; el dato completo solo se entrega cuando
un administrador lo pide expresamente (GET /admin/usuarios/{id}/contacto), y esa
consulta queda en el registro de la API.
"""

OCULTO = "•"


def rut(valor: str | None) -> str | None:
    """'20983086-8' -> '2098••••-8': se ven los primeros 4 dígitos y el verificador."""
    if not valor:
        return valor
    cuerpo, _, dv = valor.replace(".", "").partition("-")
    visible = cuerpo[:4]
    return f"{visible}{OCULTO * max(len(cuerpo) - len(visible), 0)}-{dv}" if dv else visible + OCULTO * 4


def correo(valor: str | None) -> str | None:
    """'renatodiazs@outlook.com' -> 're••••@outlook.com'. Siempre 4 puntos: no revela el largo."""
    if not valor or "@" not in valor:
        return valor
    usuario, dominio = valor.split("@", 1)
    return f"{usuario[:2]}{OCULTO * 4}@{dominio}"


def telefono(valor: str | None) -> str | None:
    """'+56989877562' -> '•••••••7562': solo los últimos 4 dígitos."""
    if not valor:
        return valor
    return OCULTO * max(len(valor) - 4, 0) + valor[-4:]
