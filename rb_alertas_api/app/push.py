import logging
import os

from app.db import consultar, ejecutar

log = logging.getLogger("rb_alertas.push")

# Canales de Android donde caen los avisos. La app los crea al arrancar;
# si cambian aquí, hay que cambiarlos también en la app (push_servicio.dart).
CANAL_ANDROID = "alertas_zona"
CANAL_COMENTARIOS = "comentarios"

# FCM acepta hasta 500 mensajes por llamada a send_each.
MENSAJES_POR_LOTE = 500

# notificacion.estado_envio: ENVIADA si Firebase aceptó el aviso en al menos un
# teléfono del usuario; FALLIDA si lo rechazó en todos o el usuario no tiene
# teléfono registrado. Queda PENDIENTE solo si nunca se intentó (push sin
# configurar). ENTREGADA no se usa: Firebase no confirma la llegada al teléfono.

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
    """Envía por FCM las alertas que generó un reporte: zona segura y grupo.

    Se llama como tarea en segundo plano después de responder: si Firebase
    falla, el reporte y las alertas ya quedaron guardados y la app las ve
    igual en la pestaña Alertas.
    """
    try:
        # LEFT JOIN: quien no tiene teléfono activo también aparece, para marcar su aviso FALLIDA.
        destinos = consultar(
            """
            SELECT n.id_notificacion, n.motivo, n.distancia_metros, n.id_grupo,
                   z.nombre AS zona, g.nombre AS grupo, c.nombre AS categoria,
                   d.id_dispositivo, d.token_push
            FROM notificacion n
            LEFT JOIN usuario_dispositivo d ON d.id_usuario = n.id_usuario AND d.activo = 1
            JOIN reporte r ON r.id_reporte = n.id_reporte
            JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
            LEFT JOIN zona_segura z ON z.id_zona_segura = n.id_zona_segura
            LEFT JOIN grupo g ON g.id_grupo = n.id_grupo
            WHERE n.id_reporte = %s AND n.motivo IN ('ZONA_SEGURA', 'GRUPO')
            """,
            (id_reporte,),
        )
    except Exception as error:
        log.error("No se pudieron leer los destinos push del reporte %s: %s", id_reporte, error)
        return

    if not destinos:
        return
    intentadas = {destino["id_notificacion"] for destino in destinos}
    destinos = [destino for destino in destinos if destino["token_push"]]

    if not push_configurado():
        for destino in destinos:
            titulo, cuerpo = _textos_alerta(destino)
            print(f"[push simulado] Dispositivo {destino['id_dispositivo']} | {titulo}: {cuerpo}", flush=True)
        return

    try:
        from firebase_admin import messaging

        app = _firebase()
    except Exception as error:
        log.error("Firebase no está disponible, no se envían avisos push: %s", error)
        _marcar_envio(set(), intentadas)
        return

    mensajes = []
    for destino in destinos:
        titulo, cuerpo = _textos_alerta(destino)
        # La app usa estos datos al tocar el aviso: ZONA_SEGURA abre la pestaña
        # Alertas y GRUPO abre el reporte.
        datos = {
            "tipo": destino["motivo"],
            "id_notificacion": str(destino["id_notificacion"]),
            "id_reporte": str(id_reporte),
        }
        if destino["id_grupo"] is not None:
            datos["id_grupo"] = str(destino["id_grupo"])
        mensajes.append((
            destino["id_notificacion"],
            messaging.Message(
                # token_push guarda el FID del teléfono (la app lo recibe por onRegistered).
                fid=destino["token_push"],
                notification=messaging.Notification(title=titulo, body=cuerpo),
                data=datos,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(channel_id=CANAL_ANDROID),
                ),
            ),
        ))

    _marcar_envio(_enviar_mensajes(messaging, app, mensajes, id_reporte), intentadas)


def _textos_alerta(destino: dict) -> tuple[str, str]:
    """Título y cuerpo del aviso según su motivo."""
    if destino["motivo"] == "GRUPO":
        grupo = destino["grupo"] or "tu grupo"
        return f"Nuevo reporte en {grupo}", f"{destino['categoria']}: toca para ver el reporte."
    zona = destino["zona"] or "tu zona segura"
    return (
        f"Alerta cerca de {zona}",
        f"Nuevo reporte: {destino['categoria']}, {_distancia_legible(destino['distancia_metros'])} de tu zona.",
    )


def enviar_avisos_comentario(id_reporte: int, avisos: list[dict]) -> None:
    """Avisa por FCM de un comentario nuevo: al autor del reporte y a quien recibió una respuesta.

    Cada aviso trae id_usuario, id_notificacion (su fila en notificacion, motivo
    COMENTARIO o RESPUESTA), titulo y cuerpo. Si Firebase falla, el comentario y
    el aviso ya quedaron guardados y se ven igual al abrir el reporte.
    """
    if not avisos:
        return
    intentadas = {aviso["id_notificacion"] for aviso in avisos}
    por_usuario = {aviso["id_usuario"]: aviso for aviso in avisos}
    marcas = ", ".join(["%s"] * len(por_usuario))
    try:
        dispositivos = consultar(
            f"""
            SELECT d.id_usuario, d.id_dispositivo, d.token_push
            FROM usuario_dispositivo d
            JOIN usuario u ON u.id_usuario = d.id_usuario
            WHERE d.activo = 1 AND u.estado = 'ACTIVO' AND d.id_usuario IN ({marcas})
            """,
            tuple(por_usuario),
        )
    except Exception as error:
        log.error("No se pudieron leer los destinos push del comentario (reporte %s): %s", id_reporte, error)
        return

    if not push_configurado():
        for dispositivo in dispositivos:
            aviso = por_usuario[dispositivo["id_usuario"]]
            print(
                f"[push simulado] Dispositivo {dispositivo['id_dispositivo']} | "
                f"{aviso['titulo']}: {aviso['cuerpo']}",
                flush=True,
            )
        return

    try:
        from firebase_admin import messaging

        app = _firebase()
    except Exception as error:
        log.error("Firebase no está disponible, no se envían avisos push: %s", error)
        _marcar_envio(set(), intentadas)
        return

    mensajes = []
    for dispositivo in dispositivos:
        aviso = por_usuario[dispositivo["id_usuario"]]
        mensajes.append((
            aviso["id_notificacion"],
            messaging.Message(
                fid=dispositivo["token_push"],
                notification=messaging.Notification(title=aviso["titulo"], body=aviso["cuerpo"]),
                # La app usa estos datos para abrir el reporte al tocar el aviso.
                data={
                    "tipo": "COMENTARIO",
                    "id_notificacion": str(aviso["id_notificacion"]),
                    "id_reporte": str(id_reporte),
                },
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(channel_id=CANAL_COMENTARIOS),
                ),
            ),
        ))
    # Quien no tiene teléfono activo no recibe mensaje y su aviso queda FALLIDA.
    _marcar_envio(_enviar_mensajes(messaging, app, mensajes, id_reporte), intentadas)


def _enviar_mensajes(messaging, app, mensajes: list[tuple], id_reporte: int) -> set:
    """Envía en lotes los pares (id_notificacion, mensaje) y desactiva los tokens
    que Firebase ya no reconoce. Devuelve los id_notificacion que Firebase aceptó
    en al menos un teléfono."""
    enviadas = set()
    tokens_vencidos = []
    for inicio in range(0, len(mensajes), MENSAJES_POR_LOTE):
        lote = mensajes[inicio:inicio + MENSAJES_POR_LOTE]
        try:
            respuesta = messaging.send_each([mensaje for _, mensaje in lote], app=app)
        except Exception as error:
            log.error("Falló el envío push del reporte %s: %s", id_reporte, error)
            continue

        for (id_notificacion, mensaje), resultado in zip(lote, respuesta.responses):
            if resultado.success:
                enviadas.add(id_notificacion)
                continue
            # El token ya no existe (app desinstalada) o es de otro proyecto de Firebase.
            if isinstance(resultado.exception, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
                tokens_vencidos.append(mensaje.fid)
            else:
                log.warning("Aviso push rechazado (reporte %s): %s", id_reporte, resultado.exception)

    if tokens_vencidos:
        _desactivar_tokens(tokens_vencidos)
    return enviadas


def _marcar_envio(enviadas: set, intentadas: set) -> None:
    """Deja en notificacion.estado_envio el resultado del intento (ver nota arriba)."""
    for estado, ids in (("ENVIADA", enviadas), ("FALLIDA", intentadas - enviadas)):
        if not ids:
            continue
        marcas = ", ".join(["%s"] * len(ids))
        try:
            ejecutar(
                f"UPDATE notificacion SET estado_envio = %s WHERE id_notificacion IN ({marcas})",
                (estado, *ids),
            )
        except Exception as error:
            # Solo se pierde el registro del resultado; el aviso ya salió (o no).
            log.error("No se pudo marcar %s avisos como %s: %s", len(ids), estado, error)


def _desactivar_tokens(tokens: list[str]) -> None:
    marcas = ", ".join(["%s"] * len(tokens))
    try:
        ejecutar(
            f"UPDATE usuario_dispositivo SET activo = 0 WHERE token_push IN ({marcas})",
            tuple(tokens),
        )
    except Exception as error:
        log.error("No se pudieron desactivar %s tokens vencidos: %s", len(tokens), error)
