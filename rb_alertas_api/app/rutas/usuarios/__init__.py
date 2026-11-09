"""Rutas de /api/usuarios: cuenta, verificación, recuperación, zonas seguras, alertas y dispositivos."""

from fastapi import APIRouter

from app.rutas.usuarios import cuenta, dispositivos, notificaciones, recuperacion, verificacion, zonas

router = APIRouter()
for modulo in (cuenta, verificacion, recuperacion):
    router.include_router(modulo.router)
router.include_router(zonas.router, prefix="/zonas")
router.include_router(notificaciones.router, prefix="/notificaciones")
router.include_router(dispositivos.router, prefix="/dispositivos")
