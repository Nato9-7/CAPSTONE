from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr, Field
from uuid import UUID, uuid4
import bcrypt
import mysql.connector

from app.db import consultar, ejecutar

router = APIRouter()


class RegistroUsuario(BaseModel):
    nombres: str = Field(min_length=1, max_length=80)
    apellidos: str = Field(min_length=1, max_length=80)
    rut: str = Field(min_length=1, max_length=12)
    email: EmailStr
    telefono: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=8, max_length=72)


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


@router.post("/registro", status_code=201)
def registrar_usuario(datos: RegistroUsuario):
    existentes = consultar(
        "SELECT id_usuario FROM usuario WHERE email = %s OR rut = %s",
        (datos.email, datos.rut),
    )
    if existentes:
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese email o RUT")

    uuid_publico = str(uuid4())
    password_hash = bcrypt.hashpw(datos.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    try:
        ejecutar(
            """
            INSERT INTO usuario (
                uuid_publico, nombres, apellidos, rut, email, telefono,
                password_hash, password_actualizada, estado,
                email_verificado, telefono_verificado, intentos_fallidos
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW(), 'pendiente', 0, 0, 0)
            """,
            (
                uuid_publico,
                datos.nombres,
                datos.apellidos,
                datos.rut,
                datos.email,
                datos.telefono,
                password_hash,
            ),
        )
    except mysql.connector.Error as error:
        raise HTTPException(status_code=400, detail=error.msg)

    return {"uuid_publico": uuid_publico, "email": datos.email, "estado": "pendiente"}
