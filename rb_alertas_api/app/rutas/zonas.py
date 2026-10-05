from fastapi import APIRouter, Depends, HTTPException, Path as PathParam
from pydantic import BaseModel, Field
import mysql.connector

from app.db import consultar, ejecutar
from app.seguridad import usuario_actual

router = APIRouter()

MAXIMO_ZONAS_POR_USUARIO = 3
RADIOS_PERMITIDOS = (500, 1000, 2000)
NOMBRES_PREDEFINIDOS = {"CASA": "Casa", "TRABAJO": "Trabajo", "ESTUDIO": "Estudio"}

# Con SRID 4326 MySQL lee el WKT como latitud-longitud; se fija el orden.
PUNTO_SQL = "ST_GeomFromText(%s, 4326, 'axis-order=long-lat')"


class ZonaSegura(BaseModel):
    tipo: str = Field(pattern="^(CASA|TRABAJO|ESTUDIO|OTRO)$")
    nombre: str | None = Field(None, max_length=60)
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)
    radio_metros: int
    direccion_referencia: str | None = Field(None, max_length=255)


def _nombre_final(datos: ZonaSegura) -> str:
    """CASA/TRABAJO/ESTUDIO usan un nombre fijo; OTRO exige que el usuario escriba uno."""
    if datos.tipo in NOMBRES_PREDEFINIDOS:
        return NOMBRES_PREDEFINIDOS[datos.tipo]
    nombre = (datos.nombre or "").strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="Escribe un nombre para la zona")
    return nombre[:60]


def _validar_radio(radio: int) -> int:
    if radio not in RADIOS_PERMITIDOS:
        raise HTTPException(
            status_code=422,
            detail="El radio debe ser 500, 1000 o 2000 metros",
        )
    return radio


def tipo_de_nombre(nombre: str) -> str:
    """Operacion inversa: a partir del nombre guardado, el tipo que dibuja el icono."""
    for tipo, etiqueta in NOMBRES_PREDEFINIDOS.items():
        if nombre.strip().lower() == etiqueta.lower():
            return tipo
    return "OTRO"


def _fila_a_json(fila: dict) -> dict:
    nombre = fila["nombre"]
    return {
        "id_zona_segura": fila["id_zona_segura"],
        "tipo": tipo_de_nombre(nombre),
        "nombre": nombre,
        "latitud": float(fila["latitud"]),
        "longitud": float(fila["longitud"]),
        "radio_metros": int(fila["radio_metros"]),
        "direccion_referencia": fila["direccion_referencia"],
        "fecha_creacion": fila["fecha_creacion"].isoformat() if fila["fecha_creacion"] else None,
    }


def _zonas_del_usuario(id_usuario: int) -> list[dict]:
    filas = consultar(
        """
        SELECT id_zona_segura, nombre,
               ST_Latitude(centro) AS latitud, ST_Longitude(centro) AS longitud,
               radio_metros, direccion_referencia, fecha_creacion
        FROM zona_segura
        WHERE id_usuario = %s AND activa = 1
        ORDER BY fecha_creacion
        """,
        (id_usuario,),
    )
    return [_fila_a_json(f) for f in filas]


def _zona_propia(id_zona: int, id_usuario: int) -> None:
    """404 si la zona no existe o es de otro usuario: no se revela cual de los dos."""
    filas = consultar(
        "SELECT id_zona_segura FROM zona_segura WHERE id_zona_segura = %s AND id_usuario = %s",
        (id_zona, id_usuario),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="La zona no existe")


@router.get("/")
def listar_zonas(usuario: dict = Depends(usuario_actual)):
    zonas = _zonas_del_usuario(usuario["id_usuario"])
    return {
        "zonas": zonas,
        "maximo": MAXIMO_ZONAS_POR_USUARIO,
        "radios_permitidos": list(RADIOS_PERMITIDOS),
    }


@router.post("/", status_code=201)
def crear_zona(datos: ZonaSegura, usuario: dict = Depends(usuario_actual)):
    id_usuario = usuario["id_usuario"]
    nombre = _nombre_final(datos)
    radio = _validar_radio(datos.radio_metros)

    actuales = consultar(
        "SELECT COUNT(*) AS total FROM zona_segura WHERE id_usuario = %s AND activa = 1",
        (id_usuario,),
    )
    if actuales and actuales[0]["total"] >= MAXIMO_ZONAS_POR_USUARIO:
        raise HTTPException(
            status_code=409,
            detail=f"Solo puedes tener {MAXIMO_ZONAS_POR_USUARIO} zonas seguras. Elimina una para agregar otra",
        )

    punto_wkt = f"POINT({datos.longitud} {datos.latitud})"
    try:
        id_zona = ejecutar(
            f"""
            INSERT INTO zona_segura (
                id_usuario, nombre, centro, radio_metros, direccion_referencia
            ) VALUES (%s, %s, {PUNTO_SQL}, %s, %s)
            """,
            (id_usuario, nombre, punto_wkt, radio, (datos.direccion_referencia or "").strip() or None),
        )
    except mysql.connector.Error as error:
        # uq_zona_usuario_nombre: el usuario ya tiene una zona con ese nombre.
        if error.errno == 1062:
            raise HTTPException(status_code=409, detail=f"Ya tienes una zona llamada «{nombre}»")
        raise HTTPException(status_code=400, detail=error.msg)

    filas = consultar(
        """
        SELECT id_zona_segura, nombre,
               ST_Latitude(centro) AS latitud, ST_Longitude(centro) AS longitud,
               radio_metros, direccion_referencia, fecha_creacion
        FROM zona_segura WHERE id_zona_segura = %s
        """,
        (id_zona,),
    )
    return _fila_a_json(filas[0])


@router.put("/{id_zona}")
def actualizar_zona(
    datos: ZonaSegura,
    id_zona: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    id_usuario = usuario["id_usuario"]
    _zona_propia(id_zona, id_usuario)
    nombre = _nombre_final(datos)
    radio = _validar_radio(datos.radio_metros)

    punto_wkt = f"POINT({datos.longitud} {datos.latitud})"
    try:
        ejecutar(
            f"""
            UPDATE zona_segura
               SET nombre = %s,
                   centro = {PUNTO_SQL},
                   radio_metros = %s,
                   direccion_referencia = %s
             WHERE id_zona_segura = %s AND id_usuario = %s
            """,
            (
                nombre,
                punto_wkt,
                radio,
                (datos.direccion_referencia or "").strip() or None,
                id_zona,
                id_usuario,
            ),
        )
    except mysql.connector.Error as error:
        if error.errno == 1062:
            raise HTTPException(status_code=409, detail=f"Ya tienes una zona llamada «{nombre}»")
        raise HTTPException(status_code=400, detail=error.msg)

    filas = consultar(
        """
        SELECT id_zona_segura, nombre,
               ST_Latitude(centro) AS latitud, ST_Longitude(centro) AS longitud,
               radio_metros, direccion_referencia, fecha_creacion
        FROM zona_segura WHERE id_zona_segura = %s
        """,
        (id_zona,),
    )
    return _fila_a_json(filas[0])


@router.delete("/{id_zona}", status_code=204)
def eliminar_zona(
    id_zona: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Borrado real: la zona desaparece. Las notificaciones que la originaron
    sobreviven porque fk_notif_zona es ON DELETE SET NULL."""
    _zona_propia(id_zona, usuario["id_usuario"])
    ejecutar(
        "DELETE FROM zona_segura WHERE id_zona_segura = %s AND id_usuario = %s",
        (id_zona, usuario["id_usuario"]),
    )
    return None
