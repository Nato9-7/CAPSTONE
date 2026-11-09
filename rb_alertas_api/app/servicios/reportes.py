"""Reglas sobre reportes que usan varias rutas: quién puede verlos, su incidente y su historial."""

from fastapi import HTTPException

from app.db import consultar
from app.servicios import incidentes

ESTADOS_VIGENTES = ("PENDIENTE", "VALIDADO")

# Al buscar el incidente de un reporte se revisa este entorno: más amplio que la
# regla de agrupación, para alcanzar también los reportes encadenados.
VENTANA_INCIDENTE_MINUTOS = 24 * 60
VENTANA_INCIDENTE_METROS = 5000


def _no_encontrado() -> HTTPException:
    return HTTPException(status_code=404, detail="Reporte no encontrado")


def puede_ver_reporte(id_reporte: int, id_autor: int, visibilidad: str, id_usuario: int | None) -> bool:
    """Un reporte GRUPO solo lo ven su autor y los miembros de los grupos activos donde se compartió."""
    if visibilidad == "PUBLICO":
        return True
    if id_usuario is None:
        return False
    if id_usuario == id_autor:
        return True
    return bool(consultar(
        """
        SELECT 1
        FROM grupo_reporte gr
        JOIN grupo g ON g.id_grupo = gr.id_grupo AND g.activo = 1
        JOIN grupo_miembro m ON m.id_grupo = gr.id_grupo AND m.id_usuario = %s
        WHERE gr.id_reporte = %s
        LIMIT 1
        """,
        (id_usuario, id_reporte),
    ))


def exigir_visible(fila: dict | None, id_reporte: int, id_usuario: int | None) -> dict:
    """Devuelve la fila del reporte si quien consulta puede verlo.

    404 si no existe o es privado de un grupo ajeno: no se revela cuál de los dos.
    `fila` debe traer id_usuario y visibilidad.
    """
    if fila is None or not puede_ver_reporte(id_reporte, fila["id_usuario"], fila["visibilidad"], id_usuario):
        raise _no_encontrado()
    return fila


def verificar_acceso_reporte(id_reporte: int, id_usuario: int | None) -> None:
    filas = consultar("SELECT id_usuario, visibilidad FROM reporte WHERE id_reporte = %s", (id_reporte,))
    exigir_visible(filas[0] if filas else None, id_reporte, id_usuario)


def reporte_visible(id_reporte: int, usuario: dict | None) -> dict:
    """El reporte con su categoría y si sigue vigente, si quien consulta puede verlo."""
    filas = consultar(
        """
        SELECT r.id_reporte, r.id_usuario, r.estado, r.visibilidad, c.nombre AS categoria,
               (r.estado IN ('PENDIENTE', 'VALIDADO')
                AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())) AS vigente
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.id_reporte = %s
        """,
        (id_reporte,),
    )
    id_usuario = usuario["id_usuario"] if usuario is not None else None
    return exigir_visible(filas[0] if filas else None, id_reporte, id_usuario)


def reportes_del_incidente(id_reporte: int) -> list[dict]:
    """El reporte y los vigentes y públicos del mismo incidente, del más antiguo al más nuevo."""
    filas = consultar(
        """
        SELECT r.id_reporte, c.codigo AS categoria_codigo,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.fecha_creacion, r.descripcion, r.estado, r.id_usuario,
               r.total_confirmaciones, r.total_desmentidos
        FROM reporte base
        JOIN reporte r ON r.id_categoria = base.id_categoria
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE base.id_reporte = %s
          AND (r.id_reporte = base.id_reporte OR (
                r.visibilidad = 'PUBLICO'
                AND r.estado IN ('PENDIENTE', 'VALIDADO')
                AND (r.fecha_expiracion IS NULL OR r.fecha_expiracion > NOW())))
          AND ABS(TIMESTAMPDIFF(MINUTE, r.fecha_creacion, base.fecha_creacion)) <= %s
          AND ST_Distance_Sphere(r.ubicacion, base.ubicacion) <= %s
        """,
        (id_reporte, VENTANA_INCIDENTE_MINUTOS, VENTANA_INCIDENTE_METROS),
    )
    return incidentes.grupo_de(id_reporte, filas)


def cambiar_estado(cursor, id_reporte: int, anterior: str, nuevo: str, id_responsable: int, motivo: str) -> None:
    """Cambia el estado del reporte y lo deja en reporte_estado_historial (en la transacción del cursor)."""
    cursor.execute("UPDATE reporte SET estado = %s WHERE id_reporte = %s", (nuevo, id_reporte))
    cursor.execute(
        """
        INSERT INTO reporte_estado_historial (
            id_reporte, estado_anterior, estado_nuevo, id_usuario_responsable, motivo
        ) VALUES (%s, %s, %s, %s, %s)
        """,
        (id_reporte, anterior, nuevo, id_responsable, motivo),
    )
