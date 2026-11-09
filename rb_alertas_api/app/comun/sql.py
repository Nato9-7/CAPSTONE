"""Ayudas para armar consultas y traducir errores de MySQL a respuestas HTTP."""

import logging

import mysql.connector
from fastapi import HTTPException

log = logging.getLogger("rb_alertas.bd")

CLAVE_DUPLICADA = 1062

# SQLSTATE de los SIGNAL que lanzan los triggers con un mensaje pensado para el usuario.
SQLSTATE_MENSAJE_USUARIO = "45000"

MENSAJE_ERROR_GENERICO = "No se pudo guardar la información. Inténtalo otra vez"


def marcas(cantidad: int) -> str:
    """Marcadores "%s, %s, ..." para una cláusula IN con `cantidad` valores."""
    return ", ".join(["%s"] * cantidad)


def es_duplicado(error: mysql.connector.Error) -> bool:
    return error.errno == CLAVE_DUPLICADA


def error_bd(error: mysql.connector.Error, mensaje: str = MENSAJE_ERROR_GENERICO) -> HTTPException:
    """Error 400 para el cliente sin exponer el detalle interno de MySQL.

    Los mensajes de los triggers (SIGNAL SQLSTATE '45000') sí se muestran: están
    escritos para el usuario. El resto queda solo en el registro de la API.
    """
    if error.sqlstate == SQLSTATE_MENSAJE_USUARIO and error.msg:
        return HTTPException(status_code=400, detail=error.msg)
    log.error("Error de base de datos: %s", error)
    return HTTPException(status_code=400, detail=mensaje)
