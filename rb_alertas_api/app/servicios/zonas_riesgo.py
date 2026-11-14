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


# Categorías del mapa de calor: solo robos y accidentes de tránsito.
CATEGORIAS_CALOR = ("ROBO", "ACCIDENTE")

# Celda a la que se redondea el centro de cada mancha: ~110 m por lado en
# Puerto Montt (en la latitud -41°, un grado de longitud mide ~84 km). Se
# entrega la celda y no el punto exacto para no delatar dónde vive quien reporta.
CELDA_LATITUD = 0.001
CELDA_LONGITUD = 0.0013

# Tamaño de la mancha: un hecho solo se ve con RADIO_CALOR_BASE y cada hecho
# más que se junta la agranda, hasta RADIO_MAXIMO_DIBUJO.
RADIO_CALOR_BASE = 150.0
RADIO_CALOR_POR_HECHO = 60.0


def puntos_calor(reportes: list[dict]) -> list[dict]:
    """Manchas del mapa de calor, de la más grande a la más chica.

    Solo cuentan robos y accidentes de tránsito. Los reportes del mismo hecho
    cuentan una vez y los hechos a menos de RADIO_ZONA_METROS entre sí se
    juntan en una sola mancha centrada entre ellos, que crece con cuántos son
    (en vez de dibujar cada hecho por separado).
    """
    elegidos = [r for r in reportes if (r["categoria_codigo"] or "").upper() in CATEGORIAS_CALOR]

    incidentes = []
    for grupo in agrupar(elegidos):
        incidentes.append({
            "codigo": grupo[0]["categoria_codigo"].upper(),
            "latitud": sum(float(r["latitud"]) for r in grupo) / len(grupo),
            "longitud": sum(float(r["longitud"]) for r in grupo) / len(grupo),
        })

    puntos = []
    for grupo in _juntar_cercanos(incidentes):
        lat = sum(i["latitud"] for i in grupo) / len(grupo)
        lng = sum(i["longitud"] for i in grupo) / len(grupo)
        lejania = max(distancia_metros(lat, lng, i["latitud"], i["longitud"]) for i in grupo)
        crecido = RADIO_CALOR_BASE + RADIO_CALOR_POR_HECHO * (len(grupo) - 1)
        radio = min(RADIO_MAXIMO_DIBUJO, max(crecido, lejania + 80))
        robos = sum(1 for i in grupo if i["codigo"] == "ROBO")
        puntos.append({
            "latitud": round(round(lat / CELDA_LATITUD) * CELDA_LATITUD, 6),
            "longitud": round(round(lng / CELDA_LONGITUD) * CELDA_LONGITUD, 6),
            "peso": len(grupo),
            "robos": robos,
            "accidentes": len(grupo) - robos,
            # Se mantiene por compatibilidad con clientes anteriores.
            "seguridad": robos,
            "radio_metros": round(radio),
        })
    puntos.sort(key=lambda p: -p["peso"])
    return puntos
