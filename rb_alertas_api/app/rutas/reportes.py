import hashlib
import logging
import os
from pathlib import Path
from uuid import uuid4

from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Path as PathParam, Query, UploadFile
from pydantic import BaseModel
import mysql.connector

from app.db import consultar, ejecutar, transaccion
from app.seguridad import usuario_actual, usuario_opcional

router = APIRouter()
log = logging.getLogger("rb_alertas.reportes")

# En Docker esta carpeta debe montarse como volumen; si no, las evidencias
# se pierden al recrear el contenedor. El volumen debe pertenecer al usuario
# con que corre la API (en la imagen, appuser).
CARPETA_UPLOADS = Path(os.getenv("CARPETA_UPLOADS", Path(__file__).resolve().parents[2] / "uploads"))
CARPETA_EVIDENCIAS = CARPETA_UPLOADS / "reportes"

# Si la carpeta no se puede escribir, la API arranca igual y solo rechaza
# las evidencias: sin esto, un problema de permisos tumba toda la API.
try:
    CARPETA_EVIDENCIAS.mkdir(parents=True, exist_ok=True)
    EVIDENCIAS_DISPONIBLES = os.access(CARPETA_EVIDENCIAS, os.W_OK)
except OSError:
    EVIDENCIAS_DISPONIBLES = False
if not EVIDENCIAS_DISPONIBLES:
    log.error("No se puede escribir en %s: los reportes funcionan, pero sin evidencias", CARPETA_EVIDENCIAS)

TAMANO_MAXIMO_EVIDENCIA = 20 * 1024 * 1024  # 20 MB

# Radio máximo desde el centroide de una comuna operativa para asignarle un reporte 
RADIO_MAXIMO_COMUNA_METROS = 40_000

# Radio de alertas cercanas cuando el usuario no tiene preferencia guardada
# (usuario_preferencia.radio_alerta_metros) ni lo pide explícitamente.
RADIO_ALERTA_POR_DEFECTO_METROS = 2000

# Votos necesarios para que la comunidad valide o descarte un reporte.
VOTOS_PARA_CAMBIAR_ESTADO = 3

# Con SRID 4326 MySQL lee el WKT como latitud-longitud; se fija el orden
PUNTO_SQL = "ST_GeomFromText(%s, 4326, 'axis-order=long-lat')"


def _primer_id(sql: str, parametros: tuple, columna: str):
    try:
        filas = consultar(sql, parametros)
    except mysql.connector.Error:
        # Sin polígonos/centroides cargados o función espacial no soportada:
        # se sigue con el siguiente criterio.
        return None
    return filas[0][columna] if filas else None


def _detectar_formato(contenido: bytes):
    """Extensión según la firma real del archivo; None si no es una foto o video aceptado.

    Se mira el contenido y no el Content-Type ni el nombre, que los controla el cliente.
    """
    if contenido.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if contenido.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if contenido[:4] == b"RIFF" and contenido[8:12] == b"WEBP":
        return ".webp"
    if contenido.startswith(b"\x1a\x45\xdf\xa3"):
        return ".webm"
    if contenido[4:8] == b"ftyp":
        marca = contenido[8:12]
        if marca in (b"heic", b"heix", b"mif1", b"msf1", b"hevc"):
            return ".heic"
        if marca == b"qt  ":
            return ".mov"
        return ".mp4"
    return None


def _radio_alerta_metros(usuario: dict | None, radio_km: float | None) -> int:
    """Radio a consultar: el que pide el cliente, si no el del usuario, si no el estándar."""
    if radio_km is not None:
        return int(radio_km * 1000)
    if usuario is not None:
        try:
            filas = consultar(
                "SELECT radio_alerta_metros FROM usuario_preferencia WHERE id_usuario = %s",
                (usuario["id_usuario"],),
            )
        except mysql.connector.Error:
            # Sin tabla de preferencias la pantalla igual funciona con el radio estándar.
            filas = []
        if filas and filas[0]["radio_alerta_metros"]:
            return int(filas[0]["radio_alerta_metros"])
    return RADIO_ALERTA_POR_DEFECTO_METROS


def _resolver_comuna(punto_wkt: str):
    """Comuna cuyo límite contiene el punto; si no, la operativa cuyo centroide esté a menos de
    RADIO_MAXIMO_COMUNA_METROS. None si el punto queda fuera de toda comuna con cobertura."""
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
              AND ST_Distance(centroide, {PUNTO_SQL}) <= %s
            ORDER BY ST_Distance(centroide, {PUNTO_SQL})
            LIMIT 1
            """,
            (punto_wkt, RADIO_MAXIMO_COMUNA_METROS, punto_wkt),
            "id_comuna",
        )
    return id_comuna


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


@router.get("/")
def listar_reportes(limite: int = Query(200, ge=1, le=500)):
    """Reportes vigentes para dibujar en el mapa, del más reciente al más antiguo."""
    return consultar(
        """
        SELECT r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
               c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
               ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion, r.estado,
               r.fecha_creacion
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.estado IN ('PENDIENTE', 'VALIDADO')
          AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (limite,),
    )


@router.get("/cercanos")
def listar_reportes_cercanos(
    usuario: dict | None = Depends(usuario_opcional),
    latitud: float = Query(ge=-90, le=90),
    longitud: float = Query(ge=-180, le=180),
    radio_km: float | None = Query(None, gt=0, le=50),
    limite: int = Query(50, ge=1, le=200),
):
    """Reportes vigentes alrededor del punto, del más reciente al más antiguo.

    Alimenta la pantalla Alertas: cada fila trae la distancia en metros al punto
    consultado para poder mostrar "a 500 m" sin recalcular en el cliente.

    Sin `radio_km`, se usa el radio que el usuario guardó en sus preferencias;
    si no tiene sesión o no lo ha configurado, RADIO_ALERTA_POR_DEFECTO_METROS.
    La respuesta devuelve el radio aplicado para poder mostrarlo en pantalla.
    """
    radio_metros = _radio_alerta_metros(usuario, radio_km)
    punto_wkt = f"POINT({longitud} {latitud})"
    reportes = consultar(
        f"""
        SELECT r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
               c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
               ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion, r.estado,
               r.fecha_creacion, r.total_confirmaciones, r.total_desmentidos,
               ST_Distance(r.ubicacion, {PUNTO_SQL}) AS distancia_metros
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.estado IN ('PENDIENTE', 'VALIDADO')
          AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())
          AND ST_Distance(r.ubicacion, {PUNTO_SQL}) <= %s
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (punto_wkt, punto_wkt, radio_metros, limite),
    )
    return {
        "radio_metros": radio_metros,
        "total": len(reportes),
        "reportes": reportes,
    }


@router.get("/mios")
def listar_mis_reportes(
    usuario: dict = Depends(usuario_actual),
    limite: int = Query(100, ge=1, le=300),
):
    """Historial de reportes de quien consulta, del más reciente al más antiguo.

    `estado_visual` traduce el estado de la BD a lo que ve el usuario:
    RESUELTA, VENCIDA (vigencia cumplida sin resolver) o ACTIVA.
    """
    return consultar(
        """
        SELECT r.id_reporte, c.codigo AS categoria_codigo, c.nombre AS categoria,
               c.color_hex, ST_Latitude(r.ubicacion) AS latitud,
               ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               r.estado, r.fecha_creacion, r.fecha_expiracion,
               r.total_confirmaciones, r.total_desmentidos,
               COALESCE(l.nombre, cm.nombre) AS zona,
               CASE
                   WHEN r.estado = 'RESUELTO' THEN 'RESUELTA'
                   WHEN r.estado = 'DESCARTADO' THEN 'DESCARTADA'
                   WHEN r.estado = 'EXPIRADO' THEN 'VENCIDA'
                   WHEN r.fecha_expiracion IS NOT NULL
                        AND r.fecha_expiracion <= NOW() THEN 'VENCIDA'
                   ELSE 'ACTIVA'
               END AS estado_visual,
               (
                   SELECT i.url_archivo FROM reporte_imagen i
                   WHERE i.id_reporte = r.id_reporte
                   ORDER BY i.orden LIMIT 1
               ) AS imagen
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        WHERE r.id_usuario = %s
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (usuario["id_usuario"], limite),
    )


@router.post("/", status_code=201)
def crear_reporte(
    usuario: dict = Depends(usuario_actual),
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

    # El autor sale del token de sesión validado en el servidor (usuario_actual),
    # no de un dato que envíe el cliente.
    categorias = consultar(
        "SELECT horas_vigencia FROM categoria_incidente WHERE id_categoria = %s AND activa = 1",
        (id_categoria,),
    )
    if not categorias:
        raise HTTPException(status_code=422, detail="Categoría no válida")
    horas_vigencia = categorias[0]["horas_vigencia"]

    punto_wkt = f"POINT({longitud} {latitud})"
    id_comuna = _resolver_comuna(punto_wkt)
    if id_comuna is None:
        raise HTTPException(
            status_code=422,
            detail="La ubicación está fuera de las comunas donde funciona RB Alertas",
        )
    id_localidad = _resolver_localidad(punto_wkt, id_comuna)

    ruta_evidencia = None
    evidencia_url = None

    if evidencia is not None and evidencia.filename:
        if not EVIDENCIAS_DISPONIBLES:
            raise HTTPException(
                status_code=503,
                detail="Por ahora no se pueden adjuntar fotos o videos. Envía el reporte sin evidencia.",
            )
        contenido = evidencia.file.read(TAMANO_MAXIMO_EVIDENCIA + 1)
        if len(contenido) > TAMANO_MAXIMO_EVIDENCIA:
            raise HTTPException(status_code=413, detail="La evidencia no puede superar los 20 MB")

        extension = _detectar_formato(contenido)
        if extension is None:
            raise HTTPException(
                status_code=415,
                detail="La evidencia debe ser una foto (JPG, PNG, WEBP, HEIC) o un video (MP4, MOV, WEBM)",
            )

        nombre_archivo = f"{uuid4().hex}{extension}"
        ruta_evidencia = CARPETA_EVIDENCIAS / nombre_archivo
        ruta_evidencia.write_bytes(contenido)
        evidencia_url = f"/uploads/reportes/{nombre_archivo}"

    try:
        with transaccion() as cursor:
            cursor.execute(
                f"""
                INSERT INTO reporte (
                    id_usuario, id_categoria, id_comuna, id_localidad,
                    ubicacion, direccion_referencia, descripcion, fecha_expiracion
                ) VALUES (
                    %s, %s, %s, %s, {PUNTO_SQL}, %s, %s,
                    DATE_ADD(NOW(), INTERVAL %s HOUR)
                )
                """,
                (
                    usuario["id_usuario"],
                    id_categoria,
                    id_comuna,
                    id_localidad,
                    punto_wkt,
                    direccion,
                    descripcion,
                    horas_vigencia,
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
        "estado": "PENDIENTE",
        "evidencia_url": evidencia_url,
    }


def _entidad_emergencia(id_entidad, id_comuna: int):
    """Organismo a llamar: el de la categoría; si no tiene, Seguridad Ciudadana (u otro) de la comuna."""
    if id_entidad is not None:
        filas = consultar(
            "SELECT nombre, tipo, telefono FROM entidad_emergencia WHERE id_entidad = %s AND activa = 1",
            (id_entidad,),
        )
        if filas:
            return filas[0]
    filas = consultar(
        """
        SELECT nombre, tipo, telefono FROM entidad_emergencia
        WHERE id_comuna = %s AND activa = 1
        ORDER BY tipo = 'SEGURIDAD_CIUDADANA' DESC, id_entidad
        LIMIT 1
        """,
        (id_comuna,),
    )
    return filas[0] if filas else None


# Nombres de fantasía para quien reporta: por seguridad, el nombre real nunca
# sale de la API (evita represalias contra quien denuncia).
ADJETIVOS_SURICATA = (
    "Vigía", "Centinela", "Valiente", "Atenta", "Curiosa", "Veloz", "Guardiana", "Exploradora",
    "Solidaria", "Despierta", "Alerta", "Intrépida", "Astuta", "Serena", "Audaz", "Protectora",
)


def alias_autor(id_reporte: int) -> str:
    """Alias fijo por reporte (siempre el mismo al recargar), p. ej. «Suricata Centinela 42».

    Sale del id del reporte y no del usuario: dos reportes de la misma persona tienen
    alias distintos, así nadie puede juntar sus reportes para adivinar quién es.
    """
    semilla = int.from_bytes(hashlib.sha256(f"alias-reporte:{id_reporte}".encode()).digest()[:8], "big")
    adjetivo = ADJETIVOS_SURICATA[semilla % len(ADJETIVOS_SURICATA)]
    numero = 10 + (semilla // len(ADJETIVOS_SURICATA)) % 90
    return f"Suricata {adjetivo} {numero}"


@router.get("/{id_reporte}")
def detalle_reporte(
    id_reporte: int = PathParam(ge=1),
    usuario: dict | None = Depends(usuario_opcional),
):
    filas = consultar(
        """
        SELECT r.id_reporte, r.id_usuario, r.id_comuna, r.estado,
               r.total_confirmaciones, r.total_desmentidos,
               c.codigo AS categoria_codigo, c.nombre AS categoria, c.color_hex, c.id_entidad,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               r.fecha_creacion, r.fecha_expiracion
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.id_reporte = %s
        """,
        (id_reporte,),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    r = filas[0]

    imagenes = consultar(
        "SELECT url_archivo FROM reporte_imagen WHERE id_reporte = %s ORDER BY orden",
        (id_reporte,),
    )

    # Voto propio, para que la app muestre cuál de los dos botones está marcado.
    mi_voto = None
    if usuario is not None:
        votos = consultar(
            "SELECT tipo_voto FROM reporte_voto WHERE id_reporte = %s AND id_usuario = %s",
            (id_reporte, usuario["id_usuario"]),
        )
        if votos:
            mi_voto = votos[0]["tipo_voto"]
    # El id del autor no se expone: solo si quien consulta es el autor.
    return {
        "id_reporte": r["id_reporte"],
        "categoria_codigo": r["categoria_codigo"],
        "categoria": r["categoria"],
        "color_hex": r["color_hex"],
        "latitud": r["latitud"],
        "longitud": r["longitud"],
        "direccion": r["direccion"],
        "descripcion": r["descripcion"],
        "estado": r["estado"],
        "fecha_creacion": r["fecha_creacion"],
        "fecha_expiracion": r["fecha_expiracion"],
        "autor": alias_autor(r["id_reporte"]),
        "es_autor": usuario is not None and usuario["id_usuario"] == r["id_usuario"],
        "total_confirmaciones": r["total_confirmaciones"],
        "total_desmentidos": r["total_desmentidos"],
        "mi_voto": mi_voto,
        "imagenes": [fila["url_archivo"] for fila in imagenes],
        "emergencia": _entidad_emergencia(r["id_entidad"], r["id_comuna"]),
    }


class VotoReporte(BaseModel):
    tipo_voto: Literal["CONFIRMA", "DESMIENTE"]


def _reporte_votable(id_reporte: int, id_usuario: int) -> dict:
    """Valida que el reporte admita votos de este usuario y lo devuelve."""
    filas = consultar(
        """
        SELECT id_usuario, estado,
               (fecha_expiracion IS NOT NULL AND fecha_expiracion <= NOW()) AS vencido
        FROM reporte WHERE id_reporte = %s
        """,
        (id_reporte,),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    reporte = filas[0]
    if reporte["id_usuario"] == id_usuario:
        raise HTTPException(status_code=403, detail="No puedes votar tu propio reporte")
    if reporte["estado"] not in ("PENDIENTE", "VALIDADO") or reporte["vencido"]:
        raise HTTPException(status_code=409, detail="Este reporte ya no admite votos")
    return reporte


@router.put("/{id_reporte}/voto")
def votar_reporte(
    datos: VotoReporte,
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Confirma o desmiente un reporte. Un voto por persona: repetirlo lo cambia.

    Los contadores de `reporte` y el paso a VALIDADO/DESCARTADO los mantienen
    los triggers de reporte_voto, no esta función: así el conteo no se duplica
    ni se descuadra si alguien vota fuera de la API.
    """
    _reporte_votable(id_reporte, usuario["id_usuario"])
    try:
        ejecutar(
            """
            INSERT INTO reporte_voto (id_reporte, id_usuario, tipo_voto)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE tipo_voto = VALUES(tipo_voto), fecha_voto = NOW()
            """,
            (id_reporte, usuario["id_usuario"], datos.tipo_voto),
        )
    except mysql.connector.Error as error:
        raise HTTPException(status_code=400, detail=error.msg)
    return _resumen_votos(id_reporte, datos.tipo_voto)


@router.delete("/{id_reporte}/voto")
def quitar_voto(
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Retira el voto propio. Si no había voto, responde igual (operación idempotente)."""
    ejecutar(
        "DELETE FROM reporte_voto WHERE id_reporte = %s AND id_usuario = %s",
        (id_reporte, usuario["id_usuario"]),
    )
    return _resumen_votos(id_reporte, None)


def _resumen_votos(id_reporte: int, mi_voto: str | None) -> dict:
    """Contadores ya actualizados por el trigger, para refrescar la pantalla."""
    filas = consultar(
        "SELECT total_confirmaciones, total_desmentidos, estado FROM reporte WHERE id_reporte = %s",
        (id_reporte,),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    return {
        "id_reporte": id_reporte,
        "total_confirmaciones": filas[0]["total_confirmaciones"],
        "total_desmentidos": filas[0]["total_desmentidos"],
        "estado": filas[0]["estado"],
        "mi_voto": mi_voto,
    }


@router.post("/{id_reporte}/resolver")
def resolver_reporte(
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Quien creó el reporte lo marca como resuelto; el cambio queda en reporte_estado_historial."""
    filas = consultar("SELECT id_usuario, estado FROM reporte WHERE id_reporte = %s", (id_reporte,))
    if not filas:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    reporte = filas[0]
    if reporte["id_usuario"] != usuario["id_usuario"]:
        raise HTTPException(status_code=403, detail="Solo quien creó el reporte puede marcarlo como resuelto")
    if reporte["estado"] not in ("PENDIENTE", "VALIDADO"):
        raise HTTPException(status_code=409, detail=f"Este reporte ya está {reporte['estado'].lower()}")

    with transaccion() as cursor:
        cursor.execute(
            "UPDATE reporte SET estado = 'RESUELTO' WHERE id_reporte = %s AND estado IN ('PENDIENTE', 'VALIDADO')",
            (id_reporte,),
        )
        if cursor.rowcount == 0:
            # Otro cambio de estado se adelantó entre la consulta y el UPDATE.
            raise HTTPException(status_code=409, detail="El estado del reporte cambió. Vuelve a cargarlo")
        cursor.execute(
            """
            INSERT INTO reporte_estado_historial (
                id_reporte, estado_anterior, estado_nuevo, id_usuario_responsable, motivo
            ) VALUES (%s, %s, 'RESUELTO', %s, 'Marcado como resuelto por quien lo reportó')
            """,
            (id_reporte, reporte["estado"], usuario["id_usuario"]),
        )
    return {"id_reporte": id_reporte, "estado": "RESUELTO"}
