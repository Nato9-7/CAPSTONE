"""Recuperación de contraseña: correo con enlace y formulario para crear una nueva."""

from fastapi import APIRouter, BackgroundTasks, Form, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, EmailStr

from app.db import consultar, transaccion
from app.rutas.usuarios.paginas import enlace_recuperacion_vencido, formulario_restablecer, pagina
from app.seguridad import (
    LARGO_MAXIMO_PASSWORD,
    LARGO_MINIMO_PASSWORD,
    TOKEN_RECUPERACION,
    crear_token_recuperacion,
    hash_password,
    hash_token,
    ip_cliente,
    revocar_sesiones_usuario,
    token_reciente,
)
from app.servicios.correo import correo_recuperacion, enviar_correo

router = APIRouter()


class RecuperacionPassword(BaseModel):
    email: EmailStr


def _usuario_de_token_recuperacion(token: str) -> dict | None:
    filas = consultar(
        """
        SELECT t.id_token, u.id_usuario, u.email
        FROM usuario_token t
        JOIN usuario u ON u.id_usuario = t.id_usuario
        WHERE t.token_hash = %s AND t.tipo = %s
          AND t.fecha_uso IS NULL AND t.fecha_expiracion > NOW()
          AND u.estado NOT IN ('SUSPENDIDO', 'ELIMINADO')
        """,
        (hash_token(token), TOKEN_RECUPERACION),
    )
    return filas[0] if filas else None


def _error_password(password: str, confirmacion: str) -> str | None:
    if not LARGO_MINIMO_PASSWORD <= len(password) <= LARGO_MAXIMO_PASSWORD:
        return f"La contraseña debe tener entre {LARGO_MINIMO_PASSWORD} y {LARGO_MAXIMO_PASSWORD} caracteres."
    if len(password.encode("utf-8")) > LARGO_MAXIMO_PASSWORD:
        return "La contraseña es demasiado larga."
    if password != confirmacion:
        return "Las contraseñas no coinciden."
    return None


@router.post("/recuperar-password", status_code=202)
def recuperar_password(datos: RecuperacionPassword, request: Request, tareas: BackgroundTasks):
    """Envía un enlace para crear una contraseña nueva."""
    # Misma respuesta exista o no la cuenta, para no revelar qué correos están registrados.
    respuesta = {"detail": "Si el correo está registrado, te enviamos un enlace para crear una contraseña nueva."}
    filas = consultar(
        """
        SELECT id_usuario, nombres, apellidos, email FROM usuario
        WHERE email = %s AND estado NOT IN ('SUSPENDIDO', 'ELIMINADO')
        """,
        (datos.email,),
    )
    if not filas or token_reciente(filas[0]["id_usuario"], TOKEN_RECUPERACION):
        return respuesta

    usuario = filas[0]
    with transaccion() as cursor:
        token = crear_token_recuperacion(cursor, usuario["id_usuario"], ip_cliente(request))
    asunto, texto, html_cuerpo = correo_recuperacion(
        f"{usuario['nombres']} {usuario['apellidos']}", usuario["email"], token
    )
    tareas.add_task(enviar_correo, usuario["email"], asunto, texto, html_cuerpo)
    return respuesta


@router.get("/restablecer", response_class=HTMLResponse)
def ver_formulario_restablecer(token: str = Query(min_length=20, max_length=200)):
    """Destino del enlace del correo de recuperación."""
    usuario = _usuario_de_token_recuperacion(token)
    if usuario is None:
        return enlace_recuperacion_vencido()
    return formulario_restablecer(token, usuario["email"])


@router.post("/restablecer", response_class=HTMLResponse)
def restablecer_password(
    token: str = Form(min_length=20, max_length=200),
    password: str = Form(""),
    confirmacion: str = Form(""),
):
    usuario = _usuario_de_token_recuperacion(token)
    if usuario is None:
        return enlace_recuperacion_vencido()

    error = _error_password(password, confirmacion)
    if error:
        return formulario_restablecer(token, usuario["email"], error, status_code=400)

    password_hash = hash_password(password)
    with transaccion() as cursor:
        # Se marca el token como usado primero: si dos envíos llegan juntos, solo uno pasa.
        cursor.execute(
            "UPDATE usuario_token SET fecha_uso = NOW() WHERE id_token = %s AND fecha_uso IS NULL",
            (usuario["id_token"],),
        )
        if cursor.rowcount != 1:
            return enlace_recuperacion_vencido()
        # Abrir el enlace del correo también demuestra que el correo es suyo.
        cursor.execute(
            """
            UPDATE usuario
            SET password_hash = %s, password_actualizada = NOW(), intentos_fallidos = 0,
                email_verificado = 1, estado = IF(estado = 'PENDIENTE', 'ACTIVO', estado)
            WHERE id_usuario = %s
            """,
            (password_hash, usuario["id_usuario"]),
        )
        # Quien tuviera la contraseña anterior queda fuera de todos los dispositivos.
        revocar_sesiones_usuario(cursor, usuario["id_usuario"])

    return pagina(
        "¡Contraseña actualizada!",
        "Ya puedes iniciar sesión en RB Alertas con tu contraseña nueva. "
        "Por seguridad, cerramos la sesión en todos tus dispositivos.",
        ok=True,
    )
