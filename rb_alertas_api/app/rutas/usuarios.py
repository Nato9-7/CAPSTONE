from fastapi import APIRouter, BackgroundTasks, Depends, Form, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field
from uuid import uuid4
import bcrypt
import html
import mysql.connector

from app.correo import correo_recuperacion, correo_verificacion, enviar_correo
from app.db import consultar, transaccion
from app.seguridad import (
    crear_sesion,
    crear_token_recuperacion,
    crear_token_verificacion,
    es_admin,
    esquema_bearer,
    hash_token,
    revocar_sesion,
    revocar_sesiones_usuario,
    usuario_actual,
)

# Mismos límites que el registro (bcrypt solo usa los primeros 72 bytes).
LARGO_MINIMO_PASSWORD = 8
LARGO_MAXIMO_PASSWORD = 72

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


class RecuperacionPassword(BaseModel):
    email: EmailStr


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _programar_correo_verificacion(tareas: BackgroundTasks, nombre: str, email: str, token: str) -> None:
    """El correo se envía después de responder: no demora el registro ni lo rompe si SMTP falla."""
    asunto, texto, html = correo_verificacion(nombre, email, token)
    tareas.add_task(enviar_correo, email, asunto, texto, html)


# Páginas que abren los enlaces del correo. Usan los mismos colores y formas que
# las pantallas de la app (inicio de sesión): tarjeta blanca sobre fondo claro.
_ESTILO_PAGINAS = """
body{margin:0;padding:40px 20px;background:#F8FAFC;font-family:'Segoe UI',Roboto,Arial,sans-serif;color:#374151}
.tarjeta{max-width:420px;margin:auto;box-sizing:border-box;background:#fff;border:1.5px solid #DCE4F2;
  border-radius:24px;box-shadow:0 4px 16px rgba(0,0,0,.04);padding:36px 28px;text-align:center}
.logo{display:block;width:88px;height:88px;object-fit:contain;margin:0 auto 22px}
h1{margin:0 0 10px;font-size:24px;font-weight:800;letter-spacing:-.4px;color:#0056D2}
h1.error{color:#B91C1C}
p{margin:0 0 8px;font-size:14px;line-height:1.45;color:#6B7280}
form{text-align:left;margin-top:24px}
label{display:block;font-size:13px;font-weight:700;color:#1F2937;margin-bottom:8px}
input[type=password]{width:100%;box-sizing:border-box;padding:14px 16px;margin-bottom:18px;font-size:15px;
  background:#F0F4FF;border:1.2px solid #D4E2FB;border-radius:12px;outline:none}
input[type=password]:focus{border:1.8px solid #0056D2}
.ayuda{font-size:12.5px;margin:-8px 0 22px}
.aviso{background:#FEE2E2;color:#B91C1C;border-radius:12px;padding:10px 14px;font-size:13.5px;margin:0 0 18px}
button{width:100%;height:48px;border:0;border-radius:12px;background:#0056D2;color:#fff;font-size:16px;
  font-weight:700;cursor:pointer}
"""


_LOGO = '<img class="logo" src="/estaticos/logo.png" alt="RB Alertas">'


def _documento(cuerpo: str, status_code: int = 200) -> HTMLResponse:
    return HTMLResponse(
        status_code=status_code,
        content=f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>RB Alertas</title>
<style>{_ESTILO_PAGINAS}</style></head>
<body><div class="tarjeta">{cuerpo}</div></body></html>""",
    )


def _pagina(titulo: str, mensaje: str, ok: bool, status_code: int = 200) -> HTMLResponse:
    clase = "" if ok else ' class="error"'
    return _documento(
        f"""{_LOGO}
<h1{clase}>{titulo}</h1>
<p>{mensaje}</p>""",
        status_code,
    )


@router.get("/perfil")
def perfil(usuario: dict = Depends(usuario_actual)):
    """Datos de la pantalla Perfil: cuenta, comuna, actividad y teléfonos de emergencia."""
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
        (usuario["id_usuario"],),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    datos = filas[0]

    actividad = consultar(
        """
        SELECT COUNT(*) AS total,
               SUM(estado = 'RESUELTO') AS resueltos
        FROM reporte WHERE id_usuario = %s
        """,
        (usuario["id_usuario"],),
    )[0]

    # Si la cuenta no tiene comuna, se usa la del último reporte y, si tampoco
    # hay, la comuna con cobertura: así siempre hay teléfonos que mostrar.
    id_comuna = datos["id_comuna"]
    if id_comuna is None:
        referencia = consultar(
            """
            SELECT c.id_comuna, c.nombre AS comuna, r.nombre AS region
            FROM reporte rep
            JOIN comuna c ON c.id_comuna = rep.id_comuna
            JOIN region r ON r.id_region = c.id_region
            WHERE rep.id_usuario = %s
            ORDER BY rep.fecha_creacion DESC LIMIT 1
            """,
            (usuario["id_usuario"],),
        ) or consultar(
            """
            SELECT c.id_comuna, c.nombre AS comuna, r.nombre AS region
            FROM comuna c JOIN region r ON r.id_region = c.id_region
            WHERE c.operativa = 1 ORDER BY c.id_comuna LIMIT 1
            """
        )
        if referencia:
            id_comuna = referencia[0]["id_comuna"]
            datos["comuna"] = referencia[0]["comuna"]
            datos["region"] = referencia[0]["region"]

    emergencias = consultar(
        """
        SELECT nombre, tipo, telefono FROM entidad_emergencia
        WHERE id_comuna = %s AND activa = 1
        ORDER BY FIELD(tipo, 'CARABINEROS', 'BOMBEROS', 'SAMU', 'SEGURIDAD_CIUDADANA'), id_entidad
        """,
        (id_comuna,),
    ) if id_comuna is not None else []

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
        "emergencias": emergencias,
    }


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
    if not filas:
        return respuesta

    usuario = filas[0]
    reciente = consultar(
        """
        SELECT 1 FROM usuario_token
        WHERE id_usuario = %s AND tipo = 'RECUPERACION_PASSWORD'
          AND fecha_creacion > NOW() - INTERVAL 1 MINUTE
        """,
        (usuario["id_usuario"],),
    )
    if reciente:
        # Máximo un correo por minuto: evita usar esto para llenar la bandeja de alguien.
        return respuesta

    with transaccion() as cursor:
        token = crear_token_recuperacion(cursor, usuario["id_usuario"], _ip(request))
    asunto, texto, html_cuerpo = correo_recuperacion(
        f"{usuario['nombres']} {usuario['apellidos']}", usuario["email"], token
    )
    tareas.add_task(enviar_correo, usuario["email"], asunto, texto, html_cuerpo)
    return respuesta


def _usuario_de_token_recuperacion(token: str):
    filas = consultar(
        """
        SELECT t.id_token, u.id_usuario, u.email
        FROM usuario_token t
        JOIN usuario u ON u.id_usuario = t.id_usuario
        WHERE t.token_hash = %s AND t.tipo = 'RECUPERACION_PASSWORD'
          AND t.fecha_uso IS NULL AND t.fecha_expiracion > NOW()
          AND u.estado NOT IN ('SUSPENDIDO', 'ELIMINADO')
        """,
        (hash_token(token),),
    )
    return filas[0] if filas else None


def _enlace_vencido() -> HTMLResponse:
    return _pagina(
        "El enlace no es válido o ya venció",
        "Abre RB Alertas, toca «¿Olvidé mi contraseña?» y pide un enlace nuevo. "
        "Cada enlace sirve una sola vez y dura 1 hora.",
        ok=False,
        status_code=400,
    )


def _formulario_restablecer(token: str, email: str, error: str | None = None, status_code: int = 200) -> HTMLResponse:
    """Página del enlace del correo: formulario para escribir la contraseña nueva."""
    error_html = f'<div class="aviso">{html.escape(error)}</div>' if error else ""
    campos = f'required minlength="{LARGO_MINIMO_PASSWORD}" maxlength="{LARGO_MAXIMO_PASSWORD}" autocomplete="new-password"'
    respuesta = _documento(
        f"""{_LOGO}
<h1>Crea tu contraseña nueva</h1>
<p>Cuenta: <b style="color:#1F2937">{html.escape(email)}</b></p>
<form method="post" action="restablecer">
{error_html}
<input type="hidden" name="token" value="{html.escape(token)}">
<label for="password">Contraseña nueva</label>
<input type="password" id="password" name="password" placeholder="••••••••" {campos}>
<label for="confirmacion">Repite la contraseña</label>
<input type="password" id="confirmacion" name="confirmacion" placeholder="••••••••" {campos}>
<p class="ayuda">Mínimo {LARGO_MINIMO_PASSWORD} caracteres.</p>
<button type="submit">Guardar contraseña</button>
</form>""",
        status_code,
    )
    # El token va en la URL: que no se guarde en caché ni viaje a otros sitios.
    respuesta.headers["Cache-Control"] = "no-store"
    respuesta.headers["Referrer-Policy"] = "no-referrer"
    return respuesta


@router.get("/restablecer", response_class=HTMLResponse)
def formulario_restablecer(token: str = Query(min_length=20, max_length=200)):
    """Destino del enlace del correo de recuperación."""
    usuario = _usuario_de_token_recuperacion(token)
    if usuario is None:
        return _enlace_vencido()
    return _formulario_restablecer(token, usuario["email"])


@router.post("/restablecer", response_class=HTMLResponse)
def restablecer_password(
    token: str = Form(min_length=20, max_length=200),
    password: str = Form(""),
    confirmacion: str = Form(""),
):
    usuario = _usuario_de_token_recuperacion(token)
    if usuario is None:
        return _enlace_vencido()

    error = None
    if not LARGO_MINIMO_PASSWORD <= len(password) <= LARGO_MAXIMO_PASSWORD:
        error = f"La contraseña debe tener entre {LARGO_MINIMO_PASSWORD} y {LARGO_MAXIMO_PASSWORD} caracteres."
    elif len(password.encode("utf-8")) > LARGO_MAXIMO_PASSWORD:
        error = "La contraseña es demasiado larga."
    elif password != confirmacion:
        error = "Las contraseñas no coinciden."
    if error:
        return _formulario_restablecer(token, usuario["email"], error, status_code=400)

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    with transaccion() as cursor:
        # Se marca el token como usado primero: si dos envíos llegan juntos, solo uno pasa.
        cursor.execute(
            "UPDATE usuario_token SET fecha_uso = NOW() WHERE id_token = %s AND fecha_uso IS NULL",
            (usuario["id_token"],),
        )
        if cursor.rowcount != 1:
            return _enlace_vencido()
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

    return _pagina(
        "¡Contraseña actualizada!",
        "Ya puedes iniciar sesión en RB Alertas con tu contraseña nueva. "
        "Por seguridad, cerramos la sesión en todos tus dispositivos.",
        ok=True,
    )


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
