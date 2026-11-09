"""Avisos (tabla notificacion) que generan los reportes y los comentarios.

Todas estas funciones corren DESPUÉS de confirmar el reporte o el comentario y a
propósito fuera de su transacción: si fallan, lo publicado ya quedó guardado y
solo se pierde el aviso. El envío push lo hace app.servicios.push.
"""

import logging

import mysql.connector

from app.comun.alias import mapa_alias
from app.comun.geo import PUNTO_SQL
from app.comun.sql import marcas
from app.db import transaccion
from app.servicios.comentarios import comentarios_de_reporte
from app.servicios.reportes import puede_ver_reporte

log = logging.getLogger("rb_alertas.avisos")

# Largo del extracto del comentario que va en el aviso push.
LARGO_EXTRACTO_AVISO = 120


def notificar_grupos(id_reporte: int, ids_grupos: list[int], id_autor: int) -> int:
    """Avisa a los miembros de los grupos donde se compartió el reporte.

    Quien está en varios de esos grupos recibe un solo aviso. Devuelve cuántos avisos se crearon.
    """
    if not ids_grupos:
        return 0
    try:
        with transaccion() as cursor:
            cursor.execute(
                f"""
                INSERT INTO notificacion (id_usuario, id_reporte, id_grupo, motivo)
                SELECT id_usuario, %s, id_grupo, 'GRUPO'
                FROM (
                    SELECT m.id_usuario, m.id_grupo,
                           ROW_NUMBER() OVER (PARTITION BY m.id_usuario ORDER BY m.id_grupo) AS orden
                    FROM grupo_miembro m
                    JOIN usuario u ON u.id_usuario = m.id_usuario
                    WHERE m.id_grupo IN ({marcas(len(ids_grupos))})
                      AND m.id_usuario <> %s
                      AND u.estado = 'ACTIVO'
                ) AS candidatos
                WHERE orden = 1
                """,
                (id_reporte, *ids_grupos, id_autor),
            )
            return cursor.rowcount or 0
    except mysql.connector.Error as error:
        log.error("No se pudieron generar los avisos de grupo del reporte %s: %s", id_reporte, error)
        return 0


def notificar_zonas_seguras(
    id_reporte: int, punto_wkt: str, id_autor: int, mismo_incidente: list[int] | None = None
) -> int:
    """Avisa a los vecinos cuyo reporte cayó dentro de alguna de sus zonas seguras.

    De cada usuario se toma su zona más cercana al incidente, para que no reciba
    dos alertas del mismo hecho cuando sus zonas se superponen. Tampoco se avisa a
    quien ya recibió la alerta por otro reporte del mismo incidente (`mismo_incidente`).
    """
    mismo_incidente = mismo_incidente or []
    filtro_incidente = ""
    if mismo_incidente:
        filtro_incidente = f"""
                      AND NOT EXISTS (
                          SELECT 1 FROM notificacion n2
                          WHERE n2.id_reporte IN ({marcas(len(mismo_incidente))}) AND n2.id_usuario = z.id_usuario
                      )"""
    try:
        with transaccion() as cursor:
            cursor.execute(
                f"""
                INSERT INTO notificacion (
                    id_usuario, id_reporte, id_zona_segura, motivo, distancia_metros
                )
                SELECT id_usuario, %s, id_zona_segura, 'ZONA_SEGURA', distancia_metros
                FROM (
                    SELECT z.id_usuario,
                           z.id_zona_segura,
                           ROUND(ST_Distance_Sphere(z.centro, {PUNTO_SQL})) AS distancia_metros,
                           ROW_NUMBER() OVER (
                               PARTITION BY z.id_usuario
                               ORDER BY ST_Distance_Sphere(z.centro, {PUNTO_SQL})
                           ) AS orden
                    FROM zona_segura z
                    JOIN usuario u ON u.id_usuario = z.id_usuario
                    LEFT JOIN usuario_preferencia p ON p.id_usuario = z.id_usuario
                    WHERE z.activa = 1
                      AND z.notif_activa = 1
                      AND z.id_usuario <> %s
                      AND u.estado = 'ACTIVO'
                      AND COALESCE(p.notif_zona_activa, 1) = 1
                      AND ST_Distance_Sphere(z.centro, {PUNTO_SQL}) <= z.radio_metros
                      AND NOT EXISTS (
                          SELECT 1 FROM notificacion n
                          WHERE n.id_reporte = %s AND n.id_usuario = z.id_usuario
                      ){filtro_incidente}
                ) AS candidatas
                WHERE orden = 1
                """,
                (id_reporte, punto_wkt, punto_wkt, id_autor, punto_wkt, id_reporte, *mismo_incidente),
            )
            return cursor.rowcount or 0
    except mysql.connector.Error as error:
        log.error("No se pudieron generar las alertas de zona segura del reporte %s: %s", id_reporte, error)
        return 0


def _extracto(contenido: str) -> str:
    if not contenido:
        return "Adjuntó una foto"
    if len(contenido) <= LARGO_EXTRACTO_AVISO:
        return contenido
    return contenido[:LARGO_EXTRACTO_AVISO - 1] + "…"


def avisos_comentario(reporte: dict, id_autor: int, respondido: dict | None, contenido: str) -> list[dict]:
    """A quién avisar de un comentario: a quien recibió la respuesta y al autor del reporte,
    nunca dos veces ni a uno mismo."""
    try:
        alias = mapa_alias(reporte["id_reporte"], reporte["id_usuario"], comentarios_de_reporte(reporte["id_reporte"]))
    except mysql.connector.Error as error:
        log.error("No se pudieron preparar los avisos del reporte %s: %s", reporte["id_reporte"], error)
        return []
    quien = alias.get(id_autor, "Un vecino")
    extracto = _extracto(contenido)

    avisos = []
    # En un reporte privado, quien comentó y después salió del grupo ya no recibe avisos.
    if respondido is not None and respondido["id_usuario"] != id_autor and puede_ver_reporte(
        reporte["id_reporte"], reporte["id_usuario"], reporte["visibilidad"], respondido["id_usuario"]
    ):
        avisos.append({
            "id_usuario": respondido["id_usuario"],
            "motivo": "RESPUESTA",
            "titulo": f"{quien} respondió tu comentario",
            "cuerpo": extracto,
        })
    avisados = {aviso["id_usuario"] for aviso in avisos}
    if reporte["id_usuario"] != id_autor and reporte["id_usuario"] not in avisados:
        avisos.append({
            "id_usuario": reporte["id_usuario"],
            "motivo": "COMENTARIO",
            "titulo": f"Nuevo comentario en tu reporte de {reporte['categoria'].lower()}",
            "cuerpo": f"{quien}: {extracto}",
        })
    return avisos


def registrar_avisos_comentario(avisos: list[dict], id_reporte: int, id_comentario: int) -> list[dict]:
    """Guarda cada aviso en notificacion y le agrega su id_notificacion."""
    if not avisos:
        return []
    try:
        with transaccion() as cursor:
            for aviso in avisos:
                cursor.execute(
                    """
                    INSERT INTO notificacion (id_usuario, id_reporte, id_comentario, motivo)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (aviso["id_usuario"], id_reporte, id_comentario, aviso["motivo"]),
                )
                aviso["id_notificacion"] = cursor.lastrowid
        return avisos
    except mysql.connector.Error as error:
        log.error("No se pudieron guardar los avisos del comentario %s: %s", id_comentario, error)
        return []
