"""Conversación de un reporte: comentarios, respuestas de un nivel y fotos."""

import logging

import mysql.connector
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Path as PathParam, UploadFile

from app.comun.alias import mapa_alias
from app.comun.archivos import FORMATOS_FOTO, CarpetaAdjuntos, borrar_archivos, hay_archivo
from app.comun.sql import error_bd
from app.db import consultar, ejecutar, transaccion
from app.seguridad import usuario_actual, usuario_opcional
from app.servicios import avisos, push
from app.servicios.comentarios import comentarios_de_reporte, marcar_eliminado
from app.servicios.reportes import reporte_visible

router = APIRouter()
log = logging.getLogger("rb_alertas.comentarios")

FOTOS = CarpetaAdjuntos(
    subcarpeta="comentarios",
    tamano_maximo=10 * 1024 * 1024,
    formatos=FORMATOS_FOTO,
    mensaje_no_disponible="Por ahora no se pueden adjuntar fotos. Envía el comentario sin foto.",
    mensaje_tamano="La foto no puede superar los 10 MB",
    mensaje_formato="La foto debe ser JPG, PNG, WEBP o HEIC",
)


def _comentario_json(fila: dict, alias: dict[int, str], id_autor_reporte: int, id_usuario_actual) -> dict:
    publicado = fila["estado"] == "PUBLICADO"
    # De un comentario eliminado u oculto solo queda el marcador (sin texto, foto ni alias).
    return {
        "id_comentario": fila["id_comentario"],
        "id_comentario_padre": fila["id_comentario_padre"],
        "estado": fila["estado"],
        "autor": alias.get(fila["id_usuario"]) if publicado else None,
        "es_autor_reporte": publicado and fila["id_usuario"] == id_autor_reporte,
        "es_mio": publicado and fila["id_usuario"] == id_usuario_actual,
        "contenido": fila["contenido"] if publicado else None,
        "imagen": fila["imagen"] if publicado else None,
        "fecha_creacion": fila["fecha_creacion"],
    }


def _marcar_avisos_leidos(id_usuario: int, id_reporte: int) -> None:
    try:
        ejecutar(
            """
            UPDATE notificacion SET fecha_lectura = NOW()
            WHERE id_usuario = %s AND id_reporte = %s
              AND motivo IN ('COMENTARIO', 'RESPUESTA') AND fecha_lectura IS NULL
            """,
            (id_usuario, id_reporte),
        )
    except mysql.connector.Error as error:
        # Solo queda sin marcar: la conversación se muestra igual.
        log.error("No se pudieron marcar leídos los avisos del reporte %s: %s", id_reporte, error)


@router.get("/{id_reporte}/comentarios")
def listar_comentarios(
    id_reporte: int = PathParam(ge=1),
    usuario: dict | None = Depends(usuario_opcional),
):
    """Conversación del reporte: comentarios raíz con sus respuestas (un nivel), del más antiguo al más nuevo.

    Un comentario raíz eliminado u oculto sigue apareciendo como marcador si tiene
    respuestas visibles, para no dejarlas sin contexto; si no tiene, desaparece.

    Con sesión, los avisos de comentarios de este reporte quedan leídos: quien
    abre la conversación ya los vio.
    """
    reporte = reporte_visible(id_reporte, usuario)
    filas = comentarios_de_reporte(id_reporte)
    alias = mapa_alias(id_reporte, reporte["id_usuario"], filas)
    id_actual = usuario["id_usuario"] if usuario else None
    if id_actual is not None:
        _marcar_avisos_leidos(id_actual, id_reporte)

    raices, por_id = [], {}
    for fila in filas:
        if fila["id_comentario_padre"] is None:
            item = {**_comentario_json(fila, alias, reporte["id_usuario"], id_actual), "respuestas": []}
            raices.append(item)
            por_id[fila["id_comentario"]] = item
    for fila in filas:
        raiz = por_id.get(fila["id_comentario_padre"])
        if raiz is not None and fila["estado"] == "PUBLICADO":
            raiz["respuestas"].append(_comentario_json(fila, alias, reporte["id_usuario"], id_actual))

    visibles = [r for r in raices if r["estado"] == "PUBLICADO" or r["respuestas"]]
    total = sum((r["estado"] == "PUBLICADO") + len(r["respuestas"]) for r in visibles)
    return {
        "total": total,
        "puede_comentar": bool(reporte["vigente"]),
        "comentarios": visibles,
    }


def _comentario_respondido(id_comentario_padre: int, id_reporte: int) -> dict:
    filas = consultar(
        "SELECT id_comentario, id_comentario_padre, id_usuario, estado FROM comentario "
        "WHERE id_comentario = %s AND id_reporte = %s",
        (id_comentario_padre, id_reporte),
    )
    if not filas or filas[0]["estado"] != "PUBLICADO":
        raise HTTPException(status_code=404, detail="El comentario que quieres responder ya no está disponible")
    return filas[0]


def _guardar_comentario(id_reporte: int, id_usuario: int, id_raiz: int | None, contenido: str, url_foto: str | None) -> int:
    with transaccion() as cursor:
        cursor.execute(
            """
            INSERT INTO comentario (id_reporte, id_usuario, id_comentario_padre, contenido)
            VALUES (%s, %s, %s, %s)
            """,
            (id_reporte, id_usuario, id_raiz, contenido),
        )
        id_comentario = cursor.lastrowid
        if url_foto is not None:
            cursor.execute(
                "INSERT INTO comentario_imagen (id_comentario, url_archivo) VALUES (%s, %s)",
                (id_comentario, url_foto),
            )
    return id_comentario


@router.post("/{id_reporte}/comentarios", status_code=201)
def crear_comentario(
    tareas: BackgroundTasks,
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
    contenido: str = Form("", max_length=500),
    id_comentario_padre: int | None = Form(None, ge=1),
    foto: UploadFile | None = File(None),
):
    """Publica un comentario o una respuesta. Lleva texto, una foto o ambos.

    Responder a una respuesta cuelga del mismo comentario raíz (un solo nivel),
    pero el aviso push le llega a quien escribió la respuesta.
    """
    reporte = reporte_visible(id_reporte, usuario)
    if not reporte["vigente"]:
        raise HTTPException(status_code=409, detail="Este reporte ya no admite comentarios")

    contenido = contenido.strip()
    con_foto = hay_archivo(foto)
    if not contenido and not con_foto:
        raise HTTPException(status_code=422, detail="Escribe un comentario o adjunta una foto")

    respondido = _comentario_respondido(id_comentario_padre, id_reporte) if id_comentario_padre is not None else None
    id_raiz = (respondido["id_comentario_padre"] or respondido["id_comentario"]) if respondido else None

    ruta_foto, url_foto = FOTOS.guardar(foto) if con_foto else (None, None)
    try:
        id_comentario = _guardar_comentario(id_reporte, usuario["id_usuario"], id_raiz, contenido, url_foto)
    except Exception as error:
        if ruta_foto is not None:
            ruta_foto.unlink(missing_ok=True)
        if isinstance(error, mysql.connector.Error):
            raise error_bd(error, "No se pudo publicar el comentario. Inténtalo otra vez") from error
        raise

    lista = avisos.avisos_comentario(reporte, usuario["id_usuario"], respondido, contenido)
    lista = avisos.registrar_avisos_comentario(lista, id_reporte, id_comentario)
    # Igual que en crear_reporte: el push sale después de responder.
    if lista:
        tareas.add_task(push.enviar_avisos_comentario, id_reporte, lista)

    return {"id_comentario": id_comentario, "id_comentario_padre": id_raiz, "imagen": url_foto}


@router.delete("/{id_reporte}/comentarios/{id_comentario}", status_code=204)
def eliminar_comentario(
    id_reporte: int = PathParam(ge=1),
    id_comentario: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Quien escribió el comentario lo elimina: queda en la BD como ELIMINADO y su foto se borra."""
    with transaccion() as cursor:
        cursor.execute(
            "SELECT id_usuario, estado FROM comentario WHERE id_comentario = %s AND id_reporte = %s FOR UPDATE",
            (id_comentario, id_reporte),
        )
        fila = cursor.fetchone()
        if fila is None or fila["estado"] == "ELIMINADO":
            raise HTTPException(status_code=404, detail="El comentario no existe")
        if fila["id_usuario"] != usuario["id_usuario"]:
            raise HTTPException(status_code=403, detail="Solo puedes eliminar tus propios comentarios")
        archivos = marcar_eliminado(cursor, id_comentario)
    borrar_archivos(archivos)
    return None
