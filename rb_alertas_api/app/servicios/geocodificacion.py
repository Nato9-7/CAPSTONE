"""Calle de un punto del mapa con Nominatim (OpenStreetMap), para el análisis por calle.

La dirección que envía la app es texto libre ("Tucapel, Puerto Montt", a veces el
barrio o solo coordenadas). Aquí se guarda aparte, en reporte.calle, solo el
nombre de la vía tal como lo tiene OpenStreetMap, para poder contar por calle.

Política de uso de Nominatim: máximo una consulta por segundo e identificarse con
un User-Agent propio. Si el servicio no responde, el reporte queda sin calle y el
script scripts/completar_calles.py lo puede completar más tarde.
"""

import json
import logging
import threading
import time
import urllib.parse
import urllib.request

import mysql.connector

from app.db import ejecutar

log = logging.getLogger("rb_alertas.geocodificacion")

URL_NOMINATIM = "https://nominatim.openstreetmap.org/reverse"
AGENTE = "RBAlertas-API/1.0 (+https://rbalerta.duckdns.org)"
SEGUNDOS_ENTRE_CONSULTAS = 1.1
SEGUNDOS_ESPERA = 8
LARGO_MAXIMO = 150

# Claves de Nominatim que son una vía, de la más a la menos específica.
_CLAVES_VIA = ("road", "pedestrian", "footway", "path", "cycleway", "residential")

_bloqueo = threading.Lock()
_ultima_consulta = 0.0


def calle_de_direccion(direccion: dict) -> str | None:
    """Nombre de la vía dentro de la respuesta `address` de Nominatim (None si no es una vía)."""
    for clave in _CLAVES_VIA:
        valor = (direccion.get(clave) or "").strip()
        if valor:
            return valor[:LARGO_MAXIMO]
    return None


def calle_de_punto(latitud: float, longitud: float) -> str | None:
    """Consulta a Nominatim la calle más cercana al punto. None si no hay o si falla."""
    global _ultima_consulta
    parametros = urllib.parse.urlencode(
        {"format": "jsonv2", "lat": f"{latitud:.6f}", "lon": f"{longitud:.6f}", "zoom": 17, "accept-language": "es"}
    )
    peticion = urllib.request.Request(f"{URL_NOMINATIM}?{parametros}", headers={"User-Agent": AGENTE})
    with _bloqueo:
        espera = SEGUNDOS_ENTRE_CONSULTAS - (time.monotonic() - _ultima_consulta)
        if espera > 0:
            time.sleep(espera)
        try:
            with urllib.request.urlopen(peticion, timeout=SEGUNDOS_ESPERA) as respuesta:
                cuerpo = json.loads(respuesta.read().decode("utf-8"))
        except (OSError, ValueError) as error:
            log.warning("No se pudo obtener la calle de (%s, %s): %s", latitud, longitud, error)
            return None
        finally:
            _ultima_consulta = time.monotonic()
    return calle_de_direccion(cuerpo.get("address") or {})


def completar_calle(id_reporte: int, latitud: float, longitud: float) -> str | None:
    """Guarda la calle del reporte (tarea en segundo plano tras crearlo)."""
    calle = calle_de_punto(latitud, longitud)
    if calle:
        try:
            ejecutar("UPDATE reporte SET calle = %s WHERE id_reporte = %s AND calle IS NULL", (calle, id_reporte))
        except mysql.connector.Error as error:
            # Base sin la migración sql/calle_reporte.sql: el reporte sigue igual.
            log.warning("No se pudo guardar la calle del reporte #%s: %s", id_reporte, error.msg)
            return None
    return calle
