from contextlib import contextmanager

from fastapi import HTTPException

from app.servicios.grafo import GrafoNoDisponible


@contextmanager
def grafo_disponible():
    """Traduce un grafo no configurado o caído en una respuesta 503 para el panel."""
    try:
        yield
    except GrafoNoDisponible as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
