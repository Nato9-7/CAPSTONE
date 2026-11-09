"""Páginas HTML que abren los enlaces del correo (verificación y recuperación de contraseña).

Usan los mismos colores y formas que las pantallas de la app (inicio de sesión):
tarjeta blanca sobre fondo claro.
"""

import html

from fastapi.responses import HTMLResponse

from app.seguridad import LARGO_MAXIMO_PASSWORD, LARGO_MINIMO_PASSWORD

_ESTILO = """
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
<style>{_ESTILO}</style></head>
<body><div class="tarjeta">{cuerpo}</div></body></html>""",
    )


def pagina(titulo: str, mensaje: str, ok: bool, status_code: int = 200) -> HTMLResponse:
    clase = "" if ok else ' class="error"'
    return _documento(
        f"""{_LOGO}
<h1{clase}>{titulo}</h1>
<p>{mensaje}</p>""",
        status_code,
    )


def enlace_recuperacion_vencido() -> HTMLResponse:
    return pagina(
        "El enlace no es válido o ya venció",
        "Abre RB Alertas, toca «¿Olvidé mi contraseña?» y pide un enlace nuevo. "
        "Cada enlace sirve una sola vez y dura 1 hora.",
        ok=False,
        status_code=400,
    )


def formulario_restablecer(token: str, email: str, error: str | None = None, status_code: int = 200) -> HTMLResponse:
    """Formulario para escribir la contraseña nueva."""
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
