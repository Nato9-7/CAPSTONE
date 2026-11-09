"""Rutas de /api/admin (panel de administración).

Todas exigen sesión de una cuenta admin (ver seguridad.CORREOS_ADMIN): la
dependencia del router se aplica a cada ruta incluida.
"""

from fastapi import APIRouter, Depends

from app.rutas.admin import comentarios, denuncias, grafo_explorador, grafo_hallazgos, grupos, reportes, resumen, usuarios
from app.seguridad import usuario_admin

router = APIRouter(dependencies=[Depends(usuario_admin)])
for modulo in (resumen, reportes, comentarios, denuncias, usuarios, grupos, grafo_hallazgos, grafo_explorador):
    router.include_router(modulo.router)
