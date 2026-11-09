"""Creación de reportes con evidencia opcional y avisos a zonas seguras y grupos."""

import mysql.connector
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile

from app.comun.archivos import FORMATOS_FOTO, FORMATOS_VIDEO, CarpetaAdjuntos, hay_archivo
from app.comun.geo import PUNTO_SQL, punto_wkt
from app.comun.sql import error_bd, marcas
from app.db import consultar, transaccion
from app.seguridad import usuario_actual
from app.servicios import avisos, push
from app.servicios.reportes import reportes_del_incidente
from app.servicios.ubicacion import resolver_comuna, resolver_localidad

router = APIRouter()

EVIDENCIAS = CarpetaAdjuntos(
    subcarpeta="reportes",
    tamano_maximo=20 * 1024 * 1024,
    formatos=FORMATOS_FOTO + FORMATOS_VIDEO,
    mensaje_no_disponible="Por ahora no se pueden adjuntar fotos o videos. Envía el reporte sin evidencia.",
    mensaje_tamano="La evidencia no puede superar los 20 MB",
    mensaje_formato="La evidencia debe ser una foto (JPG, PNG, WEBP, HEIC) o un video (MP4, MOV, WEBM)",
)


def _horas_vigencia(id_categoria: int) -> int:
    categorias = consultar(
        "SELECT horas_vigencia FROM categoria_incidente WHERE id_categoria = %s AND activa = 1",
        (id_categoria,),
    )
    if not categorias:
        raise HTTPException(status_code=422, detail="Categoría no válida")
    return categorias[0]["horas_vigencia"]


def _leer_ids_grupos(texto: str) -> list[int]:
    try:
        ids = {int(parte) for parte in texto.split(",") if parte.strip()}
    except ValueError:
        raise HTTPException(status_code=422, detail="Los grupos elegidos no son válidos")
    if any(id_grupo < 1 for id_grupo in ids):
        raise HTTPException(status_code=422, detail="Los grupos elegidos no son válidos")
    return sorted(ids)


def _validar_grupos_del_reporte(ids_grupos: list[int], id_usuario: int, punto: str) -> None:
    """Cada grupo elegido debe estar activo, tener al autor como miembro y contener el punto del incidente."""
    validos = consultar(
        f"""
        SELECT g.id_grupo
        FROM grupo g
        JOIN grupo_miembro m ON m.id_grupo = g.id_grupo AND m.id_usuario = %s
        WHERE g.id_grupo IN ({marcas(len(ids_grupos))})
          AND g.activo = 1
          AND ST_Distance_Sphere(g.centro, {PUNTO_SQL}) <= g.radio_metros
        """,
        (id_usuario, *ids_grupos, punto),
    )
    if len(validos) != len(ids_grupos):
        raise HTTPException(
            status_code=422,
            detail="Solo puedes compartir el reporte en tus grupos cuya área incluye el lugar del incidente",
        )


def _guardar_reporte(datos: dict, ids_grupos: list[int], evidencia_url: str | None) -> int:
    with transaccion() as cursor:
        cursor.execute(
            f"""
            INSERT INTO reporte (
                id_usuario, id_categoria, id_comuna, id_localidad,
                ubicacion, direccion_referencia, descripcion, visibilidad, fecha_expiracion
            ) VALUES (
                %s, %s, %s, %s, {PUNTO_SQL}, %s, %s, %s,
                DATE_ADD(NOW(), INTERVAL %s HOUR)
            )
            """,
            (
                datos["id_usuario"], datos["id_categoria"], datos["id_comuna"], datos["id_localidad"],
                datos["punto"], datos["direccion"], datos["descripcion"], datos["visibilidad"],
                datos["horas_vigencia"],
            ),
        )
        id_reporte = cursor.lastrowid
        for id_grupo in ids_grupos:
            cursor.execute(
                "INSERT INTO grupo_reporte (id_grupo, id_reporte) VALUES (%s, %s)",
                (id_grupo, id_reporte),
            )
        if evidencia_url is not None:
            cursor.execute(
                "INSERT INTO reporte_imagen (id_reporte, url_archivo, orden) VALUES (%s, %s, 1)",
                (id_reporte, evidencia_url),
            )
    return id_reporte


def _generar_avisos(id_reporte: int, punto: str, id_autor: int, ids_grupos: list[int], privado: bool) -> tuple[int, int]:
    """Avisos del reporte ya confirmado en la BD. Devuelve (zonas avisadas, miembros avisados).

    Primero los del grupo: quien es miembro y además tiene una zona segura cerca
    recibe un solo aviso, el del grupo. Un reporte privado no avisa a las zonas seguras.
    """
    avisos_grupo = avisos.notificar_grupos(id_reporte, ids_grupos, id_autor)
    if privado:
        return 0, avisos_grupo
    # Si otro vecino ya reportó el mismo hecho, quien ya recibió esa alerta no la
    # recibe de nuevo: para la comunidad es el mismo incidente.
    ya_avisados = [r["id_reporte"] for r in reportes_del_incidente(id_reporte) if r["id_reporte"] != id_reporte]
    return avisos.notificar_zonas_seguras(id_reporte, punto, id_autor, ya_avisados), avisos_grupo


@router.post("/", status_code=201)
def crear_reporte(
    tareas: BackgroundTasks,
    usuario: dict = Depends(usuario_actual),
    id_categoria: int = Form(ge=1),
    descripcion: str = Form(min_length=1, max_length=500),
    latitud: float = Form(ge=-90, le=90),
    longitud: float = Form(ge=-180, le=180),
    direccion: str | None = Form(None, max_length=255),
    evidencia: UploadFile | None = File(None),
    ids_grupos: str = Form("", max_length=100),
    solo_grupo: bool = Form(False),
):
    """Crea un reporte. Con `ids_grupos` ("3,7") además aparece en el chat de esos
    grupos; con `solo_grupo` es privado: no sale en el mapa ni avisa a las zonas seguras.

    Los ids van separados por comas porque el formulario multipart de la app
    no admite repetir un campo. El autor sale del token de sesión, no de un dato del cliente.
    """
    descripcion = descripcion.strip()
    if not descripcion:
        raise HTTPException(status_code=422, detail="La descripción no puede estar vacía")
    horas_vigencia = _horas_vigencia(id_categoria)

    punto = punto_wkt(latitud, longitud)
    id_comuna = resolver_comuna(punto)
    if id_comuna is None:
        raise HTTPException(status_code=422, detail="La ubicación está fuera de las comunas donde funciona RB Alertas")
    id_localidad = resolver_localidad(punto, id_comuna)

    # Antes de guardar la evidencia, para no dejar un archivo huérfano si los grupos no sirven.
    grupos = _leer_ids_grupos(ids_grupos)
    if solo_grupo and not grupos:
        raise HTTPException(status_code=422, detail="Elige al menos un grupo para que el reporte sea privado")
    if grupos:
        _validar_grupos_del_reporte(grupos, usuario["id_usuario"], punto)
    visibilidad = "GRUPO" if solo_grupo else "PUBLICO"

    ruta_evidencia, evidencia_url = EVIDENCIAS.guardar(evidencia) if hay_archivo(evidencia) else (None, None)
    datos = {
        "id_usuario": usuario["id_usuario"],
        "id_categoria": id_categoria,
        "id_comuna": id_comuna,
        "id_localidad": id_localidad,
        "punto": punto,
        "direccion": direccion,
        "descripcion": descripcion,
        "visibilidad": visibilidad,
        "horas_vigencia": horas_vigencia,
    }
    try:
        id_reporte = _guardar_reporte(datos, grupos, evidencia_url)
    except Exception as error:
        if ruta_evidencia is not None:
            ruta_evidencia.unlink(missing_ok=True)
        if isinstance(error, mysql.connector.Error):
            raise error_bd(error, "No se pudo guardar el reporte. Inténtalo otra vez") from error
        raise

    zonas_notificadas, miembros_notificados = _generar_avisos(
        id_reporte, punto, usuario["id_usuario"], grupos, privado=visibilidad == "GRUPO"
    )
    # El push sale después de responder, igual que los correos: no demora el reporte.
    if zonas_notificadas or miembros_notificados:
        tareas.add_task(push.enviar_alertas_de_reporte, id_reporte)

    return {
        "id_reporte": id_reporte,
        "estado": "PENDIENTE",
        "visibilidad": visibilidad,
        "evidencia_url": evidencia_url,
        "zonas_notificadas": zonas_notificadas,
        "grupos": grupos,
        "miembros_notificados": miembros_notificados,
    }
