import html
import logging
import os
import smtplib
import ssl
from datetime import datetime, timedelta
from email.message import EmailMessage
from email.utils import formataddr
from zoneinfo import ZoneInfo

log = logging.getLogger("rb_alertas.correo")

ZONA_CHILE = ZoneInfo("America/Santiago")
HORAS_VIGENCIA_VERIFICACION = 24


def correo_configurado() -> bool:
    return bool(os.getenv("SMTP_HOST"))


def enviar_correo(destinatario: str, asunto: str, texto: str, html_cuerpo: str | None = None) -> None:
    """Envía un correo por SMTP. Sirve con Microsoft 365/Outlook (smtp.office365.com:587),
    Gmail (smtp.gmail.com:587), Brevo, SendGrid, etc., según las variables SMTP_* del .env.

    Si SMTP_HOST no está definido, el correo solo se imprime en los logs de la API
    ("modo simulado"), para poder probar sin una cuenta de correo configurada.
    Se llama como tarea en segundo plano: un error de envío no rompe el registro.
    """
    if not correo_configurado():
        print(f"[correo simulado] Para: {destinatario} | Asunto: {asunto}\n{texto}", flush=True)
        return

    host = os.getenv("SMTP_HOST")
    puerto = int(os.getenv("SMTP_PUERTO", "587"))
    usuario = os.getenv("SMTP_USUARIO")
    clave = os.getenv("SMTP_CLAVE")
    remitente = os.getenv("CORREO_REMITENTE") or usuario

    mensaje = EmailMessage()
    mensaje["From"] = formataddr((os.getenv("CORREO_NOMBRE_REMITENTE", "Notificaciones RB Alertas"), remitente))
    mensaje["To"] = destinatario
    mensaje["Subject"] = asunto
    mensaje.set_content(texto)
    if html_cuerpo:
        mensaje.add_alternative(html_cuerpo, subtype="html")

    contexto = ssl.create_default_context()
    try:
        if puerto == 465:
            with smtplib.SMTP_SSL(host, puerto, context=contexto, timeout=20) as smtp:
                if usuario:
                    smtp.login(usuario, clave)
                smtp.send_message(mensaje)
        else:
            with smtplib.SMTP(host, puerto, timeout=20) as smtp:
                smtp.starttls(context=contexto)
                if usuario:
                    smtp.login(usuario, clave)
                smtp.send_message(mensaje)
    except (smtplib.SMTPException, OSError):
        log.exception("No se pudo enviar el correo a %s", destinatario)


def _plantilla(titulo: str, subtitulo: str, saludo: str, intro: str, filas: list[tuple[str, str]],
               boton: tuple[str, str] | None, nota: str, generado: str) -> str:
    """Correo tipo tarjeta: encabezado con color, tabla de datos y pie automático.

    Hecho con tablas y estilos en línea para que se vea bien en Outlook y Gmail.
    """
    filas_html = "".join(
        f"""<tr>
          <td style="padding:9px 10px;border-bottom:1px solid #E5E7EB;font-weight:bold;color:#111827;width:38%">{html.escape(etiqueta)}</td>
          <td style="padding:9px 10px;border-bottom:1px solid #E5E7EB;color:#1F2937">{html.escape(valor)}</td>
        </tr>"""
        for etiqueta, valor in filas
    )
    boton_html = ""
    if boton:
        texto_boton, enlace = boton
        boton_html = f"""<table role="presentation" cellpadding="0" cellspacing="0" style="margin:22px 0 6px">
          <tr><td style="background:#0056D2;border-radius:8px">
            <a href="{html.escape(enlace)}" style="display:inline-block;padding:12px 26px;color:#FFFFFF;font-weight:bold;text-decoration:none;font-size:15px">{html.escape(texto_boton)}</a>
          </td></tr>
        </table>
        <p style="font-size:12px;color:#6B7280;margin:10px 0 0">Si el botón no funciona, copia este enlace en tu navegador:<br>
          <a href="{html.escape(enlace)}" style="color:#0056D2;word-break:break-all">{html.escape(enlace)}</a></p>"""

    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F1F3F8">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1F3F8;padding:28px 12px">
  <tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="max-width:570px;background:#FFFFFF;border-radius:8px;overflow:hidden;font-family:'Segoe UI',Arial,sans-serif">
      <tr><td style="background:#0B3D91;padding:20px 24px">
        <div style="color:#FFFFFF;font-size:19px;font-weight:bold">{html.escape(titulo)}</div>
        <div style="color:#DCE6F7;font-size:13px;margin-top:6px">{html.escape(subtitulo)}</div>
      </td></tr>
      <tr><td style="padding:22px 24px 26px;font-size:14px;color:#111827;line-height:1.5">
        <p style="margin:0 0 12px">{html.escape(saludo)}</p>
        <p style="margin:0 0 14px">{html.escape(intro)}</p>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:13px;border-collapse:collapse">
          {filas_html}
        </table>
        {boton_html}
        <p style="font-size:12.5px;color:#4B5563;margin:18px 0 0">{html.escape(nota)}</p>
        <p style="font-size:11.5px;color:#6B7280;margin:14px 0 0">{html.escape(generado)}</p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>"""


def correo_verificacion(nombre: str, email: str, token: str) -> tuple[str, str, str]:
    """Asunto, texto plano y HTML del correo para verificar la cuenta."""
    url_api = os.getenv("URL_PUBLICA_API", "http://129.213.86.163:8000").rstrip("/")
    enlace = f"{url_api}/api/usuarios/verificar?token={token}"
    ahora = datetime.now(ZONA_CHILE)
    vence = ahora + timedelta(hours=HORAS_VIGENCIA_VERIFICACION)
    fecha = ahora.strftime("%d-%m-%Y")
    fecha_hora = ahora.strftime("%d-%m-%Y, %H:%M")
    vence_texto = vence.strftime("%d-%m-%Y, %H:%M")

    asunto = f"Verifica tu correo · RB Alertas · {fecha}"
    intro = f"Se creó una cuenta en RB Alertas con este correo el {fecha_hora}. Para activarla, confirma que el correo es tuyo."
    nota = ("Si no creaste esta cuenta, ignora este mensaje: la cuenta no se activará. "
            "Nunca te pediremos tu contraseña por correo.")
    generado = f"Generado automáticamente por RB Alertas el {fecha_hora} (hora de Chile)."

    html_cuerpo = _plantilla(
        titulo="Verifica tu correo",
        subtitulo=f"RB Alertas · {fecha}",
        saludo=f"Estimado(a) {nombre}:",
        intro=intro,
        filas=[("Nombre", nombre), ("Correo", email), ("Enlace válido hasta", f"{vence_texto} (hora de Chile)")],
        boton=("Verificar mi correo", enlace),
        nota=nota,
        generado=generado,
    )
    texto = (
        f"Estimado(a) {nombre}:\n\n{intro}\n\n"
        f"Abre este enlace para verificar tu correo (válido hasta el {vence_texto}, hora de Chile):\n{enlace}\n\n"
        f"{nota}\n\n{generado}\n"
    )
    return asunto, texto, html_cuerpo
