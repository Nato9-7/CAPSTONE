from fastapi import APIRouter, HTTPException
from app.db import consultar
from uuid import UUID

router = APIRouter()

@router.get("/")
def listar_usuarios():
    return consultar("SELECT uuid_publico, nombres, email FROM usuario")

@router.get("/{uuid_publico}")
def obtener_usuario(uuid_publico: UUID):
    filas = consultar(
        "SELECT uuid_publico, nombres, email FROM usuario WHERE uuid_publico = %s",
        (uuid_publico,)
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return filas[0]