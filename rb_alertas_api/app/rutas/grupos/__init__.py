"""Rutas de /api/grupos.

El orden importa: las rutas fijas (/en-punto, /unirse, /invitacion/...) van antes
que /{id_grupo} para que este no las capture.
"""

from fastapi import APIRouter

from app.rutas.grupos import chat, gestion, membresia

router = APIRouter()
for modulo in (membresia, gestion, chat):
    router.include_router(modulo.router)
