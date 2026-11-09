"""Acciones de moderación del panel de administración que comparten varias secciones."""

from typing import Literal

from fastapi import HTTPException

from app.seguridad import es_correo_admin, revocar_sesiones_usuario

TipoDenunciado = Literal["reporte", "comentario"]

# SQL no acepta nombres de columna como parámetro: solo se usan estos valores fijos.
_COLUMNA_DENUNCIADO = {"reporte": "id_reporte", "comentario": "id_comentario"}


def columna_denunciado(tipo: TipoDenunciado) -> str:
    return _COLUMNA_DENUNCIADO[tipo]


def cerrar_denuncias(cursor, tipo: TipoDenunciado, id_objetivo: int, estado: str, id_admin: int) -> None:
    """Marca como revisadas las denuncias pendientes de un reporte o comentario."""
    cursor.execute(
        f"""
        UPDATE denuncia SET estado = %s, fecha_revision = NOW(), id_admin = %s
        WHERE {columna_denunciado(tipo)} = %s AND estado = 'PENDIENTE'
        """,
        (estado, id_admin, id_objetivo),
    )


def suspender(cursor, id_usuario: int) -> None:
    cursor.execute("UPDATE usuario SET estado = 'SUSPENDIDO' WHERE id_usuario = %s", (id_usuario,))
    # Sin esto la persona seguiría usando la app hasta que venza su token.
    revocar_sesiones_usuario(cursor, id_usuario)


def usuario_moderable(cursor, id_usuario: int) -> dict:
    """Bloquea y devuelve la cuenta si el panel puede cambiar su estado."""
    cursor.execute("SELECT id_usuario, email, estado FROM usuario WHERE id_usuario = %s FOR UPDATE", (id_usuario,))
    usuario = cursor.fetchone()
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    if es_correo_admin(usuario["email"]):
        raise HTTPException(status_code=403, detail="No se puede cambiar el estado de una cuenta administradora")
    if usuario["estado"] == "ELIMINADO":
        raise HTTPException(status_code=409, detail="La cuenta fue eliminada")
    return usuario


def suspender_autor(cursor, id_usuario: int, mensaje_ya_suspendido: str) -> None:
    """Suspende a quien creó un reporte o comentario sin revelar su identidad en el panel."""
    usuario = usuario_moderable(cursor, id_usuario)
    if usuario["estado"] == "SUSPENDIDO":
        raise HTTPException(status_code=409, detail=mensaje_ya_suspendido)
    suspender(cursor, usuario["id_usuario"])
