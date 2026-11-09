"""Verificación del correo al registrarse."""

from fastapi import APIRouter, BackgroundTasks, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, EmailStr

from app.db import consultar, transaccion
from app.rutas.usuarios.paginas import pagina
from app.seguridad import TOKEN_VERIFICACION, crear_token_verificacion, hash_token, ip_cliente, token_reciente
from app.servicios.correo import correo_verificacion, enviar_correo

router = APIRouter()


class ReenvioVerificacion(BaseModel):
    email: EmailStr


def programar_correo_verificacion(tareas: BackgroundTasks, nombre: str, email: str, token: str) -> None:
    """El correo se envía después de responder: no demora el registro ni lo rompe si SMTP falla."""
    asunto, texto, html_cuerpo = correo_verificacion(nombre, email, token)
    tareas.add_task(enviar_correo, email, asunto, texto, html_cuerpo)


@router.get("/verificar", response_class=HTMLResponse)
def verificar_correo(token: str = Query(min_length=20, max_length=200)):
    """Destino del enlace del correo: marca el correo como verificado y activa la cuenta."""
    filas = consultar(
        """
        SELECT id_token, id_usuario FROM usuario_token
        WHERE token_hash = %s AND tipo = %s
          AND fecha_uso IS NULL AND fecha_expiracion > NOW()
        """,
        (hash_token(token), TOKEN_VERIFICACION),
    )
    if not filas:
        return pagina(
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
    return pagina("¡Correo verificado!", "Tu cuenta está activa. Ya puedes iniciar sesión en RB Alertas.", ok=True)


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
    if not filas or token_reciente(filas[0]["id_usuario"], TOKEN_VERIFICACION):
        return respuesta

    usuario = filas[0]
    with transaccion() as cursor:
        token = crear_token_verificacion(cursor, usuario["id_usuario"], ip_cliente(request))
    programar_correo_verificacion(tareas, usuario["nombres"], usuario["email"], token)
    return respuesta
