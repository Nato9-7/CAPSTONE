"""Copia de los datos de RB Alertas en Neo4j, para el panel de administración.

MySQL sigue siendo la base principal: aquí solo se arma, cada cierto tiempo, un grafo
con quién reportó qué, quién votó qué, dónde pasó y a qué zonas seguras avisó. Sirve
para ver patrones que en una tabla no se notan (cuentas que se confirman entre sí,
quien acumula reportes descartados, lugares con muchos incidentes).

En el grafo no se guardan nombres, correos, RUT ni teléfonos: cada usuario aparece con
un seudónimo fijo ("Vecino 3fa2c1"). Si NEO4J_URI no está definido, la API funciona
igual y solo el grafo responde que no está disponible.
"""

import hashlib
import logging
import os
import threading
from datetime import datetime

from app.db import consultar

log = logging.getLogger("rb_alertas.grafo")

NEO4J_URI = os.getenv("NEO4J_URI", "")
NEO4J_USUARIO = os.getenv("NEO4J_USER", "neo4j")
NEO4J_CLAVE = os.getenv("NEO4J_PASSWORD", "")
MINUTOS_ENTRE_SINCRONIZACIONES = int(os.getenv("GRAFO_MINUTOS_SINCRONIZACION", "10"))

_driver = None
_bloqueo = threading.Lock()
ultima_sincronizacion: dict = {"fecha": None, "error": None, "totales": None}


class GrafoNoDisponible(Exception):
    pass


def grafo_configurado() -> bool:
    return bool(NEO4J_URI and NEO4J_CLAVE)


def _conexion():
    global _driver
    if not grafo_configurado():
        raise GrafoNoDisponible("El grafo no está configurado en el servidor (faltan las variables NEO4J_*)")
    if _driver is None:
        from neo4j import GraphDatabase

        _driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USUARIO, NEO4J_CLAVE))
    return _driver


def consultar_grafo(cypher: str, **parametros) -> list[dict]:
    from neo4j.exceptions import Neo4jError, ServiceUnavailable

    try:
        registros, _, _ = _conexion().execute_query(cypher, parametros, database_="neo4j")
    except ServiceUnavailable as error:
        raise GrafoNoDisponible("No se pudo conectar con Neo4j") from error
    except Neo4jError as error:
        log.error("Consulta al grafo falló: %s", error)
        raise GrafoNoDisponible("La consulta al grafo falló") from error
    return [registro.data() for registro in registros]


def seudonimo(id_usuario: int) -> str:
    """Nombre fijo y no reversible para mostrar a un usuario en el grafo."""
    return "Vecino " + hashlib.sha256(f"vecino:{id_usuario}".encode()).hexdigest()[:6]


# -----------------------------------------------------------------------------
# Sincronización MySQL -> Neo4j

def _filas_mysql() -> dict[str, list[dict]]:
    from app.seguridad import CORREOS_ADMIN

    usuarios = consultar("SELECT id_usuario, email, estado, email_verificado, fecha_creacion FROM usuario")
    for u in usuarios:
        u["alias"] = seudonimo(u["id_usuario"])
        u["es_admin"] = u.pop("email").strip().lower() in CORREOS_ADMIN
        u["email_verificado"] = bool(u["email_verificado"])
        u["fecha_creacion"] = _texto_fecha(u["fecha_creacion"])

    reportes = consultar(
        """
        SELECT id_reporte, id_usuario, id_categoria, id_comuna, id_localidad, estado,
               LEFT(descripcion, 120) AS descripcion, fecha_creacion,
               (fecha_expiracion IS NOT NULL AND fecha_expiracion <= NOW()) AS vencido,
               total_confirmaciones, total_desmentidos
        FROM reporte
        """
    )
    for r in reportes:
        r["fecha_creacion"] = _texto_fecha(r["fecha_creacion"])
        r["vencido"] = bool(r["vencido"])

    return {
        "usuarios": usuarios,
        "reportes": reportes,
        "categorias": consultar("SELECT id_categoria, nombre, codigo, color_hex FROM categoria_incidente"),
        "comunas": consultar("SELECT id_comuna, nombre FROM comuna WHERE id_comuna IN (SELECT DISTINCT id_comuna FROM reporte)"),
        "localidades": consultar(
            "SELECT id_localidad, id_comuna, nombre FROM localidad "
            "WHERE id_localidad IN (SELECT DISTINCT id_localidad FROM reporte WHERE id_localidad IS NOT NULL)"
        ),
        "votos": [
            {**v, "fecha_voto": _texto_fecha(v["fecha_voto"])}
            for v in consultar("SELECT id_reporte, id_usuario, tipo_voto, fecha_voto FROM reporte_voto")
        ],
        "zonas": _opcional("SELECT id_zona_segura, id_usuario, tipo, nombre, radio_metros, activa FROM zona_segura"),
        "avisos": _opcional(
            "SELECT id_reporte, id_zona_segura, distancia_metros FROM notificacion "
            "WHERE id_zona_segura IS NOT NULL AND id_reporte IS NOT NULL"
        ),
    }


def _opcional(sql: str) -> list[dict]:
    """Tablas que pueden no existir en una base antigua: el grafo se arma igual sin ellas."""
    import mysql.connector

    try:
        return consultar(sql)
    except mysql.connector.Error as error:
        log.warning("Se omite una tabla al armar el grafo: %s", error.msg)
        return []


def _texto_fecha(valor) -> str | None:
    return valor.isoformat() if isinstance(valor, datetime) else valor


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
    """UNWIND $reportes AS r
       MATCH (u:Usuario {id: r.id_usuario})
       MATCH (cat:Categoria {id: r.id_categoria})
       CREATE (rep:Reporte {id: r.id_reporte, estado: r.estado, descripcion: r.descripcion,
                            fecha_creacion: r.fecha_creacion, vencido: r.vencido,
                            confirmaciones: r.total_confirmaciones, desmentidos: r.total_desmentidos})
       CREATE (u)-[:CREO]->(rep)
       CREATE (rep)-[:ES_DE]->(cat)
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
       CREATE (u)-[:TIENE_ZONA]->(:ZonaSegura {id: z.id_zona_segura, tipo: z.tipo, nombre: z.nombre,
                                              radio: z.radio_metros, activa: z.activa = 1})""",
    """UNWIND $avisos AS a
       MATCH (r:Reporte {id: a.id_reporte}), (z:ZonaSegura {id: a.id_zona_segura})
       CREATE (r)-[:ALERTO_A {distancia: a.distancia_metros}]->(z)""",
]

_CYPHER_INDICES = [
    "CREATE INDEX usuario_id IF NOT EXISTS FOR (n:Usuario) ON (n.id)",
    "CREATE INDEX reporte_id IF NOT EXISTS FOR (n:Reporte) ON (n.id)",
    "CREATE INDEX categoria_id IF NOT EXISTS FOR (n:Categoria) ON (n.id)",
    "CREATE INDEX comuna_id IF NOT EXISTS FOR (n:Comuna) ON (n.id)",
    "CREATE INDEX localidad_id IF NOT EXISTS FOR (n:Localidad) ON (n.id)",
    "CREATE INDEX zona_id IF NOT EXISTS FOR (n:ZonaSegura) ON (n.id)",
]


def sincronizar() -> dict:
    """Rehace el grafo con los datos actuales de MySQL. Devuelve cuántos nodos de cada tipo quedaron."""
    from neo4j.exceptions import Neo4jError, ServiceUnavailable

    with _bloqueo:
        try:
            datos = _filas_mysql()
            driver = _conexion()
            try:
                for indice in _CYPHER_INDICES:
                    driver.execute_query(indice, database_="neo4j")
                with driver.session(database="neo4j") as sesion:
                    sesion.execute_write(
                        lambda tx: [tx.run(cypher, datos).consume() for cypher in _CYPHER_RECONSTRUIR]
                    )
            except (ServiceUnavailable, Neo4jError) as error:
                raise GrafoNoDisponible(f"No se pudo actualizar el grafo en Neo4j: {error}") from error
            totales = {clave: len(filas) for clave, filas in datos.items()}
            ultima_sincronizacion.update(fecha=datetime.now().isoformat(timespec="seconds"), error=None, totales=totales)
            log.info("Grafo sincronizado: %s", totales)
            return totales
        except Exception as error:
            ultima_sincronizacion["error"] = str(error)
            raise


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
