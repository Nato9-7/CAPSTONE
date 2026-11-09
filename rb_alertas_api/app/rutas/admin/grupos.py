"""Grupos vecinales vistos por el admin general: todos (también los cerrados), sus
reportes y la opción de cerrarlos o reabrirlos. Los miembros aparecen solo como total."""

from fastapi import APIRouter, HTTPException, Path as PathParam, Query
from pydantic import BaseModel

from app.comun.alias import alias_autor
from app.db import consultar, transaccion
from app.servicios.grupos import MAXIMO_GRUPOS_CREADOS

router = APIRouter()


class CambioEstadoGrupo(BaseModel):
    activo: bool


@router.get("/grupos")
def listar_grupos(
    buscar: str | None = Query(None, max_length=80),
    activo: bool | None = None,
    limite: int = Query(100, ge=1, le=300),
):
    """Grupos del más nuevo al más antiguo. `buscar` filtra por nombre del grupo o correo de quien lo creó."""
    condiciones, parametros = [], []
    if buscar and buscar.strip():
        patron = f"%{buscar.strip()}%"
        condiciones.append("(g.nombre LIKE %s OR u.email LIKE %s)")
        parametros += [patron, patron]
    if activo is not None:
        condiciones.append("g.activo = %s")
        parametros.append(1 if activo else 0)
    filtro = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""

    filas = consultar(
        f"""
        SELECT g.id_grupo, g.nombre, g.descripcion, g.radio_metros,
               g.direccion_referencia AS direccion, g.activo, g.fecha_creacion,
               g.codigo_expira, (g.codigo_expira <= NOW()) AS codigo_vencido,
               CONCAT(u.nombres, ' ', u.apellidos) AS creador, u.email AS creador_email,
               (SELECT COUNT(*) FROM grupo_miembro m WHERE m.id_grupo = g.id_grupo) AS total_miembros,
               (SELECT COUNT(*) FROM grupo_reporte gr WHERE gr.id_grupo = g.id_grupo) AS total_reportes,
               (SELECT COUNT(*) FROM grupo_reporte gr
                  JOIN reporte r ON r.id_reporte = gr.id_reporte
                 WHERE gr.id_grupo = g.id_grupo AND r.visibilidad = 'GRUPO') AS reportes_privados,
               (SELECT MAX(gr.fecha_publicacion) FROM grupo_reporte gr
                 WHERE gr.id_grupo = g.id_grupo) AS ultimo_reporte
        FROM grupo g
        JOIN usuario u ON u.id_usuario = g.id_creador
        {filtro}
        ORDER BY g.fecha_creacion DESC
        LIMIT %s
        """,
        (*parametros, limite),
    )
    for fila in filas:
        fila["activo"] = bool(fila["activo"])
        fila["codigo_vencido"] = bool(fila["codigo_vencido"])
        for campo in ("total_miembros", "total_reportes", "reportes_privados"):
            fila[campo] = int(fila[campo])
    return filas


@router.get("/grupos/{id_grupo}/reportes")
def listar_reportes_grupo(id_grupo: int = PathParam(ge=1), limite: int = Query(100, ge=1, le=300)):
    """Lo que se compartió en el grupo, con el alias del autor como en el resto del panel."""
    if not consultar("SELECT id_grupo FROM grupo WHERE id_grupo = %s", (id_grupo,)):
        raise HTTPException(status_code=404, detail="Grupo no encontrado")
    filas = consultar(
        """
        SELECT r.id_reporte, c.nombre AS categoria, c.codigo AS categoria_codigo, c.color_hex,
               r.estado, r.visibilidad, r.descripcion, r.direccion_referencia AS direccion,
               gr.fecha_publicacion,
               (r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()) AS vencido
        FROM grupo_reporte gr
        JOIN reporte r ON r.id_reporte = gr.id_reporte
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE gr.id_grupo = %s
        ORDER BY gr.id_reporte DESC
        LIMIT %s
        """,
        (id_grupo, limite),
    )
    for fila in filas:
        fila["vencido"] = bool(fila["vencido"])
        fila["autor"] = alias_autor(fila["id_reporte"])
    return filas


@router.patch("/grupos/{id_grupo}/estado")
def cambiar_estado_grupo(datos: CambioEstadoGrupo, id_grupo: int = PathParam(ge=1)):
    """Cierra un grupo (nadie lo ve y sus reportes privados quedan ocultos) o lo reabre."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_creador, activo FROM grupo WHERE id_grupo = %s FOR UPDATE", (id_grupo,))
        grupo = cursor.fetchone()
        if grupo is None:
            raise HTTPException(status_code=404, detail="Grupo no encontrado")
        if bool(grupo["activo"]) == datos.activo:
            raise HTTPException(
                status_code=409,
                detail="El grupo ya está activo" if datos.activo else "El grupo ya está cerrado",
            )
        if datos.activo:
            # Mismo límite que en la app: quien lo creó administra un solo grupo a la vez.
            cursor.execute(
                "SELECT COUNT(*) AS total FROM grupo WHERE id_creador = %s AND activo = 1 AND id_grupo <> %s",
                (grupo["id_creador"], id_grupo),
            )
            if cursor.fetchone()["total"] >= MAXIMO_GRUPOS_CREADOS:
                raise HTTPException(status_code=409, detail="Quien creó este grupo ya administra otro grupo activo")
        cursor.execute("UPDATE grupo SET activo = %s WHERE id_grupo = %s", (1 if datos.activo else 0, id_grupo))
    return {"id_grupo": id_grupo, "activo": datos.activo}
