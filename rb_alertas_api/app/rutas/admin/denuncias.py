"""Revisión de las denuncias de los vecinos. Quién denunció no sale de la API."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel

from app.db import consultar, transaccion
from app.seguridad import usuario_admin
from app.servicios import moderacion

router = APIRouter()

# Segmento de la URL -> tipo de lo denunciado.
_TIPOS = {"reportes": "reporte", "comentarios": "comentario"}


class RevisionDenuncias(BaseModel):
    estado: Literal["ATENDIDA", "DESESTIMADA"]


def _denuncia_json(f: dict) -> dict:
    return {
        "tipo": "COMENTARIO" if f["id_comentario"] else "REPORTE",
        "id_reporte": f["id_reporte"],
        "id_comentario": f["id_comentario"],
        "total": int(f["total"]),
        "motivos": f["motivos"].split(",") if f["motivos"] else [],
        "detalles": f["detalles"].split("\n") if f["detalles"] else [],
        "ultima": f["ultima"],
        "categoria": f["categoria"],
        "categoria_codigo": f["categoria_codigo"],
        "color_hex": f["color_hex"],
        "estado_reporte": f["estado_reporte"],
        "descripcion": f["descripcion"],
        "contenido": f["contenido"],
        "estado_comentario": f["estado_comentario"],
    }


@router.get("/denuncias")
def listar_denuncias(
    estado: Literal["PENDIENTE", "ATENDIDA", "DESESTIMADA"] = "PENDIENTE",
    limite: int = Query(100, ge=1, le=300),
):
    """Denuncias juntas por lo denunciado (un reporte o un comentario):
    cuántas hay, por qué motivos y lo que escribieron."""
    filas = consultar(
        """
        SELECT g.id_reporte AS id_reporte_denunciado, g.id_comentario, g.total, g.motivos,
               g.detalles, g.ultima,
               r.id_reporte, r.estado AS estado_reporte, r.descripcion,
               cat.nombre AS categoria, cat.codigo AS categoria_codigo, cat.color_hex,
               co.contenido, co.estado AS estado_comentario
        FROM (
            SELECT id_reporte, id_comentario, COUNT(*) AS total,
                   GROUP_CONCAT(DISTINCT motivo ORDER BY motivo) AS motivos,
                   GROUP_CONCAT(detalle ORDER BY fecha_creacion DESC SEPARATOR '\n') AS detalles,
                   MAX(fecha_creacion) AS ultima
            FROM denuncia
            WHERE estado = %s
            GROUP BY id_reporte, id_comentario
        ) g
        LEFT JOIN comentario co ON co.id_comentario = g.id_comentario
        JOIN reporte r ON r.id_reporte = COALESCE(g.id_reporte, co.id_reporte)
        JOIN categoria_incidente cat ON cat.id_categoria = r.id_categoria
        ORDER BY g.total DESC, g.ultima DESC
        LIMIT %s
        """,
        (estado, limite),
    )
    return [_denuncia_json(f) for f in filas]


@router.patch("/denuncias/{tipo}/{id_objetivo}")
def revisar_denuncias(
    datos: RevisionDenuncias,
    tipo: Literal["reportes", "comentarios"],
    id_objetivo: int = PathParam(ge=1),
    admin: dict = Depends(usuario_admin),
):
    """Cierra las denuncias pendientes de un reporte o comentario. Desestimar un
    comentario que se ocultó solo por las denuncias lo vuelve a publicar."""
    denunciado = _TIPOS[tipo]
    with transaccion() as cursor:
        cursor.execute(
            f"SELECT COUNT(*) AS total FROM denuncia "
            f"WHERE {moderacion.columna_denunciado(denunciado)} = %s AND estado = 'PENDIENTE'",
            (id_objetivo,),
        )
        if cursor.fetchone()["total"] == 0:
            raise HTTPException(status_code=404, detail="No hay denuncias pendientes de esto")
        moderacion.cerrar_denuncias(cursor, denunciado, id_objetivo, datos.estado, admin["id_usuario"])
        if denunciado == "comentario" and datos.estado == "DESESTIMADA":
            cursor.execute(
                "UPDATE comentario SET estado = 'PUBLICADO' WHERE id_comentario = %s AND estado = 'OCULTO'",
                (id_objetivo,),
            )
    return {"tipo": tipo, "id": id_objetivo, "estado": datos.estado}
