"""Entrar y salir de un grupo: invitación con código, miembros y expulsión."""

import mysql.connector
from fastapi import APIRouter, Depends, HTTPException, Path as PathParam
from pydantic import BaseModel, Field

from app.comun.alias import alias_miembro
from app.comun.formato import iso
from app.comun.sql import error_bd, es_duplicado
from app.db import consultar, ejecutar, transaccion
from app.seguridad import usuario_actual
from app.servicios.grupos import exigir_admin, exigir_cupo, grupo_de_usuario, membresia, normalizar_codigo

router = APIRouter()

MENSAJE_CODIGO_INVALIDO = "El código no existe o ya venció. Pide uno nuevo al administrador"


class CodigoInvitacion(BaseModel):
    codigo: str = Field(min_length=4, max_length=20)


def _quitar_miembro(id_grupo: int, id_usuario: int) -> None:
    """Saca al vecino y borra sus avisos del grupo: dejan de mostrarle reportes que ya no puede abrir."""
    with transaccion() as cursor:
        cursor.execute(
            "DELETE FROM grupo_miembro WHERE id_grupo = %s AND id_usuario = %s",
            (id_grupo, id_usuario),
        )
        cursor.execute(
            "DELETE FROM notificacion WHERE id_usuario = %s AND id_grupo = %s AND motivo = 'GRUPO'",
            (id_usuario, id_grupo),
        )


@router.get("/invitacion/{codigo}")
def ver_invitacion(codigo: str, usuario: dict = Depends(usuario_actual)):
    """Vista previa antes de unirse. No muestra el centro exacto: a quien
    todavía no es miembro no se le revela dónde viven los vecinos."""
    filas = consultar(
        """
        SELECT g.id_grupo, g.nombre, g.descripcion, g.radio_metros,
               (SELECT COUNT(*) FROM grupo_miembro t WHERE t.id_grupo = g.id_grupo) AS total_miembros,
               EXISTS(
                   SELECT 1 FROM grupo_miembro m
                   WHERE m.id_grupo = g.id_grupo AND m.id_usuario = %s
               ) AS ya_es_miembro
        FROM grupo g
        WHERE g.codigo_invitacion = %s AND g.activo = 1 AND g.codigo_expira > NOW()
        """,
        (usuario["id_usuario"], normalizar_codigo(codigo)),
    )
    if not filas:
        raise HTTPException(status_code=404, detail=MENSAJE_CODIGO_INVALIDO)
    fila = filas[0]
    return {
        "id_grupo": fila["id_grupo"],
        "nombre": fila["nombre"],
        "descripcion": fila["descripcion"],
        "radio_metros": int(fila["radio_metros"]),
        "total_miembros": int(fila["total_miembros"]),
        "ya_es_miembro": bool(fila["ya_es_miembro"]),
    }


@router.post("/unirse")
def unirse(datos: CodigoInvitacion, usuario: dict = Depends(usuario_actual)):
    """Ingreso automático con un código vigente."""
    id_usuario = usuario["id_usuario"]
    filas = consultar(
        """
        SELECT id_grupo FROM grupo
        WHERE codigo_invitacion = %s AND activo = 1 AND codigo_expira > NOW()
        """,
        (normalizar_codigo(datos.codigo),),
    )
    if not filas:
        raise HTTPException(status_code=404, detail=MENSAJE_CODIGO_INVALIDO)
    id_grupo = filas[0]["id_grupo"]

    exigir_cupo(id_usuario, "unirte a otro")
    try:
        ejecutar(
            "INSERT INTO grupo_miembro (id_grupo, id_usuario, rol) VALUES (%s, %s, 'MIEMBRO')",
            (id_grupo, id_usuario),
        )
    except mysql.connector.Error as error:
        # uq_grupo_usuario: ya era miembro.
        if es_duplicado(error):
            raise HTTPException(status_code=409, detail="Ya eres parte de este grupo") from error
        raise error_bd(error, "No se pudo unir al grupo. Inténtalo otra vez") from error
    return grupo_de_usuario(id_grupo, id_usuario)


@router.get("/{id_grupo}/miembros")
def listar_miembros(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """Miembros con su alias del grupo; el nombre real nunca sale de la API."""
    id_usuario = usuario["id_usuario"]
    membresia(id_grupo, id_usuario)
    filas = consultar(
        """
        SELECT id_miembro, id_usuario, rol, fecha_union
        FROM grupo_miembro WHERE id_grupo = %s
        ORDER BY rol = 'ADMIN' DESC, fecha_union
        """,
        (id_grupo,),
    )
    return [
        {
            "id_miembro": fila["id_miembro"],
            "alias": alias_miembro(id_grupo, fila["id_usuario"]),
            "rol": fila["rol"],
            "soy_yo": fila["id_usuario"] == id_usuario,
            "fecha_union": iso(fila["fecha_union"]),
        }
        for fila in filas
    ]


@router.delete("/{id_grupo}/miembros/{id_miembro}", status_code=204)
def expulsar_miembro(
    id_grupo: int = PathParam(ge=1),
    id_miembro: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """El admin expulsa a un vecino. Para que no vuelva a entrar, conviene regenerar el código."""
    exigir_admin(id_grupo, usuario["id_usuario"])
    filas = consultar(
        "SELECT id_usuario, rol FROM grupo_miembro WHERE id_miembro = %s AND id_grupo = %s",
        (id_miembro, id_grupo),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Ese vecino ya no está en el grupo")
    if filas[0]["rol"] == "ADMIN":
        raise HTTPException(status_code=409, detail="El administrador no puede expulsarse a sí mismo")
    _quitar_miembro(id_grupo, filas[0]["id_usuario"])
    return None


@router.post("/{id_grupo}/salir", status_code=204)
def salir_del_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    if membresia(id_grupo, usuario["id_usuario"])["rol"] == "ADMIN":
        raise HTTPException(status_code=409, detail="Eres el administrador: si quieres irte, elimina el grupo")
    _quitar_miembro(id_grupo, usuario["id_usuario"])
    return None
