import logging
import os

from app.db import consultar, ejecutar

log = logging.getLogger("rb_alertas.push")

# Canal de Android donde caen las alertas. La app lo crea al arrancar con
# importancia alta; si cambia aquí, hay que cambiarlo también en la app.
CANAL_ANDROID = "alertas_zona"

# FCM acepta hasta 500 mensajes por llamada a send_each.
MENSAJES_POR_LOTE = 500

_app_firebase = None


def push_configurado() -> bool:
    return bool(os.getenv("FIREBASE_CREDENCIALES"))


def _firebase():
    """Inicializa Firebase una sola vez, con la cuenta de servicio de FIREBASE_CREDENCIALES.

    Se importa aquí y no arriba para que la API arranque aunque falte la
    librería o el archivo: en ese caso solo se pierden los avisos push.
    """
    global _app_firebase
    if _app_firebase is None:
        import firebase_admin
        from firebase_admin import credentials

        _app_firebase = firebase_admin.initialize_app(
            credentials.Certificate(os.getenv("FIREBASE_CREDENCIALES"))
        )
    return _app_firebase


def _distancia_legible(metros) -> str:
    if metros is None:
        return "dentro de tu zona"
    metros = int(metros)
    if metros >= 1000:
        return f"a {metros / 1000:.1f} km".replace(".", ",")
    return f"a {metros} m"


def enviar_alertas_de_reporte(id_reporte: int) -> None:
    """Envía por FCM las alertas de zona segura que generó un reporte.

    Se llama como tarea en segundo plano después de responder: si Firebase
    falla, el reporte y las alertas ya quedaron guardados y la app las ve
    igual en la pestaña Alertas.
    """
    try:
        destinos = consultar(
            """
            SELECT n.id_notificacion, n.distancia_metros,
                   z.nombre AS zona, c.nombre AS categoria,
                   d.id_dispositivo, d.token_push
            FROM notificacion n
            JOIN usuario_dispositivo d ON d.id_usuario = n.id_usuario AND d.activo = 1
            JOIN reporte r ON r.id_reporte = n.id_reporte
            JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
            LEFT JOIN zona_segura z ON z.id_zona_segura = n.id_zona_segura
            WHERE n.id_reporte = %s AND n.motivo = 'ZONA_SEGURA'
            """,
            (id_reporte,),
        )
    except Exception as error:
        log.error("No se pudieron leer los destinos push del reporte %s: %s", id_reporte, error)
        return

    if not destinos:
        return

    if not push_configurado():
        for destino in destinos:
            print(
                f"[push simulado] Dispositivo {destino['id_dispositivo']} | "
                f"Alerta cerca de {destino['zona'] or 'tu zona segura'}: {destino['categoria']}",
                flush=True,
            )
        return

    try:
        from firebase_admin import messaging

        app = _firebase()
    except Exception as error:
        log.error("Firebase no está disponible, no se envían avisos push: %s", error)
        return

    mensajes = []
    for destino in destinos:
        zona = destino["zona"] or "tu zona segura"
        mensajes.append(
            messaging.Message(
                # token_push guarda el FID del teléfono (la app lo recibe por onRegistered).
                fid=destino["token_push"],
                notification=messaging.Notification(
                    title=f"Alerta cerca de {zona}",
                    body=f"Nuevo reporte: {destino['categoria']}, "
                    f"{_distancia_legible(destino['distancia_metros'])} de tu zona.",
                ),
                # La app usa estos datos para abrir la pestaña Alertas al tocar el aviso.
                data={
                    "tipo": "ZONA_SEGURA",
                    "id_notificacion": str(destino["id_notificacion"]),
                    "id_reporte": str(id_reporte),
                },
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(channel_id=CANAL_ANDROID),
                ),
            )
        )

    tokens_vencidos = []
    for inicio in range(0, len(mensajes), MENSAJES_POR_LOTE):
        lote = mensajes[inicio:inicio + MENSAJES_POR_LOTE]
        try:
            respuesta = messaging.send_each(lote, app=app)
        except Exception as error:
            log.error("Falló el envío push del reporte %s: %s", id_reporte, error)
            continue

        for mensaje, resultado in zip(lote, respuesta.responses):
            if resultado.success:
                continue
            # El token ya no existe (app desinstalada) o es de otro proyecto de Firebase.
            if isinstance(resultado.exception, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
                tokens_vencidos.append(mensaje.fid)
            else:
                log.warning("Aviso push rechazado (reporte %s): %s", id_reporte, resultado.exception)

    if tokens_vencidos:
        _desactivar_tokens(tokens_vencidos)


def _desactivar_tokens(tokens: list[str]) -> None:
    marcas = ", ".join(["%s"] * len(tokens))
    try:
        ejecutar(
            f"UPDATE usuario_dispositivo SET activo = 0 WHERE token_push IN ({marcas})",
            tuple(tokens),
        )
    except Exception as error:
        log.error("No se pudieron desactivar %s tokens vencidos: %s", len(tokens), error)
