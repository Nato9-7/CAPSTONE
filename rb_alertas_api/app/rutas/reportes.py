import mimetypes
import os
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
import mysql.connector

from app.db import consultar, transaccion

router = APIRouter()

# En Docker esta carpeta debe montarse como volumen; si no, las evidencias
# se pierden al recrear el contenedor.
CARPETA_UPLOADS = Path(os.getenv("CARPETA_UPLOADS", Path(__file__).resolve().parents[2] / "uploads"))
CARPETA_EVIDENCIAS = CARPETA_UPLOADS / "reportes"
CARPETA_EVIDENCIAS.mkdir(parents=True, exist_ok=True)

TAMANO_MAXIMO_EVIDENCIA = 20 * 1024 * 1024  # 20 MB

EXTENSIONES_PERMITIDAS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/webm": ".webm",
}

# Con SRID 4326 MySQL lee el WKT como latitud-longitud; se fija el orden
# para escribir siempre POINT(longitud latitud).
PUNTO_SQL = "ST_GeomFromText(%s, 4326, 'axis-order=long-lat')"


def _primer_id(sql: str, parametros: tuple, columna: str):
    try:
        filas = consultar(sql, parametros)
    except mysql.connector.Error:
        # Sin polígonos/centroides cargados o función espacial no soportada:
        # se sigue con el siguiente criterio.
        return None
    return filas[0][columna] if filas else None


def _resolver_comuna(punto_wkt: str, id_comuna_usuario):
    """Comuna cuyo límite contiene el punto; si no, la de centroide más cercano; si no, la del usuario."""
    id_comuna = _primer_id(
        f"SELECT id_comuna FROM comuna WHERE limite IS NOT NULL AND ST_Contains(limite, {PUNTO_SQL}) LIMIT 1",
        (punto_wkt,),
        "id_comuna",
    )
    if id_comuna is None:
        id_comuna = _primer_id(
            f"""
            SELECT id_comuna FROM comuna
            WHERE operativa = 1 AND centroide IS NOT NULL
            ORDER BY ST_Distance(centroide, {PUNTO_SQL})
            LIMIT 1
            """,
            (punto_wkt,),
            "id_comuna",
        )
    return id_comuna if id_comuna is not None else id_comuna_usuario


def _resolver_localidad(punto_wkt: str, id_comuna: int):
    return _primer_id(
        f"""
        SELECT id_localidad FROM localidad
        WHERE id_comuna = %s AND activa = 1 AND limite IS NOT NULL
          AND ST_Contains(limite, {PUNTO_SQL})
        LIMIT 1
        """,
        (id_comuna, punto_wkt),
        "id_localidad",
    )


@router.get("/categorias")
def listar_categorias():
    return consultar(
        """
        SELECT id_categoria, codigo, nombre, icono, color_hex
        FROM categoria_incidente
        WHERE activa = 1
        ORDER BY id_categoria
        """
    )


@router.post("/", status_code=201)
async def crear_reporte(
    uuid_usuario: UUID = Form(),
    id_categoria: int = Form(ge=1),
    descripcion: str = Form(min_length=1, max_length=500),
    latitud: float = Form(ge=-90, le=90),
    longitud: float = Form(ge=-180, le=180),
    direccion: str | None = Form(None, max_length=255),
    evidencia: UploadFile | None = File(None),
):
    descripcion = descripcion.strip()
    if not descripcion:
        raise HTTPException(status_code=422, detail="La descripción no puede estar vacía")

    usuarios = consultar(
        "SELECT id_usuario, id_comuna FROM usuario WHERE uuid_publico = %s",
        (str(uuid_usuario),),
    )
    if not usuarios:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    usuario = usuarios[0]

    categorias = consultar(
        "SELECT id_categoria FROM categoria_incidente WHERE id_categoria = %s AND activa = 1",
        (id_categoria,),
    )
    if not categorias:
        raise HTTPException(status_code=422, detail="Categoría no válida")

    punto_wkt = f"POINT({longitud} {latitud})"
    id_comuna = _resolver_comuna(punto_wkt, usuario["id_comuna"])
    if id_comuna is None:
        raise HTTPException(status_code=422, detail="No se pudo determinar la comuna de la ubicación")
    id_localidad = _resolver_localidad(punto_wkt, id_comuna)

    ruta_evidencia = None
    evidencia_url = None

    if evidencia is not None and evidencia.filename:
        # Flutter web suele enviar application/octet-stream, así que si el
        # tipo no sirve se deduce por la extensión del archivo.
        tipo = evidencia.content_type
        if tipo not in EXTENSIONES_PERMITIDAS:
            tipo = mimetypes.guess_type(evidencia.filename)[0]
        if tipo not in EXTENSIONES_PERMITIDAS:
            raise HTTPException(status_code=415, detail="La evidencia debe ser una foto o un video")

        contenido = await evidencia.read(TAMANO_MAXIMO_EVIDENCIA + 1)
        if len(contenido) > TAMANO_MAXIMO_EVIDENCIA:
            raise HTTPException(status_code=413, detail="La evidencia no puede superar los 20 MB")

        nombre_archivo = f"{uuid4().hex}{EXTENSIONES_PERMITIDAS[tipo]}"
        ruta_evidencia = CARPETA_EVIDENCIAS / nombre_archivo
        ruta_evidencia.write_bytes(contenido)
        evidencia_url = f"/uploads/reportes/{nombre_archivo}"

    try:
        with transaccion() as cursor:
            cursor.execute(
                f"""
                INSERT INTO reporte (
                    id_usuario, id_categoria, id_comuna, id_localidad,
                    ubicacion, direccion_referencia, descripcion, estado,
                    es_anonimo, total_confirmaciones, total_desmentidos
                ) VALUES (%s, %s, %s, %s, {PUNTO_SQL}, %s, %s, 'pendiente', 0, 0, 0)
                """,
                (
                    usuario["id_usuario"],
                    id_categoria,
                    id_comuna,
                    id_localidad,
                    punto_wkt,
                    direccion,
                    descripcion,
                ),
            )
            id_reporte = cursor.lastrowid

            if evidencia_url is not None:
                cursor.execute(
                    "INSERT INTO reporte_imagen (id_reporte, url_archivo, orden) VALUES (%s, %s, 1)",
                    (id_reporte, evidencia_url),
                )
    except mysql.connector.Error as error:
        if ruta_evidencia is not None:
            ruta_evidencia.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=error.msg)

    return {
        "id_reporte": id_reporte,
        "estado": "pendiente",
        "evidencia_url": evidencia_url,
    }
