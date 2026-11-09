"""Consultas y cambios sobre comentarios que comparten la app y el panel de administración."""

from fastapi import HTTPException

from app.db import consultar


def comentarios_de_reporte(id_reporte: int) -> list[dict]:
    """Todos los comentarios del reporte, en cualquier estado, del más antiguo al más nuevo."""
    return consultar(
        """
        SELECT c.id_comentario, c.id_comentario_padre, c.id_usuario, c.contenido,
               c.estado, c.fecha_creacion, i.url_archivo AS imagen
        FROM comentario c
        LEFT JOIN comentario_imagen i ON i.id_comentario = c.id_comentario
        WHERE c.id_reporte = %s
        ORDER BY c.fecha_creacion, c.id_comentario
        """,
        (id_reporte,),
    )


def bloquear_comentario(cursor, id_comentario: int) -> dict:
    """Lee y bloquea el comentario para cambiarlo. 404 si no existe; 409 si ya fue eliminado."""
    cursor.execute(
        "SELECT id_comentario, id_reporte, id_usuario, estado FROM comentario WHERE id_comentario = %s FOR UPDATE",
        (id_comentario,),
    )
    fila = cursor.fetchone()
    if fila is None:
        raise HTTPException(status_code=404, detail="Comentario no encontrado")
    if fila["estado"] == "ELIMINADO":
        raise HTTPException(status_code=409, detail="Este comentario ya fue eliminado")
    return fila


def marcar_eliminado(cursor, id_comentario: int) -> list[str]:
    """Deja el comentario como ELIMINADO (así sus respuestas no quedan colgando) y quita su foto.

    Devuelve las url de las fotos para borrarlas del disco después de confirmar la
    transacción: aunque el comentario no se muestre, la foto se podía abrir con su enlace.
    """
    cursor.execute("SELECT url_archivo FROM comentario_imagen WHERE id_comentario = %s", (id_comentario,))
    archivos = [f["url_archivo"] for f in cursor.fetchall()]
    cursor.execute("DELETE FROM comentario_imagen WHERE id_comentario = %s", (id_comentario,))
    cursor.execute("UPDATE comentario SET estado = 'ELIMINADO' WHERE id_comentario = %s", (id_comentario,))
    return archivos
