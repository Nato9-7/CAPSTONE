"""Zonas de riesgo para el mapa: lugares donde se repiten robos y hechos parecidos.

Se calcula al consultar a partir de los reportes de los últimos días:

1. Solo cuentan las categorías que hablan del lugar y no de un hecho aislado:
   seguridad (robos, asaltos, actividad sospechosa...) y vial (accidentes,
   problemas en la vía). Un incendio o una mascota perdida no hacen peligrosa
   una calle.
2. Los reportes del mismo hecho se juntan en un incidente (app/servicios/incidentes.py):
   cinco vecinos reportando el mismo robo son un robo, no cinco.
3. Los incidentes a menos de RADIO_ZONA_METROS entre sí forman una zona. Si la
   zona tiene al menos MINIMO_INCIDENTES, se muestra con su recomendación.

No se guarda nada en la base ni se expone quién reportó: solo el centro, el
radio y cuántos hechos hubo de cada categoría.
"""

import os
from datetime import datetime

from app.servicios.incidentes import agrupar, distancia_metros

RADIO_ZONA_METROS = float(os.getenv("ZONA_RIESGO_RADIO_METROS", "250"))
MINIMO_INCIDENTES = int(os.getenv("ZONA_RIESGO_MINIMO", "2"))
INCIDENTES_NIVEL_ALTO = int(os.getenv("ZONA_RIESGO_NIVEL_ALTO", "4"))

# El círculo dibujado nunca es más chico que esto (un solo punto no se vería)
# ni más grande que lo otro (una cadena de hechos no pinta media ciudad).
RADIO_MINIMO_DIBUJO = 120.0
RADIO_MAXIMO_DIBUJO = 600.0

# Horas de noche: de 20:00 a 06:59.
HORA_INICIO_NOCHE = 20
HORA_FIN_NOCHE = 7

# Palabras del código de categoría que la hacen contar. Se busca por palabra
# para que una categoría nueva (VANDALISMO, RIÑA...) cuente sin tocar código.
_PALABRAS_SEGURIDAD = ("ROBO", "ASALTO", "HURTO", "SOSPECH", "VANDAL", "VIOLEN", "RINA", "DROGA", "AGRESION")
_PALABRAS_VIAL = ("ACCIDENTE", "VIAL", "CHOQUE", "ATROPELL")


def tipo_riesgo(codigo: str) -> str | None:
    """'SEGURIDAD', 'VIAL' o None si la categoría no marca zonas de riesgo."""
    c = (codigo or "").upper()
    if any(p in c for p in _PALABRAS_SEGURIDAD):
        return "SEGURIDAD"
    if any(p in c for p in _PALABRAS_VIAL):
        return "VIAL"
    return None


def _fecha(valor) -> datetime:
    return valor if isinstance(valor, datetime) else datetime.fromisoformat(str(valor))


def _es_de_noche(fecha: datetime) -> bool:
    return fecha.hour >= HORA_INICIO_NOCHE or fecha.hour < HORA_FIN_NOCHE


def _juntar_cercanos(incidentes: list[dict]) -> list[list[dict]]:
    """Grupos de incidentes encadenados a menos de RADIO_ZONA_METROS."""
    padre = list(range(len(incidentes)))

    def raiz(i: int) -> int:
        while padre[i] != i:
            padre[i] = padre[padre[i]]
            i = padre[i]
        return i

    for i in range(len(incidentes)):
        for j in range(i + 1, len(incidentes)):
            a, b = incidentes[i], incidentes[j]
            if distancia_metros(a["latitud"], a["longitud"], b["latitud"], b["longitud"]) <= RADIO_ZONA_METROS:
                padre[raiz(i)] = raiz(j)

    grupos: dict[int, list[dict]] = {}
    for i, incidente in enumerate(incidentes):
        grupos.setdefault(raiz(i), []).append(incidente)
    return list(grupos.values())


def recomendacion(tipo: str, nivel: str, de_noche: bool) -> str:
    if tipo == "SEGURIDAD":
        base = "Evita transitar por aquí" if nivel == "ALTO" else "Transita con precaución por aquí"
        return base + (", sobre todo de noche." if de_noche else ".") + \
            " Si debes pasar, hazlo acompañado, por calles iluminadas y sin exponer tu celular."
    return ("Zona con accidentes frecuentes: " if nivel == "ALTO" else "Se han reportado problemas en la vía: ") + \
        "reduce la velocidad y cruza solo por pasos peatonales."


def calcular(reportes: list[dict]) -> list[dict]:
    """Zonas de riesgo a partir de reportes, de la más riesgosa a la menos.

    Cada reporte necesita id_reporte, categoria_codigo, categoria, color_hex,
    latitud, longitud y fecha_creacion. Los de categorías que no marcan riesgo
    se ignoran.
    """
    incidentes = []
    for grupo in agrupar([r for r in reportes if tipo_riesgo(r["categoria_codigo"])]):
        primero = grupo[0]
        incidentes.append({
            "codigo": primero["categoria_codigo"],
            "nombre": primero["categoria"],
            "color_hex": primero.get("color_hex"),
            "tipo": tipo_riesgo(primero["categoria_codigo"]),
            "latitud": sum(float(r["latitud"]) for r in grupo) / len(grupo),
            "longitud": sum(float(r["longitud"]) for r in grupo) / len(grupo),
            "fecha": _fecha(primero["fecha_creacion"]),
            "ultima": _fecha(grupo[-1]["fecha_creacion"]),
        })

    zonas = []
    # Seguridad y vial son zonas distintas: una calle con choques no es una
    # calle con asaltos, y la recomendación es otra.
    for tipo in ("SEGURIDAD", "VIAL"):
        del_tipo = [i for i in incidentes if i["tipo"] == tipo]
        for grupo in _juntar_cercanos(del_tipo):
            if len(grupo) < MINIMO_INCIDENTES:
                continue
            lat = sum(i["latitud"] for i in grupo) / len(grupo)
            lng = sum(i["longitud"] for i in grupo) / len(grupo)
            lejania = max(distancia_metros(lat, lng, i["latitud"], i["longitud"]) for i in grupo)
            radio = min(RADIO_MAXIMO_DIBUJO, max(RADIO_MINIMO_DIBUJO, lejania + 80))

            por_categoria: dict[str, dict] = {}
            for i in grupo:
                c = por_categoria.setdefault(
                    i["codigo"], {"codigo": i["codigo"], "nombre": i["nombre"], "color_hex": i["color_hex"], "total": 0}
                )
                c["total"] += 1

            nivel = "ALTO" if len(grupo) >= INCIDENTES_NIVEL_ALTO else "MEDIO"
            nocturnos = sum(1 for i in grupo if _es_de_noche(i["fecha"]))
            de_noche = nocturnos * 2 >= len(grupo)
            zonas.append({
                "tipo": tipo,
                "nivel": nivel,
                "latitud": round(lat, 6),
                "longitud": round(lng, 6),
                "radio_metros": round(radio),
                "total_incidentes": len(grupo),
                "incidentes_de_noche": nocturnos,
                "por_categoria": sorted(por_categoria.values(), key=lambda c: -c["total"]),
                "ultimo_incidente": max(i["ultima"] for i in grupo).isoformat(),
                "recomendacion": recomendacion(tipo, nivel, de_noche),
            })

    # Primero seguridad, luego las de más hechos.
    zonas.sort(key=lambda z: (z["tipo"] != "SEGURIDAD", z["nivel"] != "ALTO", -z["total_incidentes"]))
    return zonas


# Celda a la que se redondea el centro de cada mancha: ~110 m por lado en
# Puerto Montt (en la latitud -41°, un grado de longitud mide ~84 km). Se
# entrega la celda y no el punto exacto para no delatar dónde vive quien reporta.
CELDA_LATITUD = 0.001
CELDA_LONGITUD = 0.0013

# Tamaño de la mancha: dos hechos se ven con RADIO_CALOR_BASE y cada hecho
# más que se junta la agranda, hasta RADIO_MAXIMO_DIBUJO.
RADIO_CALOR_BASE = 150.0
RADIO_CALOR_POR_HECHO = 60.0

# Una mancha de un solo hecho podría insinuar dónde vive quien lo reportó.
MINIMO_HECHOS_CALOR = int(os.getenv("CALOR_MINIMO_HECHOS", "2"))

# Peso de cada hecho en la intensidad de su mancha:
# - Gravedad: nivel_gravedad de su categoría dividido por GRAVEDAD_REFERENCIA
#   (un robo o un accidente, nivel 4, vale 1; un problema en la vía, nivel 2, vale 0,5).
# - Antigüedad: pierde la mitad de su peso cada VIDA_MEDIA_DIAS.
GRAVEDAD_REFERENCIA = 4.0
VIDA_MEDIA_DIAS = float(os.getenv("CALOR_VIDA_MEDIA_DIAS", "15"))


def peso_hecho(nivel_gravedad, fecha: datetime, ahora: datetime) -> float:
    """Cuánto aporta un hecho a la intensidad de su mancha."""
    gravedad = (float(nivel_gravedad) if nivel_gravedad is not None else GRAVEDAD_REFERENCIA) / GRAVEDAD_REFERENCIA
    edad_dias = max(0.0, (ahora - fecha).total_seconds() / 86_400)
    return gravedad * 0.5 ** (edad_dias / VIDA_MEDIA_DIAS)


def puntos_calor(reportes: list[dict], ahora: datetime | None = None) -> list[dict]:
    """Manchas del mapa de calor, de la más intensa a la menos.

    Cuentan las mismas categorías que las zonas de riesgo (ver tipo_riesgo). Los
    reportes del mismo hecho cuentan una vez y los hechos a menos de
    RADIO_ZONA_METROS entre sí se juntan en una mancha centrada entre ellos.
    Solo se entregan las manchas con al menos MINIMO_HECHOS_CALOR hechos.

    `intensidad` es la suma de los pesos de sus hechos (ver peso_hecho): la app
    la pinta con una escala fija, así el mismo color significa lo mismo siempre.
    """
    ahora = ahora or datetime.now()
    elegidos = [r for r in reportes if tipo_riesgo(r["categoria_codigo"])]

    incidentes = []
    for grupo in agrupar(elegidos):
        primero = grupo[0]
        incidentes.append({
            "codigo": primero["categoria_codigo"].upper(),
            "tipo": tipo_riesgo(primero["categoria_codigo"]),
            "latitud": sum(float(r["latitud"]) for r in grupo) / len(grupo),
            "longitud": sum(float(r["longitud"]) for r in grupo) / len(grupo),
            # El hecho se fecha por su último reporte: si lo siguen reportando, sigue vigente.
            "peso": peso_hecho(primero.get("nivel_gravedad"), _fecha(grupo[-1]["fecha_creacion"]), ahora),
        })

    puntos = []
    for grupo in _juntar_cercanos(incidentes):
        if len(grupo) < MINIMO_HECHOS_CALOR:
            continue
        lat = sum(i["latitud"] for i in grupo) / len(grupo)
        lng = sum(i["longitud"] for i in grupo) / len(grupo)
        lejania = max(distancia_metros(lat, lng, i["latitud"], i["longitud"]) for i in grupo)
        crecido = RADIO_CALOR_BASE + RADIO_CALOR_POR_HECHO * (len(grupo) - MINIMO_HECHOS_CALOR)
        radio = min(RADIO_MAXIMO_DIBUJO, max(crecido, lejania + 80))
        robos = sum(1 for i in grupo if i["tipo"] == "SEGURIDAD")
        accidentes = sum(1 for i in grupo if i["codigo"] == "ACCIDENTE")
        puntos.append({
            "latitud": round(round(lat / CELDA_LATITUD) * CELDA_LATITUD, 6),
            "longitud": round(round(lng / CELDA_LONGITUD) * CELDA_LONGITUD, 6),
            "peso": len(grupo),
            "intensidad": round(sum(i["peso"] for i in grupo), 2),
            "robos": robos,
            "accidentes": accidentes,
            "viales": len(grupo) - robos - accidentes,
            # Se mantiene por compatibilidad con clientes anteriores.
            "seguridad": robos,
            "radio_metros": round(radio),
        })
    puntos.sort(key=lambda p: -p["intensidad"])
    return puntos
