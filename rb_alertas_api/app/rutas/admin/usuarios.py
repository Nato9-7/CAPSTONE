"""Cuentas registradas: búsqueda, suspensión y reactivación."""

from typing import Literal

from fastapi import APIRouter, HTTPException, Path as PathParam, Query
from pydantic import BaseModel

from app.db import consultar, transaccion
from app.seguridad import es_correo_admin
from app.servicios import moderacion

router = APIRouter()


class CambioEstadoUsuario(BaseModel):
    estado: Literal["ACTIVO", "SUSPENDIDO"]


@router.get("/usuarios")
def listar_usuarios(
    buscar: str | None = Query(None, max_length=80),
    estado: Literal["PENDIENTE", "ACTIVO", "SUSPENDIDO", "ELIMINADO"] | None = None,
    limite: int = Query(100, ge=1, le=300),
):
    """Cuentas registradas, de la más nueva a la más antigua. `buscar` filtra por nombre, correo o RUT."""
    condiciones, parametros = [], []
    if buscar and buscar.strip():
        patron = f"%{buscar.strip()}%"
        condiciones.append("(CONCAT(u.nombres, ' ', u.apellidos) LIKE %s OR u.email LIKE %s OR u.rut LIKE %s)")
        parametros += [patron, patron, patron]
    if estado:
        condiciones.append("u.estado = %s")
        parametros.append(estado)
    filtro = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""

    filas = consultar(
        f"""
        SELECT u.id_usuario, u.nombres, u.apellidos, u.email, u.rut, u.telefono,
               u.estado, u.email_verificado, u.fecha_creacion,
               (SELECT COUNT(*) FROM reporte r WHERE r.id_usuario = u.id_usuario) AS total_reportes
        FROM usuario u
        {filtro}
        ORDER BY u.fecha_creacion DESC
        LIMIT %s
        """,
        (*parametros, limite),
    )
    for fila in filas:
        fila["email_verificado"] = bool(fila["email_verificado"])
        fila["total_reportes"] = int(fila["total_reportes"])
        fila["es_admin"] = es_correo_admin(fila["email"])
    return filas


@router.patch("/usuarios/{id_usuario}/estado")
def cambiar_estado_usuario(datos: CambioEstadoUsuario, id_usuario: int = PathParam(ge=1)):
    """Suspende o reactiva una cuenta. Al suspender se cierran todas sus sesiones."""
    with transaccion() as cursor:
        usuario = moderacion.usuario_moderable(cursor, id_usuario)
        if datos.estado == "SUSPENDIDO":
            if usuario["estado"] == "SUSPENDIDO":
                raise HTTPException(status_code=409, detail="La cuenta ya está suspendida")
            moderacion.suspender(cursor, id_usuario)
            return {"id_usuario": id_usuario, "estado": "SUSPENDIDO"}

        if usuario["estado"] != "SUSPENDIDO":
            raise HTTPException(status_code=409, detail="La cuenta no está suspendida")
        # Si nunca verificó su correo, vuelve a PENDIENTE y no a ACTIVO.
        cursor.execute(
            "UPDATE usuario SET estado = IF(email_verificado = 1, 'ACTIVO', 'PENDIENTE') WHERE id_usuario = %s",
            (id_usuario,),
        )
        cursor.execute("SELECT estado FROM usuario WHERE id_usuario = %s", (id_usuario,))
        nuevo = cursor.fetchone()["estado"]
    return {"id_usuario": id_usuario, "estado": nuevo}
