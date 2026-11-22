"""Resumen del grafo (Neo4j) e incidentes: reportes del mismo hecho (ver app/servicios/incidentes.py)."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.db import transaccion
from app.rutas.admin.errores import grafo_disponible
from app.seguridad import usuario_admin
from app.servicios import grafo
from app.servicios.grafo import analisis
from app.servicios.grafo.red import nodo
from app.servicios.reportes import cambiar_estado, reportes_del_incidente

router = APIRouter()


class CambioEstadoIncidente(BaseModel):
    estado: Literal["VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


@router.get("/grafo/resumen")
def resumen_grafo():
    """Cifras de los últimos 30 días para la tarjeta del Resumen y los contadores del análisis."""
    with grafo_disponible():
        calles = analisis.ranking_calles(30, None, None, limite=3)
        sectores = analisis.sectores_en_el_tiempo(30, None, None, tramos=2, limite=1)
        fila = grafo.consultar_grafo(
            """
            MATCH (i:Incidente)-[:AGRUPA]->(r:Reporte)
            WHERE r.estado IN ['PENDIENTE', 'VALIDADO'] AND NOT r.vencido
            RETURN count(DISTINCT i) AS incidentes_abiertos
            """
        )[0]
    return {
        "calles_con_hechos": calles["total_calles"],
        "calles_top": [{"nombre": c["nombre"], "total": c["total"], "tendencia": c["tendencia"]} for c in calles["calles"]],
        "sectores_en_alza": sectores["resumen"]["sube"] + sectores["resumen"]["nueva"],
        "incidentes_abiertos": fila["incidentes_abiertos"],
        "sincronizacion": grafo.ultima_sincronizacion,
    }


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
