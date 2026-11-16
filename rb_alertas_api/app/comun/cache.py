"""Caché en memoria con vencimiento, para cálculos caros que se repiten igual.

Vive en cada proceso de la API: si corren varios, cada uno tiene la suya y un
cambio solo la vacía en el proceso que lo atendió; en los demás, el resultado
anterior dura como máximo el tiempo de vencimiento.
"""

import os
import threading
import time
from collections.abc import Callable, Hashable
from typing import Any


class CacheTemporal:
    def __init__(self, segundos: float):
        self._segundos = segundos
        self._datos: dict[Hashable, tuple[float, Any]] = {}
        self._candado = threading.Lock()

    def obtener(self, clave: Hashable, calcular: Callable[[], Any]) -> Any:
        """Valor guardado para [clave] si no venció; si no, lo calcula y lo guarda.

        El cálculo ocurre con el candado tomado: si llegan varias consultas a la
        vez, solo una consulta la base y las demás reciben su resultado.
        """
        with self._candado:
            guardado = self._datos.get(clave)
            if guardado is not None and time.monotonic() < guardado[0]:
                return guardado[1]
            valor = calcular()
            self._datos[clave] = (time.monotonic() + self._segundos, valor)
            return valor

    def vaciar(self) -> None:
        with self._candado:
            self._datos.clear()


# Zonas de riesgo y mapa de calor: se vacía cada vez que se crea, cambia de
# estado o se elimina un reporte, así un hecho nuevo se ve al instante.
cache_mapa = CacheTemporal(float(os.getenv("CACHE_MAPA_SEGUNDOS", "300")))
