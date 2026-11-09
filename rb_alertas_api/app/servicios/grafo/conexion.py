"""Conexión con Neo4j. Sin NEO4J_URI la API funciona igual y el grafo responde que no está disponible."""

import logging
import os

log = logging.getLogger("rb_alertas.grafo")

NEO4J_URI = os.getenv("NEO4J_URI", "")
NEO4J_USUARIO = os.getenv("NEO4J_USER", "neo4j")
NEO4J_CLAVE = os.getenv("NEO4J_PASSWORD", "")
BASE_DE_DATOS = "neo4j"

_driver = None


class GrafoNoDisponible(Exception):
    pass


def grafo_configurado() -> bool:
    return bool(NEO4J_URI and NEO4J_CLAVE)


def obtener_driver():
    """Driver de Neo4j, creado una sola vez.

    La librería se importa aquí para que la API arranque aunque no esté instalada.
    """
    global _driver
    if not grafo_configurado():
        raise GrafoNoDisponible("El grafo no está configurado en el servidor (faltan las variables NEO4J_*)")
    if _driver is None:
        from neo4j import GraphDatabase

        # Sin avisos informativos (p. ej. "ese tipo de relación aún no existe" cuando no hay datos).
        _driver = GraphDatabase.driver(
            NEO4J_URI, auth=(NEO4J_USUARIO, NEO4J_CLAVE), notifications_min_severity="OFF"
        )
    return _driver


def consultar_grafo(cypher: str, **parametros) -> list[dict]:
    from neo4j.exceptions import Neo4jError, ServiceUnavailable

    try:
        registros, _, _ = obtener_driver().execute_query(cypher, parametros, database_=BASE_DE_DATOS)
    except ServiceUnavailable as error:
        raise GrafoNoDisponible("No se pudo conectar con Neo4j") from error
    except Neo4jError as error:
        log.error("Consulta al grafo falló: %s", error)
        raise GrafoNoDisponible("La consulta al grafo falló") from error
    return [registro.data() for registro in registros]
