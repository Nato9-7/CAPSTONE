from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam
from pydantic import BaseModel, Field

from app.db import transaccion
from app.rutas.comentarios import _reporte
from app.seguridad import usuario_actual

router = APIRouter()

# Con esta cantidad de denuncias pendientes (de personas distintas) un comentario
# se oculta solo hasta que el admin lo revise.
DENUNCIAS_PARA_OCULTAR = 3


class NuevaDenuncia(BaseModel):
    motivo: Literal["FALSO", "OFENSIVO", "SPAM", "DATOS_PERSONALES", "OTRO"]
    detalle: str | None = Field(None, max_length=300)


def _registrar(cursor, usuario: dict, datos: NuevaDenuncia, columna: str, id_objetivo: int, que: str) -> None:
    """Guarda la denuncia; cada persona denuncia una sola vez lo mismo."""
    cursor.execute(
        f"SELECT 1 FROM denuncia WHERE id_usuario = %s AND {columna} = %s",
        (usuario["id_usuario"], id_objetivo),
    )
    if cursor.fetchone():
        raise HTTPException(status_code=409, detail=f"Ya denunciaste este {que}")
    detalle = (datos.detalle or "").strip() or None
    cursor.execute(
        f"INSERT INTO denuncia (id_usuario, {columna}, motivo, detalle) VALUES (%s, %s, %s, %s)",
        (usuario["id_usuario"], id_objetivo, datos.motivo, detalle),
    )


@router.post("/{id_reporte}/denuncias", status_code=201)
def denunciar_reporte(
    datos: NuevaDenuncia,
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Un vecino denuncia un reporte (falso, ofensivo...). Llega al panel del admin;
    quien lo creó no se entera de quién lo denunció."""
    reporte = _reporte(id_reporte, usuario)
    if reporte["id_usuario"] == usuario["id_usuario"]:
        raise HTTPException(status_code=400, detail="No puedes denunciar tu propio reporte")
    with transaccion() as cursor:
        _registrar(cursor, usuario, datos, "id_reporte", id_reporte, "reporte")
    return {"id_reporte": id_reporte, "denunciado": True}


@router.post("/{id_reporte}/comentarios/{id_comentario}/denuncias", status_code=201)
def denunciar_comentario(
    datos: NuevaDenuncia,
    id_reporte: int = PathParam(ge=1),
    id_comentario: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Un vecino denuncia un comentario. Con DENUNCIAS_PARA_OCULTAR denuncias pendientes
    se oculta solo; el admin después lo elimina o lo vuelve a publicar."""
    _reporte(id_reporte, usuario)
    with transaccion() as cursor:
        cursor.execute(
            "SELECT id_usuario, estado FROM comentario WHERE id_comentario = %s AND id_reporte = %s FOR UPDATE",
            (id_comentario, id_reporte),
        )
        comentario = cursor.fetchone()
        if comentario is None or comentario["estado"] != "PUBLICADO":
            raise HTTPException(status_code=404, detail="El comentario ya no está visible")
        if comentario["id_usuario"] == usuario["id_usuario"]:
            raise HTTPException(status_code=400, detail="No puedes denunciar tu propio comentario")
        _registrar(cursor, usuario, datos, "id_comentario", id_comentario, "comentario")
        cursor.execute(
            "SELECT COUNT(*) AS total FROM denuncia WHERE id_comentario = %s AND estado = 'PENDIENTE'",
            (id_comentario,),
        )
        oculto = cursor.fetchone()["total"] >= DENUNCIAS_PARA_OCULTAR
        if oculto:
            cursor.execute("UPDATE comentario SET estado = 'OCULTO' WHERE id_comentario = %s", (id_comentario,))
    return {"id_comentario": id_comentario, "denunciado": True, "oculto": oculto}
