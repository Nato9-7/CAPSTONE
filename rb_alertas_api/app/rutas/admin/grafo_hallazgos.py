"""Hallazgos del grafo (Neo4j). Los usuarios aparecen con seudónimo.

Cada sección responde una pregunta del administrador:
  - Cuentas sospechosas: ¿hay grupos que se confirman entre ellos para inflar reportes?
  - Reputación: ¿de quién me puedo fiar? (ver app/servicios/analisis_grafo.py)
  - Incidentes: ¿estos reportes son el mismo hecho? (ver app/servicios/incidentes.py)
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.db import transaccion
from app.rutas.admin.errores import grafo_disponible
from app.seguridad import es_correo_admin, usuario_admin
from app.servicios import grafo, moderacion
from app.servicios.grafo.red import nodo
from app.servicios.reportes import cambiar_estado, reportes_del_incidente

router = APIRouter()


class CambioEstadoIncidente(BaseModel):
    estado: Literal["VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


@router.get("/grafo/resumen")
def resumen_grafo():
    """Cuántos casos hay en cada sección, para los contadores de la pestaña."""
    with grafo_disponible():
        fila = grafo.consultar_grafo(
            """
            CALL () { MATCH (c:Coordinacion) RETURN count(c) AS sospechosos }
            CALL () { MATCH (u:Usuario) WHERE u.reputacion < 35 RETURN count(u) AS baja_reputacion }
            CALL () { MATCH (i:Incidente)-[:AGRUPA]->(r:Reporte)
                      WHERE r.estado IN ['PENDIENTE', 'VALIDADO'] AND NOT r.vencido
                      RETURN count(DISTINCT i) AS incidentes_abiertos }
            RETURN sospechosos, baja_reputacion, incidentes_abiertos
            """
        )[0]
    return {**fila, "sincronizacion": grafo.ultima_sincronizacion}


@router.get("/grafo/sospechosos")
def cuentas_sospechosas():
    """Grupos de cuentas que se confirman los reportes entre ellas, del más sospechoso al menos."""
    with grafo_disponible():
        filas = grafo.consultar_grafo(
            """
            MATCH (c:Coordinacion)<-[:MIEMBRO_DE]-(u:Usuario)
            WITH c, u ORDER BY u.alias
            WITH c, collect(properties(u)) AS miembros
            RETURN properties(c) AS grupo, miembros
            ORDER BY c.reciprocidad DESC, c.confirmaciones_internas DESC
            """
        )
        evidencia = grafo.consultar_grafo(
            """
            MATCH (c:Coordinacion)<-[:MIEMBRO_DE]-(a:Usuario)-[v:VOTO {tipo: 'CONFIRMA'}]->(r:Reporte)
                  <-[:CREO]-(b:Usuario)-[:MIEMBRO_DE]->(c)
            WHERE a <> b
            RETURN c.id AS grupo, a.alias AS votante, b.alias AS autor, r.id AS reporte,
                   r.categoria AS categoria, v.fecha AS fecha
            ORDER BY v.fecha DESC
            """
        )
        afuera = grafo.consultar_grafo(
            """
            MATCH (c:Coordinacion)<-[:MIEMBRO_DE]-(a:Usuario)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(b:Usuario)
            WHERE NOT (b)-[:MIEMBRO_DE]->(c) AND a <> b
            RETURN c.id AS grupo, count(*) AS total
            """
        )
    externas = {f["grupo"]: f["total"] for f in afuera}
    return [
        {
            **nodo("Coordinacion", f["grupo"]),
            "miembros": [nodo("Usuario", m) for m in f["miembros"]],
            # Por qué es sospechoso: cada voto dentro del grupo y cuántos dieron afuera.
            "evidencia": [e for e in evidencia if e["grupo"] == f["grupo"]["id"]],
            "confirmaciones_afuera": externas.get(f["grupo"]["id"], 0),
        }
        for f in filas
    ]


@router.post("/grafo/sospechosos/{id_grupo}/suspender")
def suspender_sospechosos(id_grupo: int = PathParam(ge=1)):
    """Suspende todas las cuentas del grupo (salvo las administradoras) y rehace el grafo."""
    with grafo_disponible():
        miembros = grafo.consultar_grafo(
            "MATCH (:Coordinacion {id: $id})<-[:MIEMBRO_DE]-(u:Usuario) RETURN u.id AS id",
            id=id_grupo,
        )
    if not miembros:
        raise HTTPException(status_code=404, detail="Ese grupo ya no está entre los sospechosos")
    suspendidas = []
    with transaccion() as cursor:
        for m in miembros:
            cursor.execute("SELECT email, estado FROM usuario WHERE id_usuario = %s FOR UPDATE", (m["id"],))
            usuario = cursor.fetchone()
            if usuario is None or usuario["estado"] in ("SUSPENDIDO", "ELIMINADO") or es_correo_admin(usuario["email"]):
                continue
            moderacion.suspender(cursor, m["id"])
            suspendidas.append(m["id"])
    grafo.sincronizar_sin_fallar()
    return {"id_grupo": id_grupo, "suspendidas": len(suspendidas), "ids": suspendidas}


@router.get("/grafo/reputacion")
def reputacion(
    orden: Literal["baja", "alta"] = "baja",
    limite: int = Query(30, ge=1, le=200),
):
    """Vecinos ordenados por reputación (por defecto, los menos confiables primero)."""
    direccion = "ASC" if orden == "baja" else "DESC"
    with grafo_disponible():
        filas = grafo.consultar_grafo(
            f"""
            MATCH (u:Usuario) WHERE NOT u.es_admin
            OPTIONAL MATCH (u)-[:CREO]->(r:Reporte)
            OPTIONAL MATCH (u)-[:MIEMBRO_DE]->(c:Coordinacion)
            WITH u, count(DISTINCT r) AS reportes, c IS NOT NULL AS sospechoso
            WHERE reportes > 0 OR u.confirmaciones_recibidas > 0
            RETURN properties(u) AS u, reportes, sospechoso
            ORDER BY u.reputacion {direccion}, reportes DESC LIMIT $limite
            """,
            limite=limite,
        )
    return [{**nodo("Usuario", f["u"]), "reportes": f["reportes"], "sospechoso": f["sospechoso"]} for f in filas]


@router.get("/grafo/incidentes")
def incidentes_agrupados(
    abiertos: bool = True,
    limite: int = Query(30, ge=1, le=200),
):
    """Incidentes con más de un reporte, del más reciente al más antiguo."""
    with grafo_disponible():
        filas = grafo.consultar_grafo(
            """
            MATCH (i:Incidente)-[:AGRUPA]->(r:Reporte)
            OPTIONAL MATCH (r)-[:OCURRIO_EN]->(lugar)
            WITH i, r, lugar ORDER BY r.fecha_creacion
            WITH i, collect(properties(r)) AS reportes, head(collect(lugar.nombre)) AS lugar,
                 sum(CASE WHEN r.estado IN ['PENDIENTE', 'VALIDADO'] AND NOT r.vencido THEN 1 ELSE 0 END) AS vigentes
            WHERE NOT $abiertos OR vigentes > 0
            RETURN properties(i) AS i, reportes, lugar, vigentes
            ORDER BY i.fin DESC LIMIT $limite
            """,
            abiertos=abiertos,
            limite=limite,
        )
    return [
        {
            **nodo("Incidente", f["i"]),
            "lugar": f["lugar"],
            "vigentes": f["vigentes"],
            "reportes": [nodo("Reporte", r) for r in f["reportes"]],
        }
        for f in filas
    ]


@router.patch("/incidentes/{id_reporte}/estado")
def cambiar_estado_incidente(
    datos: CambioEstadoIncidente,
    id_reporte: int = PathParam(ge=1),
    admin: dict = Depends(usuario_admin),
):
    """Aplica el estado a todos los reportes vigentes del incidente de id_reporte.

    El incidente se recalcula en MySQL al momento (no se usa la copia del grafo), así
    incluye también los reportes que llegaron después de la última sincronización.
    """
    grupo = reportes_del_incidente(id_reporte)
    if not grupo:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    id_incidente = grupo[0]["id_reporte"]
    motivo = (datos.motivo or "").strip()
    motivo = (
        f"Panel de administración (incidente #{id_incidente}): {motivo}" if motivo
        else f"Incidente #{id_incidente} moderado desde el panel de administración"
    )
    cambiados = []
    with transaccion() as cursor:
        for r in grupo:
            cursor.execute("SELECT estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (r["id_reporte"],))
            fila = cursor.fetchone()
            if fila is None or fila["estado"] == datos.estado:
                continue
            cambiar_estado(cursor, r["id_reporte"], fila["estado"], datos.estado, admin["id_usuario"], motivo)
            cambiados.append(r["id_reporte"])
    grafo.sincronizar_sin_fallar()
    return {"id_incidente": id_incidente, "estado": datos.estado, "reportes": cambiados}


@router.post("/grafo/sincronizar")
def sincronizar_grafo():
    """Rehace el grafo ahora, sin esperar la sincronización automática."""
    with grafo_disponible():
        totales = grafo.sincronizar()
    return {"totales": totales, "sincronizacion": grafo.ultima_sincronizacion}
