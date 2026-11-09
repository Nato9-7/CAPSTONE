"""Cuenta del vecino: registro, inicio y cierre de sesión, y perfil."""

from uuid import uuid4

import mysql.connector
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field

from app.comun.sql import error_bd, es_duplicado
from app.db import consultar, transaccion
from app.rutas.usuarios.verificacion import programar_correo_verificacion
from app.seguridad import (
    LARGO_MAXIMO_PASSWORD,
    LARGO_MINIMO_PASSWORD,
    crear_sesion,
    crear_token_verificacion,
    es_admin,
    esquema_bearer,
    hash_password,
    ip_cliente,
    revocar_sesion,
    usuario_actual,
    verificar_password,
)

router = APIRouter()

MENSAJE_USUARIO_EXISTENTE = "Ya existe un usuario con ese email o RUT"


class RegistroUsuario(BaseModel):
    nombres: str = Field(min_length=1, max_length=80)
    apellidos: str = Field(min_length=1, max_length=80)
    rut: str = Field(min_length=1, max_length=12)
    email: EmailStr
    telefono: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=LARGO_MINIMO_PASSWORD, max_length=LARGO_MAXIMO_PASSWORD)


class LoginUsuario(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=LARGO_MAXIMO_PASSWORD)


def _comuna_de_referencia(id_usuario: int) -> dict | None:
    """Comuna para una cuenta sin comuna: la de su último reporte y, si no hay, la primera con cobertura.

    Así el perfil siempre tiene teléfonos de emergencia que mostrar.
    """
    filas = consultar(
        """
        SELECT c.id_comuna, c.nombre AS comuna, r.nombre AS region
        FROM reporte rep
        JOIN comuna c ON c.id_comuna = rep.id_comuna
        JOIN region r ON r.id_region = c.id_region
        WHERE rep.id_usuario = %s
        ORDER BY rep.fecha_creacion DESC LIMIT 1
        """,
        (id_usuario,),
    ) or consultar(
        """
        SELECT c.id_comuna, c.nombre AS comuna, r.nombre AS region
        FROM comuna c JOIN region r ON r.id_region = c.id_region
        WHERE c.operativa = 1 ORDER BY c.id_comuna LIMIT 1
        """
    )
    return filas[0] if filas else None


def _emergencias(id_comuna: int | None) -> list[dict]:
    if id_comuna is None:
        return []
    return consultar(
        """
        SELECT nombre, tipo, telefono FROM entidad_emergencia
        WHERE id_comuna = %s AND activa = 1
        ORDER BY FIELD(tipo, 'CARABINEROS', 'BOMBEROS', 'SAMU', 'SEGURIDAD_CIUDADANA'), id_entidad
        """,
        (id_comuna,),
    )


@router.get("/perfil")
def perfil(usuario: dict = Depends(usuario_actual)):
    """Datos de la pantalla Perfil: cuenta, comuna, actividad y teléfonos de emergencia."""
    id_usuario = usuario["id_usuario"]
    filas = consultar(
        """
        SELECT u.nombres, u.apellidos, u.email, u.telefono, u.url_foto_perfil,
               u.email_verificado, u.estado, u.fecha_creacion,
               c.id_comuna, c.nombre AS comuna, r.nombre AS region
        FROM usuario u
        LEFT JOIN comuna c ON c.id_comuna = u.id_comuna
        LEFT JOIN region r ON r.id_region = c.id_region
        WHERE u.id_usuario = %s
        """,
        (id_usuario,),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    datos = filas[0]

    actividad = consultar(
        "SELECT COUNT(*) AS total, SUM(estado = 'RESUELTO') AS resueltos FROM reporte WHERE id_usuario = %s",
        (id_usuario,),
    )[0]

    if datos["id_comuna"] is None:
        referencia = _comuna_de_referencia(id_usuario)
        if referencia:
            datos.update(referencia)

    return {
        "nombres": datos["nombres"],
        "apellidos": datos["apellidos"],
        "email": datos["email"],
        "telefono": datos["telefono"],
        "url_foto_perfil": datos["url_foto_perfil"],
        "email_verificado": bool(datos["email_verificado"]),
        "estado": datos["estado"],
        "es_admin": es_admin(datos["email"], datos["email_verificado"]),
        "fecha_creacion": datos["fecha_creacion"],
        "comuna": datos["comuna"],
        "region": datos["region"],
        "total_reportes": int(actividad["total"] or 0),
        "total_resueltos": int(actividad["resueltos"] or 0),
        "emergencias": _emergencias(datos["id_comuna"]),
    }


@router.post("/login")
def iniciar_sesion(datos: LoginUsuario, request: Request):
    filas = consultar(
        """
        SELECT id_usuario, uuid_publico, nombres, apellidos, email, password_hash, estado, email_verificado
        FROM usuario WHERE email = %s
        """,
        (datos.email,),
    )
    if not filas or not verificar_password(datos.password, filas[0]["password_hash"]):
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos")

    usuario = filas[0]
    if usuario["estado"] in ("SUSPENDIDO", "ELIMINADO"):
        raise HTTPException(status_code=403, detail="Tu cuenta no está activa")

    if not usuario["email_verificado"]:
        # La app reconoce el código y ofrece reenviar el correo de verificación.
        raise HTTPException(
            status_code=403,
            detail={
                "codigo": "EMAIL_NO_VERIFICADO",
                "mensaje": "Verifica tu correo para iniciar sesión. Revisa tu bandeja de entrada (y la carpeta de spam).",
            },
        )

    # El token queda registrado (hasheado) en usuario_sesion; la app lo envía
    # como `Authorization: Bearer <token>` en las rutas protegidas.
    token = crear_sesion(usuario["id_usuario"], ip_cliente(request), request.headers.get("user-agent"))
    return {
        "token": token,
        "usuario": {
            "uuid_publico": usuario["uuid_publico"],
            "nombres": usuario["nombres"],
            "apellidos": usuario["apellidos"],
            "email": usuario["email"],
            "es_admin": es_admin(usuario["email"], usuario["email_verificado"]),
        },
    }


@router.post("/logout", status_code=204)
def cerrar_sesion(credenciales: HTTPAuthorizationCredentials | None = Depends(esquema_bearer)):
    if credenciales is not None:
        revocar_sesion(credenciales.credentials)
    return Response(status_code=204)


@router.post("/registro", status_code=201)
def registrar_usuario(datos: RegistroUsuario, request: Request, tareas: BackgroundTasks):
    existentes = consultar(
        "SELECT id_usuario FROM usuario WHERE email = %s OR rut = %s",
        (datos.email, datos.rut),
    )
    if existentes:
        raise HTTPException(status_code=409, detail=MENSAJE_USUARIO_EXISTENTE)

    uuid_publico = str(uuid4())
    try:
        # Usuario y token de verificación en la misma transacción: si falla
        # uno, no queda una cuenta a medias sin forma de verificarse.
        with transaccion() as cursor:
            cursor.execute(
                """
                INSERT INTO usuario (
                    uuid_publico, nombres, apellidos, rut, email, telefono,
                    password_hash, password_actualizada, estado,
                    email_verificado, telefono_verificado, intentos_fallidos
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW(), 'PENDIENTE', 0, 0, 0)
                """,
                (
                    uuid_publico, datos.nombres, datos.apellidos, datos.rut,
                    datos.email, datos.telefono, hash_password(datos.password),
                ),
            )
            token = crear_token_verificacion(cursor, cursor.lastrowid, ip_cliente(request))
    except mysql.connector.Error as error:
        # Dos registros casi simultáneos con el mismo correo o RUT.
        if es_duplicado(error):
            raise HTTPException(status_code=409, detail=MENSAJE_USUARIO_EXISTENTE) from error
        raise error_bd(error, "No se pudo crear la cuenta. Inténtalo otra vez") from error

    programar_correo_verificacion(tareas, f"{datos.nombres} {datos.apellidos}", datos.email, token)
    return {
        "uuid_publico": uuid_publico,
        "email": datos.email,
        "estado": "PENDIENTE",
        "verificacion_enviada": True,
    }
