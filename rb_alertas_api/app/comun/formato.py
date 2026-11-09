"""Conversión de valores de la base de datos al formato de las respuestas JSON."""


def iso(fecha) -> str | None:
    return fecha.isoformat() if fecha else None


def entero(valor) -> int | None:
    return int(valor) if valor is not None else None


def decimal(valor) -> float | None:
    return float(valor) if valor is not None else None
