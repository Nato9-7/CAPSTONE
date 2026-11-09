"""Grupos de quien consulta: crear, ver, editar, cerrar y regenerar el código de invitación."""

import mysql.connector
from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.comun.geo import PUNTO_SQL, punto_wkt
from app.comun.sql import error_bd, es_duplicado
from app.db import consultar, ejecutar, transaccion
from app.seguridad import usuario_actual
from app.servicios.grupos import (
    DIAS_VIGENCIA_CODIGO,
    INTENTOS_CODIGO,
    MAXIMO_GRUPOS_CREADOS,
    MAXIMO_GRUPOS_POR_USUARIO,
    RADIOS_PERMITIDOS,
    SELECT_GRUPO,
    exigir_admin,
    exigir_cupo,
    grupo_de_usuario,
    grupo_json,
    nuevo_codigo,
)

router = APIRouter()

MENSAJE_CODIGO_FALLIDO = "No se pudo generar el código del grupo. Inténtalo otra vez"


class DatosGrupo(BaseModel):
    nombre: str = Field(min_length=1, max_length=60)
    descripcion: str | None = Field(None, max_length=255)
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)
    radio_metros: int
    direccion_referencia: str | None = Field(None, max_length=255)


def _validar_datos(datos: DatosGrupo) -> tuple[str, str | None, str | None]:
    nombre = datos.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="Escribe un nombre para el grupo")
    if datos.radio_metros not in RADIOS_PERMITIDOS:
        raise HTTPException(status_code=422, detail="El radio debe ser 500, 1000 o 2000 metros")
    descripcion = (datos.descripcion or "").strip() or None
    direccion = (datos.direccion_referencia or "").strip() or None
    return nombre, descripcion, direccion


def _insertar_grupo(id_usuario: int, datos: DatosGrupo, nombre: str, descripcion: str | None, direccion: str | None) -> int:
    with transaccion() as cursor:
        cursor.execute(
            f"""
            INSERT INTO grupo (
                id_creador, nombre, descripcion, centro, radio_metros,
                direccion_referencia, codigo_invitacion, codigo_expira
            ) VALUES (
                %s, %s, %s, {PUNTO_SQL}, %s, %s, %s,
                DATE_ADD(NOW(), INTERVAL %s DAY)
            )
            """,
            (
                id_usuario, nombre, descripcion, punto_wkt(datos.latitud, datos.longitud),
                datos.radio_metros, direccion, nuevo_codigo(), DIAS_VIGENCIA_CODIGO,
            ),
        )
        id_grupo = cursor.lastrowid
        cursor.execute(
            "INSERT INTO grupo_miembro (id_grupo, id_usuario, rol) VALUES (%s, %s, 'ADMIN')",
            (id_grupo, id_usuario),
        )
    return id_grupo


@router.get("/")
def listar_mis_grupos(usuario: dict = Depends(usuario_actual)):
    """Grupos de quien consulta, el de actividad más reciente primero."""
    filas = consultar(
        SELECT_GRUPO + " ORDER BY COALESCE(ultimo_reporte, g.fecha_creacion) DESC",
        (usuario["id_usuario"],),
    )
    creados = sum(1 for fila in filas if fila["rol"] == "ADMIN")
    return {
        "grupos": [grupo_json(fila) for fila in filas],
        "maximo": MAXIMO_GRUPOS_POR_USUARIO,
        "puede_crear": creados < MAXIMO_GRUPOS_CREADOS and len(filas) < MAXIMO_GRUPOS_POR_USUARIO,
        "radios_permitidos": list(RADIOS_PERMITIDOS),
    }


@router.post("/", status_code=201)
def crear_grupo(datos: DatosGrupo, usuario: dict = Depends(usuario_actual)):
    id_usuario = usuario["id_usuario"]
    nombre, descripcion, direccion = _validar_datos(datos)

    creados = consultar(
        "SELECT COUNT(*) AS total FROM grupo WHERE id_creador = %s AND activo = 1",
        (id_usuario,),
    )
    if creados and creados[0]["total"] >= MAXIMO_GRUPOS_CREADOS:
        raise HTTPException(status_code=409, detail="Ya administras un grupo. Elimínalo para crear otro")
    exigir_cupo(id_usuario, "crear otro")

    for _ in range(INTENTOS_CODIGO):
        try:
            id_grupo = _insertar_grupo(id_usuario, datos, nombre, descripcion, direccion)
            return grupo_de_usuario(id_grupo, id_usuario)
        except mysql.connector.Error as error:
            if not es_duplicado(error):
                raise error_bd(error, "No se pudo crear el grupo. Inténtalo otra vez") from error
    raise HTTPException(status_code=503, detail=MENSAJE_CODIGO_FALLIDO)


@router.get("/en-punto")
def grupos_en_punto(
    usuario: dict = Depends(usuario_actual),
    latitud: float = Query(ge=-90, le=90),
    longitud: float = Query(ge=-180, le=180),
):
    """Grupos de quien consulta cuyo círculo contiene el punto: los que puede
    elegir al crear un reporte en esa ubicación."""
    return consultar(
        f"""
        SELECT g.id_grupo, g.nombre
        FROM grupo g
        JOIN grupo_miembro m ON m.id_grupo = g.id_grupo AND m.id_usuario = %s
        WHERE g.activo = 1
          AND ST_Distance_Sphere(g.centro, {PUNTO_SQL}) <= g.radio_metros
        ORDER BY g.nombre
        """,
        (usuario["id_usuario"], punto_wkt(latitud, longitud)),
    )


@router.get("/{id_grupo}")
def detalle_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    return grupo_de_usuario(id_grupo, usuario["id_usuario"])


@router.put("/{id_grupo}")
def actualizar_grupo(
    datos: DatosGrupo,
    id_grupo: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """El admin cambia nombre, descripción o área. Los reportes ya compartidos se quedan en el grupo."""
    exigir_admin(id_grupo, usuario["id_usuario"])
    nombre, descripcion, direccion = _validar_datos(datos)
    ejecutar(
        f"""
        UPDATE grupo
           SET nombre = %s, descripcion = %s, centro = {PUNTO_SQL},
               radio_metros = %s, direccion_referencia = %s
         WHERE id_grupo = %s AND activo = 1
        """,
        (nombre, descripcion, punto_wkt(datos.latitud, datos.longitud), datos.radio_metros, direccion, id_grupo),
    )
    return grupo_de_usuario(id_grupo, usuario["id_usuario"])


@router.delete("/{id_grupo}", status_code=204)
def eliminar_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """El admin cierra el grupo. Queda inactivo (no se borra), así el admin general
    puede revisarlo; sus reportes privados dejan de verlos los ex miembros."""
    exigir_admin(id_grupo, usuario["id_usuario"])
    ejecutar("UPDATE grupo SET activo = 0 WHERE id_grupo = %s", (id_grupo,))
    return None


@router.post("/{id_grupo}/codigo")
def regenerar_codigo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """Nuevo código con vigencia renovada; el anterior deja de servir de inmediato."""
    exigir_admin(id_grupo, usuario["id_usuario"])
    for _ in range(INTENTOS_CODIGO):
        try:
            ejecutar(
                """
                UPDATE grupo
                   SET codigo_invitacion = %s, codigo_expira = DATE_ADD(NOW(), INTERVAL %s DAY)
                 WHERE id_grupo = %s
                """,
                (nuevo_codigo(), DIAS_VIGENCIA_CODIGO, id_grupo),
            )
            return grupo_de_usuario(id_grupo, usuario["id_usuario"])
        except mysql.connector.Error as error:
            if not es_duplicado(error):
                raise error_bd(error, MENSAJE_CODIGO_FALLIDO) from error
    raise HTTPException(status_code=503, detail=MENSAJE_CODIGO_FALLIDO)
