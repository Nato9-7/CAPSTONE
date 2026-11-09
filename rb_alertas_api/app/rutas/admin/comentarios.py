"""Moderación de comentarios desde el panel: ocultar, volver a publicar, eliminar y suspender al autor."""

import logging
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam
from pydantic import BaseModel

from app.comun.archivos import borrar_archivos
from app.db import transaccion
from app.seguridad import usuario_admin
from app.servicios import moderacion
from app.servicios.comentarios import bloquear_comentario, marcar_eliminado

router = APIRouter()
log = logging.getLogger("rb_alertas.admin")


class CambioEstadoComentario(BaseModel):
    estado: Literal["PUBLICADO", "OCULTO"]


@router.patch("/comentarios/{id_comentario}/estado")
def cambiar_estado_comentario(
    datos: CambioEstadoComentario,
    id_comentario: int = PathParam(ge=1),
    admin: dict = Depends(usuario_admin),
):
    """Oculta un comentario (deja de verse en la app) o lo vuelve a publicar."""
    with transaccion() as cursor:
        fila = bloquear_comentario(cursor, id_comentario)
        if fila["estado"] == datos.estado:
            raise HTTPException(status_code=409, detail=f"El comentario ya está {datos.estado.lower()}")
        cursor.execute("UPDATE comentario SET estado = %s WHERE id_comentario = %s", (datos.estado, id_comentario))
        if datos.estado == "OCULTO":
            moderacion.cerrar_denuncias(cursor, "comentario", id_comentario, "ATENDIDA", admin["id_usuario"])
    return {"id_comentario": id_comentario, "estado": datos.estado}


@router.delete("/comentarios/{id_comentario}")
def eliminar_comentario(id_comentario: int = PathParam(ge=1), admin: dict = Depends(usuario_admin)):
    """Elimina un comentario mal intencionado: queda como ELIMINADO (igual que cuando lo
    borra su autor) y su foto se borra del disco."""
    with transaccion() as cursor:
        bloquear_comentario(cursor, id_comentario)
        archivos = marcar_eliminado(cursor, id_comentario)
        moderacion.cerrar_denuncias(cursor, "comentario", id_comentario, "ATENDIDA", admin["id_usuario"])
    borrar_archivos(archivos)
    log.warning("Comentario #%s eliminado por el admin #%s", id_comentario, admin["id_usuario"])
    return {"id_comentario": id_comentario, "estado": "ELIMINADO"}


@router.post("/comentarios/{id_comentario}/suspender-autor")
def suspender_autor_comentario(id_comentario: int = PathParam(ge=1)):
    """Suspende a quien escribió el comentario sin revelar su identidad en el panel."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_usuario FROM comentario WHERE id_comentario = %s", (id_comentario,))
        comentario = cursor.fetchone()
        if comentario is None:
            raise HTTPException(status_code=404, detail="Comentario no encontrado")
        moderacion.suspender_autor(cursor, comentario["id_usuario"], "Quien escribió este comentario ya está suspendido")
    return {"id_comentario": id_comentario, "estado_autor": "SUSPENDIDO"}
