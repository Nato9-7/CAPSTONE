"""Copia periódica de MySQL a Neo4j para el panel de administración.

MySQL sigue siendo la base principal: aquí solo se arma, cada cierto tiempo, un grafo
con quién reportó qué, quién votó qué, en qué calle y sector pasó y a qué zonas seguras
avisó. Sirve para el análisis del panel: calles y sectores con más hechos, cómo cambian
en el tiempo y qué categorías se concentran en cada lugar.

En el grafo no se guardan nombres, correos, RUT ni teléfonos: cada usuario aparece con
un seudónimo fijo ("Vecino 3fa2c1").
"""

import hashlib
import logging
import os
import threading
from datetime import datetime

import mysql.connector

from app.db import consultar
from app.seguridad import es_correo_admin
from app.servicios import incidentes
from app.servicios.grafo.conexion import BASE_DE_DATOS, GrafoNoDisponible, grafo_configurado, obtener_driver

log = logging.getLogger("rb_alertas.grafo")


def _minutos_entre_sincronizaciones() -> int:
    try:
        return max(1, int(os.getenv("GRAFO_MINUTOS_SINCRONIZACION", "10")))
    except ValueError:
        log.warning("GRAFO_MINUTOS_SINCRONIZACION no es un entero válido; se usan 10 minutos")
        return 10


MINUTOS_ENTRE_SINCRONIZACIONES = _minutos_entre_sincronizaciones()

_bloqueo = threading.Lock()
ultima_sincronizacion: dict = {"fecha": None, "error": None, "totales": None}


def seudonimo(id_usuario: int) -> str:
    """Nombre fijo y no reversible para mostrar a un usuario en el grafo."""
    return "Vecino " + hashlib.sha256(f"vecino:{id_usuario}".encode()).hexdigest()[:6]


def _texto_fecha(valor) -> str | None:
    return valor.isoformat() if isinstance(valor, datetime) else valor


def _opcional(sql: str) -> list[dict]:
    """Tablas que pueden no existir en una base antigua: el grafo se arma igual sin ellas."""
    try:
        return consultar(sql)
    except mysql.connector.Error as error:
        log.warning("Se omite una tabla al armar el grafo: %s", error.msg)
        return []


def _usuarios_y_reportes() -> tuple[list[dict], list[dict], list[dict]]:
    usuarios = consultar("SELECT id_usuario, email, estado, email_verificado, fecha_creacion FROM usuario")
    for u in usuarios:
        u["alias"] = seudonimo(u["id_usuario"])
        u["es_admin"] = es_correo_admin(u.pop("email"))
        u["email_verificado"] = bool(u["email_verificado"])
        u["fecha_creacion"] = _texto_fecha(u["fecha_creacion"])

    sql_reportes = """
        SELECT r.id_reporte, r.id_usuario, r.id_categoria, r.id_comuna, r.id_localidad, r.estado,
               LEFT(r.descripcion, 120) AS descripcion, r.direccion_referencia AS direccion, {calle} AS calle,
               r.fecha_creacion, (r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()) AS vencido,
               r.total_confirmaciones, r.total_desmentidos, c.codigo AS categoria_codigo, r.visibilidad,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        """
    try:
        reportes = consultar(sql_reportes.format(calle="r.calle"))
    except mysql.connector.Error as error:
        # Base sin la migración sql/calle_reporte.sql: el grafo se arma sin calles.
        log.warning("Se arma el grafo sin calles: %s", error.msg)
        reportes = consultar(sql_reportes.format(calle="NULL"))
    for r in reportes:
        r["latitud"] = float(r["latitud"]) if r["latitud"] is not None else None
        r["longitud"] = float(r["longitud"]) if r["longitud"] is not None else None
    votos = consultar("SELECT id_reporte, id_usuario, tipo_voto, fecha_voto FROM reporte_voto")
    return usuarios, reportes, votos


def id_calle(nombre: str, id_comuna: int | None) -> int:
    """Id numérico fijo de una calle dentro de su comuna (la misma calle en otra comuna es otra)."""
    clave = f"{id_comuna}:{nombre.strip().lower()}"
    return int(hashlib.sha256(clave.encode()).hexdigest()[:12], 16)


def calles_de_reportes(reportes: list[dict]) -> list[dict]:
    """Una calle por (nombre, comuna) con el punto medio de sus reportes, para ubicarla en el mapa."""
    calles: dict[int, dict] = {}
    for r in reportes:
        if not r.get("calle"):
            continue
        id_c = id_calle(r["calle"], r["id_comuna"])
        r["id_calle"] = id_c
        calle = calles.setdefault(
            id_c, {"id": id_c, "nombre": r["calle"].strip(), "id_comuna": r["id_comuna"], "lat": [], "lon": []}
        )
        if r["latitud"] is not None and r["longitud"] is not None:
            calle["lat"].append(r["latitud"])
            calle["lon"].append(r["longitud"])
    return [
        {
            "id": c["id"],
            "nombre": c["nombre"],
            "id_comuna": c["id_comuna"],
            "latitud": sum(c["lat"]) / len(c["lat"]) if c["lat"] else None,
            "longitud": sum(c["lon"]) / len(c["lon"]) if c["lon"] else None,
        }
        for c in calles.values()
    ]


def _incidentes_para_grafo(reportes: list[dict]) -> list[dict]:
    return [
        {
            "id": g[0]["id_reporte"],
            "ids": [r["id_reporte"] for r in g],
            "total": len(g),
            "inicio": _texto_fecha(g[0]["fecha_creacion"]),
            "fin": _texto_fecha(g[-1]["fecha_creacion"]),
        }
        for g in incidentes.agrupar(reportes)
        if len(g) > 1
    ]


def _filas_mysql() -> dict[str, list[dict]]:
    usuarios, reportes, votos = _usuarios_y_reportes()

    # Reportes del mismo hecho: se agrupan con las fechas todavía como datetime.
    lista_incidentes = _incidentes_para_grafo(reportes)
    calles = calles_de_reportes(reportes)

    for r in reportes:
        r["fecha_creacion"] = _texto_fecha(r["fecha_creacion"])
        r["vencido"] = bool(r["vencido"])

    return {
        "usuarios": usuarios,
        "reportes": reportes,
        "calles": calles,
        "incidentes": lista_incidentes,
        "categorias": consultar("SELECT id_categoria, nombre, codigo, color_hex FROM categoria_incidente"),
        "comunas": consultar("SELECT id_comuna, nombre FROM comuna WHERE id_comuna IN (SELECT DISTINCT id_comuna FROM reporte)"),
        "localidades": consultar(
            "SELECT id_localidad, id_comuna, nombre FROM localidad "
            "WHERE id_localidad IN (SELECT DISTINCT id_localidad FROM reporte WHERE id_localidad IS NOT NULL)"
        ),
        "votos": [{**v, "fecha_voto": _texto_fecha(v["fecha_voto"])} for v in votos],
        "zonas": _opcional("SELECT id_zona_segura, id_usuario, nombre, radio_metros, activa FROM zona_segura"),
        "grupos": _opcional("SELECT id_grupo, nombre, activo, radio_metros FROM grupo"),
        "miembros_grupo": _opcional("SELECT id_grupo, id_usuario, rol FROM grupo_miembro"),
        "reportes_grupo": _opcional("SELECT id_grupo, id_reporte FROM grupo_reporte"),
        "avisos": _opcional(
            "SELECT id_reporte, id_zona_segura, distancia_metros FROM notificacion "
            "WHERE id_zona_segura IS NOT NULL AND id_reporte IS NOT NULL"
        ),
    }


# Se borra y se vuelve a armar todo en una sola transacción: con el volumen de
# RB Alertas tarda poco, y nunca queda un grafo a medias ni datos ya borrados en MySQL.
_CYPHER_RECONSTRUIR = [
    "MATCH (n) DETACH DELETE n",
    """UNWIND $categorias AS c
       CREATE (:Categoria {id: c.id_categoria, nombre: c.nombre, codigo: c.codigo, color: c.color_hex})""",
    """UNWIND $comunas AS c CREATE (:Comuna {id: c.id_comuna, nombre: c.nombre})""",
    """UNWIND $localidades AS l
       MATCH (c:Comuna {id: l.id_comuna})
       CREATE (:Localidad {id: l.id_localidad, nombre: l.nombre})-[:PERTENECE_A]->(c)""",
    """UNWIND $usuarios AS u
       CREATE (:Usuario {id: u.id_usuario, alias: u.alias, estado: u.estado, verificado: u.email_verificado,
                         es_admin: u.es_admin, fecha_creacion: u.fecha_creacion})""",
    """UNWIND $calles AS c
       CREATE (calle:Calle {id: c.id, nombre: c.nombre, latitud: c.latitud, longitud: c.longitud})
       WITH calle, c
       MATCH (com:Comuna {id: c.id_comuna})
       CREATE (calle)-[:EN_COMUNA]->(com)""",
    """UNWIND $reportes AS r
       MATCH (u:Usuario {id: r.id_usuario})
       MATCH (cat:Categoria {id: r.id_categoria})
       CREATE (rep:Reporte {id: r.id_reporte, estado: r.estado, descripcion: r.descripcion, direccion: r.direccion,
                            calle: r.calle, fecha_creacion: r.fecha_creacion, dia: substring(r.fecha_creacion, 0, 10),
                            vencido: r.vencido, latitud: r.latitud, longitud: r.longitud,
                            confirmaciones: r.total_confirmaciones, desmentidos: r.total_desmentidos,
                            categoria: cat.nombre, categoria_codigo: cat.codigo, color: cat.color,
                            visibilidad: r.visibilidad, id_comuna: r.id_comuna})
       CREATE (u)-[:CREO]->(rep)
       CREATE (rep)-[:ES_DE]->(cat)
       WITH rep, r
       OPTIONAL MATCH (calle:Calle {id: r.id_calle})
       FOREACH (_ IN CASE WHEN calle IS NOT NULL THEN [1] ELSE [] END | CREATE (rep)-[:EN_CALLE]->(calle))
       WITH rep, r
       OPTIONAL MATCH (loc:Localidad {id: r.id_localidad})
       OPTIONAL MATCH (com:Comuna {id: r.id_comuna})
       FOREACH (_ IN CASE WHEN loc IS NOT NULL THEN [1] ELSE [] END | CREATE (rep)-[:OCURRIO_EN]->(loc))
       FOREACH (_ IN CASE WHEN loc IS NULL AND com IS NOT NULL THEN [1] ELSE [] END | CREATE (rep)-[:OCURRIO_EN]->(com))""",
    """UNWIND $votos AS v
       MATCH (u:Usuario {id: v.id_usuario}), (r:Reporte {id: v.id_reporte})
       CREATE (u)-[:VOTO {tipo: v.tipo_voto, fecha: v.fecha_voto}]->(r)""",
    """UNWIND $zonas AS z
       MATCH (u:Usuario {id: z.id_usuario})
       CREATE (u)-[:TIENE_ZONA]->(:ZonaSegura {id: z.id_zona_segura, nombre: z.nombre,
                                              radio: z.radio_metros, activa: z.activa = 1})""",
    """UNWIND $avisos AS a
       MATCH (r:Reporte {id: a.id_reporte}), (z:ZonaSegura {id: a.id_zona_segura})
       CREATE (r)-[:ALERTO_A {distancia: a.distancia_metros}]->(z)""",
    """UNWIND $grupos AS g
       CREATE (:Grupo {id: g.id_grupo, nombre: g.nombre, activo: g.activo = 1, radio: g.radio_metros})""",
    """UNWIND $miembros_grupo AS m
       MATCH (u:Usuario {id: m.id_usuario}), (g:Grupo {id: m.id_grupo})
       CREATE (u)-[:INTEGRA {rol: m.rol}]->(g)""",
    """UNWIND $reportes_grupo AS x
       MATCH (r:Reporte {id: x.id_reporte}), (g:Grupo {id: x.id_grupo})
       CREATE (r)-[:COMPARTIDO_EN]->(g)""",
    # Reportes del mismo hecho.
    """UNWIND $incidentes AS i
       MATCH (primero:Reporte {id: i.id})
       CREATE (inc:Incidente {id: i.id, total: i.total, inicio: i.inicio, fin: i.fin,
                              categoria: primero.categoria, categoria_codigo: primero.categoria_codigo,
                              color: primero.color, direccion: primero.direccion})
       WITH inc, i
       UNWIND i.ids AS id_reporte
       MATCH (r:Reporte {id: id_reporte})
       CREATE (inc)-[:AGRUPA]->(r)""",
]

_CYPHER_INDICES = [
    f"CREATE INDEX {nombre}_id IF NOT EXISTS FOR (n:{etiqueta}) ON (n.id)"
    for nombre, etiqueta in (
        ("usuario", "Usuario"), ("reporte", "Reporte"), ("categoria", "Categoria"), ("comuna", "Comuna"),
        ("localidad", "Localidad"), ("zona", "ZonaSegura"), ("calle", "Calle"),
        ("incidente", "Incidente"), ("grupo", "Grupo"),
    )
] + ["CREATE INDEX reporte_dia IF NOT EXISTS FOR (r:Reporte) ON (r.dia)"]


def _reconstruir_en_neo4j(datos: dict) -> None:
    from neo4j.exceptions import Neo4jError, ServiceUnavailable

    driver = obtener_driver()
    try:
        for indice in _CYPHER_INDICES:
            driver.execute_query(indice, database_=BASE_DE_DATOS)
        with driver.session(database=BASE_DE_DATOS) as sesion:
            sesion.execute_write(
                lambda tx: [tx.run(cypher, datos).consume() for cypher in _CYPHER_RECONSTRUIR]
            )
    except (ServiceUnavailable, Neo4jError) as error:
        raise GrafoNoDisponible(f"No se pudo actualizar el grafo en Neo4j: {error}") from error


def sincronizar() -> dict:
    """Rehace el grafo con los datos actuales de MySQL. Devuelve cuántos nodos de cada tipo quedaron."""
    with _bloqueo:
        try:
            datos = _filas_mysql()
            _reconstruir_en_neo4j(datos)
            totales = {clave: len(filas) for clave, filas in datos.items()}
            ultima_sincronizacion.update(fecha=datetime.now().isoformat(timespec="seconds"), error=None, totales=totales)
            log.info("Grafo sincronizado: %s", totales)
            return totales
        except Exception as error:
            ultima_sincronizacion["error"] = str(error)
            raise


def sincronizar_sin_fallar() -> None:
    """Rehace el grafo tras una moderación. El cambio en MySQL ya quedó hecho:
    si Neo4j no está disponible solo se registra el aviso."""
    if not grafo_configurado():
        return
    try:
        sincronizar()
    except Exception as error:  # noqa: BLE001
        log.warning("No se pudo rehacer el grafo tras moderar: %s", error)


def iniciar_sincronizacion_periodica() -> None:
    """Hilo en segundo plano que rehace el grafo cada MINUTOS_ENTRE_SINCRONIZACIONES."""
    if not grafo_configurado():
        log.info("NEO4J_URI no está definido: el grafo del panel queda desactivado")
        return
    detener = threading.Event()

    def ciclo():
        while not detener.is_set():
            try:
                sincronizar()
            except Exception as error:  # el hilo sigue: Neo4j puede estar arrancando
                log.warning("No se pudo sincronizar el grafo: %s", error)
            detener.wait(MINUTOS_ENTRE_SINCRONIZACIONES * 60)

    threading.Thread(target=ciclo, name="sincronizar-grafo", daemon=True).start()
