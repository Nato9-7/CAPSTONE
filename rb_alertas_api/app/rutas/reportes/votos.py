"""Votos de la comunidad (confirmar o desmentir) y cierre del reporte por su autor."""

from typing import Literal

import mysql.connector
from fastapi import APIRouter, Depends, HTTPException, Path as PathParam
from pydantic import BaseModel

from app.comun.sql import error_bd
from app.db import consultar, ejecutar, transaccion
from app.seguridad import usuario_actual
from app.servicios.reportes import ESTADOS_VIGENTES, cambiar_estado, exigir_visible, verificar_acceso_reporte

router = APIRouter()


class VotoReporte(BaseModel):
    tipo_voto: Literal["CONFIRMA", "DESMIENTE"]


def _reporte_votable(id_reporte: int, id_usuario: int) -> dict:
    """Valida que el reporte admita votos de este usuario y lo devuelve."""
    filas = consultar(
        """
        SELECT id_usuario, estado, visibilidad,
               (fecha_expiracion IS NOT NULL AND fecha_expiracion <= NOW()) AS vencido
        FROM reporte WHERE id_reporte = %s
        """,
        (id_reporte,),
    )
    reporte = exigir_visible(filas[0] if filas else None, id_reporte, id_usuario)
    if reporte["id_usuario"] == id_usuario:
        raise HTTPException(status_code=403, detail="No puedes votar tu propio reporte")
    if reporte["estado"] not in ESTADOS_VIGENTES or reporte["vencido"]:
        raise HTTPException(status_code=409, detail="Este reporte ya no admite votos")
    return reporte


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
        raise error_bd(error, "No se pudo registrar tu voto. Inténtalo otra vez") from error
    return _resumen_votos(id_reporte, datos.tipo_voto)


@router.delete("/{id_reporte}/voto")
def quitar_voto(
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Retira el voto propio. Si no había voto, responde igual (operación idempotente)."""
    verificar_acceso_reporte(id_reporte, usuario["id_usuario"])
    ejecutar(
        "DELETE FROM reporte_voto WHERE id_reporte = %s AND id_usuario = %s",
        (id_reporte, usuario["id_usuario"]),
    )
    return _resumen_votos(id_reporte, None)


@router.post("/{id_reporte}/resolver")
def resolver_reporte(
    id_reporte: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """Quien creó el reporte lo marca como resuelto; el cambio queda en reporte_estado_historial."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_usuario, estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (id_reporte,))
        reporte = cursor.fetchone()
        if reporte is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        if reporte["id_usuario"] != usuario["id_usuario"]:
            raise HTTPException(status_code=403, detail="Solo quien creó el reporte puede marcarlo como resuelto")
        if reporte["estado"] not in ESTADOS_VIGENTES:
            raise HTTPException(status_code=409, detail=f"Este reporte ya está {reporte['estado'].lower()}")
        cambiar_estado(
            cursor, id_reporte, reporte["estado"], "RESUELTO", usuario["id_usuario"],
            "Marcado como resuelto por quien lo reportó",
        )
    return {"id_reporte": id_reporte, "estado": "RESUELTO"}
