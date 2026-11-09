import hashlib
import logging
import os
from uuid import uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Path as PathParam, UploadFile
import mysql.connector

from app import push
from app.db import consultar, ejecutar, transaccion
from app.rutas.reportes import ADJETIVOS_SURICATA, CARPETA_UPLOADS, _detectar_formato, alias_autor, puede_ver_reporte
from app.seguridad import usuario_actual, usuario_opcional

router = APIRouter()
log = logging.getLogger("rb_alertas.comentarios")

# Igual que las evidencias de los reportes: si la carpeta no se puede escribir,
# los comentarios funcionan, pero sin foto.
CARPETA_FOTOS = CARPETA_UPLOADS / "comentarios"
try:
    CARPETA_FOTOS.mkdir(parents=True, exist_ok=True)
    FOTOS_DISPONIBLES = os.access(CARPETA_FOTOS, os.W_OK)
except OSError:
    FOTOS_DISPONIBLES = False
if not FOTOS_DISPONIBLES:
    log.error("No se puede escribir en %s: los comentarios funcionan, pero sin fotos", CARPETA_FOTOS)

TAMANO_MAXIMO_FOTO = 10 * 1024 * 1024  # 10 MB
FORMATOS_FOTO = (".jpg", ".png", ".webp", ".heic")

# Largo del extracto del comentario que va en el aviso push.
LARGO_EXTRACTO_AVISO = 120


def alias_comentaristas(id_reporte: int, cantidad: int) -> list[str]:
    """Alias de quienes comentan un reporte, en orden de llegada a la conversación.

    Igual que alias_autor, el nombre real nunca sale de la API. El alias depende
    del reporte y del orden en que cada persona comentó por primera vez (no de su
    id): es fijo dentro del reporte, distinto entre reportes y no permite juntar
    los comentarios de alguien en reportes distintos. Nunca repite el alias del autor.
    """
    semilla = int.from_bytes(hashlib.sha256(f"alias-comentario:{id_reporte}".encode()).digest()[:8], "big")
    reservado = alias_autor(id_reporte)
    alias, paso = [], 0
    # Saltos coprimos con 16 adjetivos y 90 números: el par no se repite en 720
    # pasos y los números no salen correlativos (no delatan el orden de llegada).
    while len(alias) < cantidad:
        adjetivo = ADJETIVOS_SURICATA[(semilla + paso * 5) % len(ADJETIVOS_SURICATA)]
        numero = 10 + (semilla // len(ADJETIVOS_SURICATA) + paso * 37) % 90
        paso += 1
        nombre = f"Suricata {adjetivo} {numero}"
        if nombre != reservado:
            alias.append(nombre)
    return alias


def mapa_alias(id_reporte: int, id_autor_reporte: int, filas: list[dict]) -> dict[int, str]:
    """id_usuario -> alias. `filas` son todos los comentarios del reporte (cualquier estado)."""
    orden = []
    for fila in sorted(filas, key=lambda f: f["id_comentario"]):
        if fila["id_usuario"] != id_autor_reporte and fila["id_usuario"] not in orden:
            orden.append(fila["id_usuario"])
    mapa = dict(zip(orden, alias_comentaristas(id_reporte, len(orden))))
    # Si quien reportó comenta, aparece con el mismo alias del reporte.
    mapa[id_autor_reporte] = alias_autor(id_reporte)
    return mapa


def comentarios_de_reporte(id_reporte: int) -> list[dict]:
    """Todos los comentarios del reporte, en cualquier estado, del más antiguo al más nuevo."""
    return consultar(
        """
        SELECT c.id_comentario, c.id_comentario_padre, c.id_usuario, c.contenido,
               c.estado, c.fecha_creacion, i.url_archivo AS imagen
        FROM comentario c
        LEFT JOIN comentario_imagen i ON i.id_comentario = c.id_comentario
        WHERE c.id_reporte = %s
        ORDER BY c.fecha_creacion, c.id_comentario
        """,
        (id_reporte,),
    )


def _reporte(id_reporte: int, usuario: dict | None) -> dict:
    """El reporte, si quien consulta puede verlo (los privados de grupo solo los ven sus miembros)."""
    filas = consultar(
        """
        SELECT r.id_reporte, r.id_usuario, r.estado, r.visibilidad, c.nombre AS categoria,
               (r.estado IN ('PENDIENTE', 'VALIDADO')
                AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())) AS vigente
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.id_reporte = %s
        """,
        (id_reporte,),
    )
    id_usuario = usuario["id_usuario"] if usuario is not None else None
    if not filas or not puede_ver_reporte(id_reporte, filas[0]["id_usuario"], filas[0]["visibilidad"], id_usuario):
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    return filas[0]


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
    reporte = _reporte(id_reporte, usuario)
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


def _guardar_foto(foto: UploadFile):
    """Valida y guarda la foto. Devuelve (ruta en disco, url pública)."""
    if not FOTOS_DISPONIBLES:
        raise HTTPException(
            status_code=503,
            detail="Por ahora no se pueden adjuntar fotos. Envía el comentario sin foto.",
        )
    contenido = foto.file.read(TAMANO_MAXIMO_FOTO + 1)
    if len(contenido) > TAMANO_MAXIMO_FOTO:
        raise HTTPException(status_code=413, detail="La foto no puede superar los 10 MB")
    extension = _detectar_formato(contenido)
    if extension not in FORMATOS_FOTO:
        raise HTTPException(status_code=415, detail="La foto debe ser JPG, PNG, WEBP o HEIC")
    nombre_archivo = f"{uuid4().hex}{extension}"
    ruta = CARPETA_FOTOS / nombre_archivo
    ruta.write_bytes(contenido)
    return ruta, f"/uploads/comentarios/{nombre_archivo}"


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
    reporte = _reporte(id_reporte, usuario)
    if not reporte["vigente"]:
        raise HTTPException(status_code=409, detail="Este reporte ya no admite comentarios")

    contenido = contenido.strip()
    hay_foto = foto is not None and bool(foto.filename)
    if not contenido and not hay_foto:
        raise HTTPException(status_code=422, detail="Escribe un comentario o adjunta una foto")

    id_raiz = None
    respondido = None
    if id_comentario_padre is not None:
        filas = consultar(
            "SELECT id_comentario, id_comentario_padre, id_usuario, estado FROM comentario "
            "WHERE id_comentario = %s AND id_reporte = %s",
            (id_comentario_padre, id_reporte),
        )
        if not filas or filas[0]["estado"] != "PUBLICADO":
            raise HTTPException(status_code=404, detail="El comentario que quieres responder ya no está disponible")
        respondido = filas[0]
        id_raiz = respondido["id_comentario_padre"] or respondido["id_comentario"]

    ruta_foto, url_foto = _guardar_foto(foto) if hay_foto else (None, None)

    try:
        with transaccion() as cursor:
            cursor.execute(
                """
                INSERT INTO comentario (id_reporte, id_usuario, id_comentario_padre, contenido)
                VALUES (%s, %s, %s, %s)
                """,
                (id_reporte, usuario["id_usuario"], id_raiz, contenido),
            )
            id_comentario = cursor.lastrowid
            if url_foto is not None:
                cursor.execute(
                    "INSERT INTO comentario_imagen (id_comentario, url_archivo) VALUES (%s, %s)",
                    (id_comentario, url_foto),
                )
    except mysql.connector.Error as error:
        if ruta_foto is not None:
            ruta_foto.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=error.msg)

    avisos = _avisos_comentario(reporte, usuario["id_usuario"], respondido, contenido)
    avisos = _registrar_avisos(avisos, id_reporte, id_comentario)
    # Igual que en crear_reporte: el push sale después de responder.
    if avisos:
        tareas.add_task(push.enviar_avisos_comentario, id_reporte, avisos)

    return {"id_comentario": id_comentario, "id_comentario_padre": id_raiz, "imagen": url_foto}


def _avisos_comentario(reporte: dict, id_autor: int, respondido: dict | None, contenido: str) -> list[dict]:
    """A quién avisar: a quien recibió la respuesta y al autor del reporte, nunca dos veces ni a uno mismo."""
    try:
        alias = mapa_alias(reporte["id_reporte"], reporte["id_usuario"], comentarios_de_reporte(reporte["id_reporte"]))
    except mysql.connector.Error as error:
        log.error("No se pudieron preparar los avisos del reporte %s: %s", reporte["id_reporte"], error)
        return []
    quien = alias.get(id_autor, "Un vecino")
    extracto = contenido if len(contenido) <= LARGO_EXTRACTO_AVISO else contenido[:LARGO_EXTRACTO_AVISO - 1] + "…"
    extracto = extracto or "Adjuntó una foto"

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


def _registrar_avisos(avisos: list[dict], id_reporte: int, id_comentario: int) -> list[dict]:
    """Guarda cada aviso en notificacion y le agrega su id_notificacion.

    Corre después de confirmar el comentario y fuera de su transacción, como
    _notificar_zonas_seguras: si falla, el comentario ya quedó y solo se pierde el aviso.
    """
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


@router.delete("/{id_reporte}/comentarios/{id_comentario}", status_code=204)
def eliminar_comentario(
    id_reporte: int = PathParam(ge=1),
    id_comentario: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Quien escribió el comentario lo elimina (queda en la BD con estado ELIMINADO)."""
    filas = consultar(
        "SELECT id_usuario, estado FROM comentario WHERE id_comentario = %s AND id_reporte = %s",
        (id_comentario, id_reporte),
    )
    if not filas or filas[0]["estado"] == "ELIMINADO":
        raise HTTPException(status_code=404, detail="El comentario no existe")
    if filas[0]["id_usuario"] != usuario["id_usuario"]:
        raise HTTPException(status_code=403, detail="Solo puedes eliminar tus propios comentarios")
    ejecutar(
        "UPDATE comentario SET estado = 'ELIMINADO' WHERE id_comentario = %s AND id_usuario = %s",
        (id_comentario, usuario["id_usuario"]),
    )
    return None
