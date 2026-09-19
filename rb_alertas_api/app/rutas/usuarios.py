from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field
from uuid import UUID, uuid4
import bcrypt
import mysql.connector

from app.db import consultar, ejecutar
from app.seguridad import crear_sesion, esquema_bearer, revocar_sesion, usuario_actual

router = APIRouter()


class RegistroUsuario(BaseModel):
    nombres: str = Field(min_length=1, max_length=80)
    apellidos: str = Field(min_length=1, max_length=80)
    rut: str = Field(min_length=1, max_length=12)
    email: EmailStr
    telefono: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=8, max_length=72)


class LoginUsuario(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=72)


@router.get("/")
def listar_usuarios(_: dict = Depends(usuario_actual)):
    return consultar("SELECT uuid_publico, nombres, email FROM usuario")


@router.get("/{uuid_publico}")
def obtener_usuario(uuid_publico: UUID, _: dict = Depends(usuario_actual)):
    filas = consultar(
        "SELECT uuid_publico, nombres, email FROM usuario WHERE uuid_publico = %s",
        (uuid_publico,)
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return filas[0]


@router.post("/login")
def iniciar_sesion(datos: LoginUsuario, request: Request):
    filas = consultar(
        "SELECT id_usuario, uuid_publico, nombres, apellidos, email, password_hash, estado FROM usuario WHERE email = %s",
        (datos.email,),
    )
    credenciales_invalidas = HTTPException(status_code=401, detail="Correo o contraseña incorrectos")

    if not filas:
        raise credenciales_invalidas

    usuario = filas[0]
    if not bcrypt.checkpw(datos.password.encode("utf-8"), usuario["password_hash"].encode("utf-8")):
        raise credenciales_invalidas

    if usuario["estado"] in ("SUSPENDIDO", "ELIMINADO"):
        raise HTTPException(status_code=403, detail="Tu cuenta no está activa")

    # El token queda registrado (hasheado) en usuario_sesion; la app lo envía
    # como `Authorization: Bearer <token>` en las rutas protegidas.
    token = crear_sesion(
        usuario["id_usuario"],
        request.client.host if request.client else None,
        request.headers.get("user-agent"),
    )
    return {
        "token": token,
        "usuario": {
            "uuid_publico": usuario["uuid_publico"],
            "nombres": usuario["nombres"],
            "apellidos": usuario["apellidos"],
            "email": usuario["email"],
        },
    }


@router.post("/logout", status_code=204)
def cerrar_sesion(credenciales: HTTPAuthorizationCredentials | None = Depends(esquema_bearer)):
    if credenciales is not None:
        revocar_sesion(credenciales.credentials)
    return Response(status_code=204)


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
