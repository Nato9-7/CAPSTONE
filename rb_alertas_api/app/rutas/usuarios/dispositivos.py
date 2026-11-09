from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.db import ejecutar
from app.seguridad import usuario_actual

router = APIRouter()


class Dispositivo(BaseModel):
    token_push: str = Field(min_length=1, max_length=255)
    plataforma: Literal["ANDROID", "IOS", "WEB"]
    modelo: str | None = Field(None, max_length=100)
    version_so: str | None = Field(None, max_length=40)
    version_app: str | None = Field(None, max_length=20)


class BajaDispositivo(BaseModel):
    token_push: str = Field(min_length=1, max_length=255)


@router.post("/", status_code=204)
def registrar_dispositivo(datos: Dispositivo, usuario: dict = Depends(usuario_actual)):
    """La app lo llama al iniciar sesión, al abrirse con una sesión guardada y
    cuando FCM le entrega un token nuevo.

    token_push es único: si el teléfono ya estaba registrado con otra cuenta
    (equipo compartido o cambio de cuenta), la fila pasa a quien inició sesión,
    así ese teléfono solo recibe las alertas de la cuenta activa.
    """
    ejecutar(
        """
        INSERT INTO usuario_dispositivo (
            id_usuario, token_push, plataforma, modelo, version_so, version_app,
            activo, ultima_actividad
        )
        VALUES (%s, %s, %s, %s, %s, %s, 1, NOW())
        ON DUPLICATE KEY UPDATE
            id_usuario = VALUES(id_usuario),
            plataforma = VALUES(plataforma),
            modelo = VALUES(modelo),
            version_so = VALUES(version_so),
            version_app = VALUES(version_app),
            activo = 1,
            ultima_actividad = NOW()
        """,
        (
            usuario["id_usuario"],
            datos.token_push,
            datos.plataforma,
            datos.modelo,
            datos.version_so,
            datos.version_app,
        ),
    )
    return None


@router.post("/baja", status_code=204)
def dar_de_baja_dispositivo(datos: BajaDispositivo, usuario: dict = Depends(usuario_actual)):
    """Al cerrar sesión: el dispositivo deja de recibir avisos, pero la fila se
    conserva y vuelve a activarse si alguien inicia sesión en ese teléfono."""
    ejecutar(
        "UPDATE usuario_dispositivo SET activo = 0 WHERE token_push = %s AND id_usuario = %s",
        (datos.token_push, usuario["id_usuario"]),
    )
    return None
