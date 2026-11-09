"""Rutas de /api/reportes.

El orden importa: las rutas fijas (/categorias, /cercanos, /mios...) van antes
que /{id_reporte} para que este no las capture.
"""

from fastapi import APIRouter

from app.rutas.reportes import comentarios, consultas, creacion, denuncias, detalle, votos

router = APIRouter()
for modulo in (consultas, creacion, detalle, votos, comentarios, denuncias):
    router.include_router(modulo.router)
