from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field
from uuid import UUID, uuid4
import bcrypt
import mysql.connector

from app.correo import correo_verificacion, enviar_correo
from app.db import consultar, transaccion
from app.seguridad import (
    crear_sesion,
    crear_token_verificacion,
    esquema_bearer,
    hash_token,
    revocar_sesion,
    usuario_actual,
)

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


class ReenvioVerificacion(BaseModel):
    email: EmailStr


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _programar_correo_verificacion(tareas: BackgroundTasks, nombre: str, email: str, token: str) -> None:
    """El correo se envía después de responder: no demora el registro ni lo rompe si SMTP falla."""
    asunto, texto, html = correo_verificacion(nombre, email, token)
    tareas.add_task(enviar_correo, email, asunto, texto, html)


def _pagina(titulo: str, mensaje: str, ok: bool, status_code: int = 200) -> HTMLResponse:
    color = "#0056D2" if ok else "#B91C1C"
    return HTMLResponse(
        status_code=status_code,
        content=f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RB Alertas</title></head>
<body style="font-family:Segoe UI,Arial,sans-serif;background:#F1F3F8;margin:0;padding:48px 16px">
<div style="max-width:440px;margin:auto;background:#fff;border-radius:10px;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,.06)">
<div style="background:{color};color:#fff;padding:20px 24px;font-size:20px;font-weight:bold">{titulo}</div>
<p style="color:#374151;line-height:1.5;padding:8px 24px 16px;margin:16px 0">{mensaje}</p>
</div></body></html>""",
    )


@router.get("/")
def listar_usuarios(_: dict = Depends(usuario_actual)):
    return consultar("SELECT uuid_publico, nombres, email FROM usuario")


@router.get("/verificar", response_class=HTMLResponse)
def verificar_correo(token: str = Query(min_length=20, max_length=200)):
    """Destino del enlace del correo: marca el correo como verificado y activa la cuenta."""
    filas = consultar(
        """
        SELECT id_token, id_usuario FROM usuario_token
        WHERE token_hash = %s AND tipo = 'VERIFICACION_EMAIL'
          AND fecha_uso IS NULL AND fecha_expiracion > NOW()
        """,
        (hash_token(token),),
    )
    if not filas:
        return _pagina(
            "El enlace no es válido o ya venció",
            "Abre RB Alertas, intenta iniciar sesión y toca «Reenviar correo» para recibir un enlace nuevo.",
            ok=False,
            status_code=400,
        )

    with transaccion() as cursor:
        cursor.execute("UPDATE usuario_token SET fecha_uso = NOW() WHERE id_token = %s", (filas[0]["id_token"],))
        cursor.execute(
            """
            UPDATE usuario
            SET email_verificado = 1, estado = IF(estado = 'PENDIENTE', 'ACTIVO', estado)
            WHERE id_usuario = %s
            """,
            (filas[0]["id_usuario"],),
        )
    return _pagina("¡Correo verificado!", "Tu cuenta está activa. Ya puedes iniciar sesión en RB Alertas.", ok=True)


@router.post("/reenviar-verificacion", status_code=202)
def reenviar_verificacion(datos: ReenvioVerificacion, request: Request, tareas: BackgroundTasks):
    # Misma respuesta exista o no la cuenta, para no revelar qué correos están registrados.
    respuesta = {"detail": "Si el correo está registrado y falta verificarlo, te enviamos un nuevo enlace."}
    filas = consultar(
        """
        SELECT id_usuario, nombres, email FROM usuario
        WHERE email = %s AND email_verificado = 0 AND estado NOT IN ('SUSPENDIDO', 'ELIMINADO')
        """,
        (datos.email,),
    )
    if not filas:
        return respuesta

    usuario = filas[0]
    reciente = consultar(
        """
        SELECT 1 FROM usuario_token
        WHERE id_usuario = %s AND tipo = 'VERIFICACION_EMAIL'
          AND fecha_creacion > NOW() - INTERVAL 1 MINUTE
        """,
        (usuario["id_usuario"],),
    )
    if reciente:
        # Máximo un correo por minuto: evita usar esto para llenar la bandeja de alguien.
        return respuesta

    with transaccion() as cursor:
        token = crear_token_verificacion(cursor, usuario["id_usuario"], _ip(request))
    _programar_correo_verificacion(tareas, usuario["nombres"], usuario["email"], token)
    return respuesta


@router.get("/{uuid_publico}")
def obtener_usuario(uuid_publico: UUID, _: dict = Depends(usuario_actual)):
    filas = consultar(
        "SELECT uuid_publico, nombres, email FROM usuario WHERE uuid_publico = %s",
        (str(uuid_publico),)
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return filas[0]


@router.post("/login")
def iniciar_sesion(datos: LoginUsuario, request: Request):
    filas = consultar(
        """
        SELECT id_usuario, uuid_publico, nombres, apellidos, email, password_hash, estado, email_verificado
        FROM usuario WHERE email = %s
        """,
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
    token = crear_sesion(
        usuario["id_usuario"],
        _ip(request),
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
def registrar_usuario(datos: RegistroUsuario, request: Request, tareas: BackgroundTasks):
    existentes = consultar(
        "SELECT id_usuario FROM usuario WHERE email = %s OR rut = %s",
        (datos.email, datos.rut),
    )
    if existentes:
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese email o RUT")

    uuid_publico = str(uuid4())
    password_hash = bcrypt.hashpw(datos.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

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
                    uuid_publico,
                    datos.nombres,
                    datos.apellidos,
                    datos.rut,
                    datos.email,
                    datos.telefono,
                    password_hash,
                ),
            )
            token = crear_token_verificacion(cursor, cursor.lastrowid, _ip(request))
    except mysql.connector.Error as error:
        raise HTTPException(status_code=400, detail=error.msg)

    _programar_correo_verificacion(tareas, f"{datos.nombres} {datos.apellidos}", datos.email, token)
    return {
        "uuid_publico": uuid_publico,
        "email": datos.email,
        "estado": "PENDIENTE",
        "verificacion_enviada": True,
    }
