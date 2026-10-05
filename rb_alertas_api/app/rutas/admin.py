from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app.db import consultar, transaccion
from app.rutas.reportes import alias_autor
from app.seguridad import CORREOS_ADMIN, revocar_sesiones_usuario, usuario_admin

# Todas las rutas exigen sesión de una cuenta admin (ver seguridad.CORREOS_ADMIN).
router = APIRouter(dependencies=[Depends(usuario_admin)])

ESTADOS_REPORTE = ("PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO", "EXPIRADO")
ESTADOS_USUARIO = ("PENDIENTE", "ACTIVO", "SUSPENDIDO", "ELIMINADO")


class CambioEstadoReporte(BaseModel):
    estado: Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


class CambioEstadoUsuario(BaseModel):
    estado: Literal["ACTIVO", "SUSPENDIDO"]


def _conteo_por_estado(tabla: str, estados: tuple) -> dict:
    filas = consultar(f"SELECT estado, COUNT(*) AS total FROM {tabla} GROUP BY estado")
    conteo = {estado: 0 for estado in estados}
    for fila in filas:
        conteo[fila["estado"]] = int(fila["total"])
    return conteo


@router.get("/resumen")
def resumen():
    """Cifras de la portada del panel."""
    actividad = consultar(
        """
        SELECT SUM(fecha_creacion > NOW() - INTERVAL 1 DAY) AS ultimas_24h,
               SUM(fecha_creacion > NOW() - INTERVAL 7 DAY) AS ultimos_7d,
               SUM(estado IN ('PENDIENTE', 'VALIDADO')
                   AND (fecha_expiracion IS NULL OR fecha_expiracion > NOW())) AS vigentes
        FROM reporte
        """
    )[0]
    nuevos = consultar("SELECT COUNT(*) AS total FROM usuario WHERE fecha_creacion > NOW() - INTERVAL 7 DAY")[0]
    categorias = consultar(
        """
        SELECT c.nombre, c.color_hex, COUNT(r.id_reporte) AS total
        FROM categoria_incidente c
        LEFT JOIN reporte r ON r.id_categoria = c.id_categoria
             AND r.fecha_creacion > NOW() - INTERVAL 30 DAY
        WHERE c.activa = 1
        GROUP BY c.id_categoria, c.nombre, c.color_hex
        ORDER BY total DESC, c.id_categoria
        """
    )
    return {
        "usuarios_por_estado": _conteo_por_estado("usuario", ESTADOS_USUARIO),
        "usuarios_nuevos_7d": int(nuevos["total"] or 0),
        "reportes_por_estado": _conteo_por_estado("reporte", ESTADOS_REPORTE),
        "reportes_24h": int(actividad["ultimas_24h"] or 0),
        "reportes_7d": int(actividad["ultimos_7d"] or 0),
        "reportes_vigentes": int(actividad["vigentes"] or 0),
        "categorias_30d": [{**c, "total": int(c["total"])} for c in categorias],
    }


@router.get("/reportes")
def listar_reportes(
    estado: Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO", "EXPIRADO"] | None = None,
    limite: int = Query(100, ge=1, le=300),
):
    """Todos los reportes (no solo los vigentes), del más reciente al más antiguo.

    Igual que en el resto de la API, el autor se muestra con su alias: el panel
    puede suspender a quien reportó (ver suspender_autor) sin conocer su nombre.
    """
    filtro, parametros = ("WHERE r.estado = %s", (estado,)) if estado else ("", ())
    filas = consultar(
        f"""
        SELECT r.id_reporte, c.nombre AS categoria, c.codigo AS categoria_codigo, c.color_hex,
               r.estado, r.descripcion, r.direccion_referencia AS direccion,
               COALESCE(l.nombre, cm.nombre) AS zona,
               r.fecha_creacion, r.fecha_expiracion,
               (r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()) AS vencido,
               r.total_confirmaciones, r.total_desmentidos,
               (
                   SELECT i.url_archivo FROM reporte_imagen i
                   WHERE i.id_reporte = r.id_reporte
                   ORDER BY i.orden LIMIT 1
               ) AS imagen
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        LEFT JOIN comuna cm ON cm.id_comuna = r.id_comuna
        LEFT JOIN localidad l ON l.id_localidad = r.id_localidad
        {filtro}
        ORDER BY r.fecha_creacion DESC
        LIMIT %s
        """,
        (*parametros, limite),
    )
    for fila in filas:
        fila["vencido"] = bool(fila["vencido"])
        fila["autor"] = alias_autor(fila["id_reporte"])
    return filas


@router.patch("/reportes/{id_reporte}/estado")
def cambiar_estado_reporte(
    datos: CambioEstadoReporte,
    id_reporte: int = PathParam(ge=1),
    admin: dict = Depends(usuario_admin),
):
    """Modera un reporte (p. ej. descartar uno falso); el cambio queda en reporte_estado_historial."""
    motivo = (datos.motivo or "").strip()
    motivo = f"Panel de administración: {motivo}" if motivo else "Cambio desde el panel de administración"

    with transaccion() as cursor:
        cursor.execute("SELECT estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (id_reporte,))
        fila = cursor.fetchone()
        if fila is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        if fila["estado"] == datos.estado:
            raise HTTPException(status_code=409, detail=f"El reporte ya está {datos.estado.lower()}")

        cursor.execute("UPDATE reporte SET estado = %s WHERE id_reporte = %s", (datos.estado, id_reporte))
        cursor.execute(
            """
            INSERT INTO reporte_estado_historial (
                id_reporte, estado_anterior, estado_nuevo, id_usuario_responsable, motivo
            ) VALUES (%s, %s, %s, %s, %s)
            """,
            (id_reporte, fila["estado"], datos.estado, admin["id_usuario"], motivo),
        )
    return {"id_reporte": id_reporte, "estado": datos.estado}


def _suspender(cursor, id_usuario: int) -> None:
    cursor.execute("UPDATE usuario SET estado = 'SUSPENDIDO' WHERE id_usuario = %s", (id_usuario,))
    # Sin esto la persona seguiría usando la app hasta que venza su token.
    revocar_sesiones_usuario(cursor, id_usuario)


def _usuario_moderable(cursor, id_usuario: int) -> dict:
    cursor.execute("SELECT id_usuario, email, estado FROM usuario WHERE id_usuario = %s FOR UPDATE", (id_usuario,))
    usuario = cursor.fetchone()
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    if usuario["email"].strip().lower() in CORREOS_ADMIN:
        raise HTTPException(status_code=403, detail="No se puede cambiar el estado de una cuenta administradora")
    if usuario["estado"] == "ELIMINADO":
        raise HTTPException(status_code=409, detail="La cuenta fue eliminada")
    return usuario


@router.post("/reportes/{id_reporte}/suspender-autor")
def suspender_autor(id_reporte: int = PathParam(ge=1)):
    """Suspende a quien creó el reporte sin revelar su identidad en el panel."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_usuario FROM reporte WHERE id_reporte = %s", (id_reporte,))
        reporte = cursor.fetchone()
        if reporte is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        usuario = _usuario_moderable(cursor, reporte["id_usuario"])
        if usuario["estado"] == "SUSPENDIDO":
            raise HTTPException(status_code=409, detail="Quien creó este reporte ya está suspendido")
        _suspender(cursor, usuario["id_usuario"])
    return {"id_reporte": id_reporte, "autor": alias_autor(id_reporte), "estado_autor": "SUSPENDIDO"}


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
        fila["es_admin"] = fila["email"].strip().lower() in CORREOS_ADMIN
    return filas


@router.patch("/usuarios/{id_usuario}/estado")
def cambiar_estado_usuario(datos: CambioEstadoUsuario, id_usuario: int = PathParam(ge=1)):
    """Suspende o reactiva una cuenta. Al suspender se cierran todas sus sesiones."""
    with transaccion() as cursor:
        usuario = _usuario_moderable(cursor, id_usuario)
        if datos.estado == "SUSPENDIDO":
            if usuario["estado"] == "SUSPENDIDO":
                raise HTTPException(status_code=409, detail="La cuenta ya está suspendida")
            _suspender(cursor, id_usuario)
            nuevo = "SUSPENDIDO"
        else:
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
