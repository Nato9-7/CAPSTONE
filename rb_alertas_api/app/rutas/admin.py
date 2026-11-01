import logging
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app import grafo
from app.db import consultar, transaccion
from app.rutas.comentarios import comentarios_de_reporte, mapa_alias
from app.rutas.grupos import MAXIMO_GRUPOS_CREADOS
from app.rutas.reportes import CARPETA_UPLOADS, alias_autor
from app.seguridad import CORREOS_ADMIN, revocar_sesiones_usuario, usuario_admin

# Todas las rutas exigen sesión de una cuenta admin (ver seguridad.CORREOS_ADMIN).
router = APIRouter(dependencies=[Depends(usuario_admin)])
log = logging.getLogger("rb_alertas.admin")

ESTADOS_REPORTE = ("PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO", "EXPIRADO")
ESTADOS_USUARIO = ("PENDIENTE", "ACTIVO", "SUSPENDIDO", "ELIMINADO")


class CambioEstadoReporte(BaseModel):
    estado: Literal["PENDIENTE", "VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


class CambioEstadoUsuario(BaseModel):
    estado: Literal["ACTIVO", "SUSPENDIDO"]


class CambioEstadoComentario(BaseModel):
    estado: Literal["PUBLICADO", "OCULTO"]


class CambioEstadoGrupo(BaseModel):
    activo: bool


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
    limite: int = Query(100, ge=1, le=500),
):
    """Todos los reportes (no solo los vigentes), del más reciente al más antiguo.

    Igual que en el resto de la API, el autor se muestra con su alias: el panel
    puede suspender a quien reportó (ver suspender_autor) sin conocer su nombre.
    """
    filtro, parametros = ("WHERE r.estado = %s", (estado,)) if estado else ("", ())
    filas = consultar(
        f"""
        SELECT r.id_reporte, c.nombre AS categoria, c.codigo AS categoria_codigo, c.color_hex,
               r.estado, r.visibilidad, r.descripcion, r.direccion_referencia AS direccion,
               COALESCE(l.nombre, cm.nombre) AS zona,
               r.fecha_creacion, r.fecha_expiracion,
               (r.fecha_expiracion IS NOT NULL AND r.fecha_expiracion <= NOW()) AS vencido,
               r.total_confirmaciones, r.total_desmentidos,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               (
                   SELECT i.url_archivo FROM reporte_imagen i
                   WHERE i.id_reporte = r.id_reporte
                   ORDER BY i.orden LIMIT 1
               ) AS imagen,
               (
                   SELECT COUNT(*) FROM comentario co
                   WHERE co.id_reporte = r.id_reporte AND co.estado = 'PUBLICADO'
               ) AS total_comentarios,
               (
                   SELECT COUNT(*) FROM comentario co
                   WHERE co.id_reporte = r.id_reporte AND co.estado = 'OCULTO'
               ) AS comentarios_ocultos
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


def _borrar_archivo(url: str | None) -> bool:
    """Borra del disco una evidencia ("/uploads/...") sin salir de la carpeta de uploads."""
    if not url or not url.startswith("/uploads/"):
        return False
    base = Path(CARPETA_UPLOADS).resolve()
    ruta = (base / url.removeprefix("/uploads/")).resolve()
    if base not in ruta.parents:
        return False
    try:
        ruta.unlink(missing_ok=True)
        return True
    except OSError as error:
        log.warning("No se pudo borrar %s: %s", ruta, error)
        return False


@router.delete("/reportes/{id_reporte}")
def eliminar_reporte(id_reporte: int = PathParam(ge=1), admin: dict = Depends(usuario_admin)):
    """Elimina el reporte para siempre: sus votos, comentarios, avisos e historial se borran
    en cascada (claves foráneas ON DELETE CASCADE) y sus fotos se borran del disco.

    Como el historial del reporte desaparece con él, la eliminación queda en el registro
    de la API (quién, cuándo y qué reporte).
    """
    with transaccion() as cursor:
        cursor.execute(
            "SELECT id_reporte, estado, id_categoria FROM reporte WHERE id_reporte = %s FOR UPDATE",
            (id_reporte,),
        )
        reporte = cursor.fetchone()
        if reporte is None:
            raise HTTPException(status_code=404, detail="Reporte no encontrado")
        cursor.execute("SELECT url_archivo FROM reporte_imagen WHERE id_reporte = %s", (id_reporte,))
        archivos = [f["url_archivo"] for f in cursor.fetchall()]
        cursor.execute(
            """
            SELECT i.url_archivo FROM comentario_imagen i
            JOIN comentario c ON c.id_comentario = i.id_comentario
            WHERE c.id_reporte = %s
            """,
            (id_reporte,),
        )
        archivos += [f["url_archivo"] for f in cursor.fetchall()]
        cursor.execute("DELETE FROM reporte WHERE id_reporte = %s", (id_reporte,))
    # Los archivos se borran después de confirmar: si la BD fallara, las fotos siguen ahí.
    borrados = sum(_borrar_archivo(url) for url in archivos)
    log.warning(
        "Reporte #%s (estado %s) eliminado por el admin #%s; %s archivos borrados",
        id_reporte, reporte["estado"], admin["id_usuario"], borrados,
    )
    _resincronizar()
    return {"id_reporte": id_reporte, "eliminado": True, "archivos_borrados": borrados}


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


@router.get("/reportes/{id_reporte}/comentarios")
def listar_comentarios_reporte(id_reporte: int = PathParam(ge=1)):
    """Todos los comentarios del reporte (también ocultos y eliminados), con alias como en la app."""
    reporte = consultar("SELECT id_usuario FROM reporte WHERE id_reporte = %s", (id_reporte,))
    if not reporte:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    filas = comentarios_de_reporte(id_reporte)
    alias = mapa_alias(id_reporte, reporte[0]["id_usuario"], filas)
    return [
        {
            "id_comentario": f["id_comentario"],
            "id_comentario_padre": f["id_comentario_padre"],
            "autor": alias.get(f["id_usuario"]),
            "contenido": f["contenido"],
            "imagen": f["imagen"],
            "estado": f["estado"],
            "fecha_creacion": f["fecha_creacion"],
        }
        for f in filas
    ]


@router.patch("/comentarios/{id_comentario}/estado")
def cambiar_estado_comentario(datos: CambioEstadoComentario, id_comentario: int = PathParam(ge=1)):
    """Oculta un comentario (deja de verse en la app) o lo vuelve a publicar."""
    with transaccion() as cursor:
        cursor.execute("SELECT estado FROM comentario WHERE id_comentario = %s FOR UPDATE", (id_comentario,))
        fila = cursor.fetchone()
        if fila is None:
            raise HTTPException(status_code=404, detail="Comentario no encontrado")
        if fila["estado"] == "ELIMINADO":
            raise HTTPException(status_code=409, detail="Este comentario ya fue eliminado")
        if fila["estado"] == datos.estado:
            raise HTTPException(status_code=409, detail=f"El comentario ya está {datos.estado.lower()}")
        cursor.execute("UPDATE comentario SET estado = %s WHERE id_comentario = %s", (datos.estado, id_comentario))
    return {"id_comentario": id_comentario, "estado": datos.estado}


@router.delete("/comentarios/{id_comentario}")
def eliminar_comentario(id_comentario: int = PathParam(ge=1), admin: dict = Depends(usuario_admin)):
    """Elimina un comentario mal intencionado: queda como ELIMINADO (igual que cuando lo
    borra su autor, así las respuestas no quedan colgando) y su foto se borra del disco,
    porque estando oculta igual se podía abrir con su enlace."""
    with transaccion() as cursor:
        cursor.execute("SELECT estado FROM comentario WHERE id_comentario = %s FOR UPDATE", (id_comentario,))
        fila = cursor.fetchone()
        if fila is None:
            raise HTTPException(status_code=404, detail="Comentario no encontrado")
        if fila["estado"] == "ELIMINADO":
            raise HTTPException(status_code=409, detail="Este comentario ya fue eliminado")
        cursor.execute("SELECT url_archivo FROM comentario_imagen WHERE id_comentario = %s", (id_comentario,))
        archivos = [f["url_archivo"] for f in cursor.fetchall()]
        cursor.execute("DELETE FROM comentario_imagen WHERE id_comentario = %s", (id_comentario,))
        cursor.execute("UPDATE comentario SET estado = 'ELIMINADO' WHERE id_comentario = %s", (id_comentario,))
    for url in archivos:
        _borrar_archivo(url)
    log.warning("Comentario #%s eliminado por el admin #%s", id_comentario, admin["id_usuario"])
    return {"id_comentario": id_comentario, "estado": "ELIMINADO"}


@router.post("/comentarios/{id_comentario}/suspender-autor")
def suspender_autor_comentario(id_comentario: int = PathParam(ge=1)):
    """Suspende a quien escribió el comentario sin revelar su identidad en el panel."""
    with transaccion() as cursor:
        cursor.execute("SELECT id_usuario FROM comentario WHERE id_comentario = %s", (id_comentario,))
        comentario = cursor.fetchone()
        if comentario is None:
            raise HTTPException(status_code=404, detail="Comentario no encontrado")
        usuario = _usuario_moderable(cursor, comentario["id_usuario"])
        if usuario["estado"] == "SUSPENDIDO":
            raise HTTPException(status_code=409, detail="Quien escribió este comentario ya está suspendido")
        _suspender(cursor, usuario["id_usuario"])
    return {"id_comentario": id_comentario, "estado_autor": "SUSPENDIDO"}


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


# -----------------------------------------------------------------------------
# Grupos vecinales. El admin general los ve todos (también los cerrados) y
# puede cerrarlos o reabrirlos; los miembros siguen apareciendo solo como total.


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
        cursor.execute(
            "SELECT id_creador, activo FROM grupo WHERE id_grupo = %s FOR UPDATE",
            (id_grupo,),
        )
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
                raise HTTPException(
                    status_code=409,
                    detail="Quien creó este grupo ya administra otro grupo activo",
                )
        cursor.execute("UPDATE grupo SET activo = %s WHERE id_grupo = %s", (1 if datos.activo else 0, id_grupo))
    return {"id_grupo": id_grupo, "activo": datos.activo}


# -----------------------------------------------------------------------------
# Grafo (Neo4j). Ver app/grafo.py: los usuarios aparecen con seudónimo.
#
# Tres secciones, cada una responde una pregunta del administrador:
#   - Cuentas sospechosas: ¿hay grupos que se confirman entre ellos para inflar reportes?
#   - Reputación: ¿de quién me puedo fiar? (ver app/analisis_grafo.py)
#   - Incidentes: ¿estos reportes son el mismo hecho? (ver app/incidentes.py)
# Además, cualquier elemento se puede poner "en foco" para ver sus conexiones.

TIPOS_NODO = (
    "Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura", "Coordinacion", "Incidente", "Grupo",
)
MAXIMO_RELACIONES_FOCO = 90


def _etiqueta(tipo: str, datos: dict) -> str:
    if tipo == "Usuario":
        return datos.get("alias") or f"Vecino {datos.get('id')}"
    if tipo == "Reporte":
        return f"#{datos.get('id')}"
    if tipo == "Coordinacion":
        return f"Grupo de {datos.get('tamano', '?')} cuentas"
    if tipo == "Incidente":
        return f"Incidente #{datos.get('id')}"
    return str(datos.get("nombre") or datos.get("id"))


def _nodo(tipo: str, datos: dict) -> dict:
    return {"clave": f"{tipo}:{datos['id']}", "tipo": tipo, "etiqueta": _etiqueta(tipo, datos), "datos": datos}


def _grafo_o_503(funcion):
    try:
        return funcion()
    except grafo.GrafoNoDisponible as error:
        raise HTTPException(status_code=503, detail=str(error))


@router.get("/grafo/resumen")
def resumen_grafo():
    """Cuántos casos hay en cada sección, para los contadores de la pestaña."""

    def consultar_resumen():
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

    return _grafo_o_503(consultar_resumen)


@router.get("/grafo/sospechosos")
def cuentas_sospechosas():
    """Grupos de cuentas que se confirman los reportes entre ellas, del más sospechoso al menos."""

    def consultar_sospechosos():
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
                **_nodo("Coordinacion", f["grupo"]),
                "miembros": [_nodo("Usuario", m) for m in f["miembros"]],
                # Por qué es sospechoso: cada voto dentro del grupo y cuántos dieron afuera.
                "evidencia": [e for e in evidencia if e["grupo"] == f["grupo"]["id"]],
                "confirmaciones_afuera": externas.get(f["grupo"]["id"], 0),
            }
            for f in filas
        ]

    return _grafo_o_503(consultar_sospechosos)


@router.post("/grafo/sospechosos/{id_grupo}/suspender")
def suspender_sospechosos(id_grupo: int = PathParam(ge=1)):
    """Suspende todas las cuentas del grupo (salvo las administradoras) y rehace el grafo."""
    miembros = _grafo_o_503(lambda: grafo.consultar_grafo(
        "MATCH (:Coordinacion {id: $id})<-[:MIEMBRO_DE]-(u:Usuario) RETURN u.id AS id",
        id=id_grupo,
    ))
    if not miembros:
        raise HTTPException(status_code=404, detail="Ese grupo ya no está entre los sospechosos")
    suspendidas = []
    with transaccion() as cursor:
        for m in miembros:
            cursor.execute("SELECT email, estado FROM usuario WHERE id_usuario = %s FOR UPDATE", (m["id"],))
            usuario = cursor.fetchone()
            if usuario is None or usuario["estado"] in ("SUSPENDIDO", "ELIMINADO"):
                continue
            if usuario["email"].strip().lower() in CORREOS_ADMIN:
                continue
            _suspender(cursor, m["id"])
            suspendidas.append(m["id"])
    _resincronizar()
    return {"id_grupo": id_grupo, "suspendidas": len(suspendidas), "ids": suspendidas}


@router.get("/grafo/reputacion")
def reputacion(
    orden: Literal["baja", "alta"] = "baja",
    limite: int = Query(30, ge=1, le=200),
):
    """Vecinos ordenados por reputación (por defecto, los menos confiables primero)."""

    def consultar_reputacion():
        direccion = "ASC" if orden == "baja" else "DESC"
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
        return [
            {**_nodo("Usuario", f["u"]), "reportes": f["reportes"], "sospechoso": f["sospechoso"]}
            for f in filas
        ]

    return _grafo_o_503(consultar_reputacion)


@router.get("/grafo/incidentes")
def incidentes_agrupados(
    abiertos: bool = True,
    limite: int = Query(30, ge=1, le=200),
):
    """Incidentes con más de un reporte, del más reciente al más antiguo."""

    def consultar_incidentes():
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
                **_nodo("Incidente", f["i"]),
                "lugar": f["lugar"],
                "vigentes": f["vigentes"],
                "reportes": [_nodo("Reporte", r) for r in f["reportes"]],
            }
            for f in filas
        ]

    return _grafo_o_503(consultar_incidentes)


class CambioEstadoIncidente(BaseModel):
    estado: Literal["VALIDADO", "DESCARTADO", "RESUELTO"]
    motivo: str | None = Field(None, max_length=200)


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
    from app.rutas.reportes import reportes_del_incidente

    grupo = reportes_del_incidente(id_reporte)
    if not grupo:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    motivo = (datos.motivo or "").strip()
    motivo = (
        f"Panel de administración (incidente #{grupo[0]['id_reporte']}): {motivo}" if motivo
        else f"Incidente #{grupo[0]['id_reporte']} moderado desde el panel de administración"
    )
    cambiados = []
    with transaccion() as cursor:
        for r in grupo:
            cursor.execute("SELECT estado FROM reporte WHERE id_reporte = %s FOR UPDATE", (r["id_reporte"],))
            fila = cursor.fetchone()
            if fila is None or fila["estado"] == datos.estado:
                continue
            cursor.execute("UPDATE reporte SET estado = %s WHERE id_reporte = %s", (datos.estado, r["id_reporte"]))
            cursor.execute(
                """
                INSERT INTO reporte_estado_historial (
                    id_reporte, estado_anterior, estado_nuevo, id_usuario_responsable, motivo
                ) VALUES (%s, %s, %s, %s, %s)
                """,
                (r["id_reporte"], fila["estado"], datos.estado, admin["id_usuario"], motivo),
            )
            cambiados.append(r["id_reporte"])
    _resincronizar()
    return {"id_incidente": grupo[0]["id_reporte"], "estado": datos.estado, "reportes": cambiados}


def _resincronizar() -> None:
    """Tras moderar, el grafo se rehace para reflejar el cambio (si Neo4j no está, no importa)."""
    try:
        grafo.sincronizar()
    except Exception:  # noqa: BLE001 - el cambio en MySQL ya quedó hecho
        pass


# -- Explorador de la red ------------------------------------------------------

_PROYECCION_RELACION = """
RETURN labels(startNode(rel))[0] AS tipo_a, properties(startNode(rel)) AS a,
       type(rel) AS tipo_rel, properties(rel) AS datos_rel,
       labels(endNode(rel))[0] AS tipo_b, properties(endNode(rel)) AS b
"""


def _armar_red(filas: list[dict], extra_nodos: list[dict] | None = None) -> dict:
    """Nodos y aristas sin repetir a partir de filas (a)-[rel]->(b)."""
    nodos: dict[str, dict] = {n["clave"]: n for n in (extra_nodos or [])}
    aristas = []
    for fila in filas:
        a, b = _nodo(fila["tipo_a"], fila["a"]), _nodo(fila["tipo_b"], fila["b"])
        nodos.setdefault(a["clave"], a)
        nodos.setdefault(b["clave"], b)
        aristas.append({"origen": a["clave"], "destino": b["clave"], "tipo": fila["tipo_rel"], "datos": fila["datos_rel"] or {}})
    return {"nodos": list(nodos.values()), "aristas": aristas}


def _comunidades(red: dict) -> None:
    """Marca cada nodo con su comunidad: grupos de vecinos y reportes unidos por votos o
    creación. Lugares y categorías no cuentan (unirían a todos por igual)."""
    padre: dict[str, str] = {}

    def raiz(x: str) -> str:
        padre.setdefault(x, x)
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x

    for arista in red["aristas"]:
        if arista["tipo"] in ("CREO", "VOTO", "CONFIRMA_A", "DESMIENTE_A", "AGRUPA", "MIEMBRO_DE", "INTEGRA", "COMPARTIDO_EN"):
            padre[raiz(arista["origen"])] = raiz(arista["destino"])
    tamanos: dict[str, int] = {}
    for n in red["nodos"]:
        tamanos[raiz(n["clave"])] = tamanos.get(raiz(n["clave"]), 0) + 1
    # Numeradas de la más grande a la más chica; las de un solo nodo quedan sin comunidad.
    orden = {r: i for i, r in enumerate(sorted((r for r, t in tamanos.items() if t > 1), key=lambda r: -tamanos[r]))}
    for n in red["nodos"]:
        n["comunidad"] = orden.get(raiz(n["clave"]))


@router.get("/grafo/red")
def red_completa(
    modo: Literal["vecinos", "completa"] = "vecinos",
    dias: int | None = Query(None, ge=1, le=3650),
    capas: str = Query("lugares,incidentes,sospechosos,grupos", max_length=100),
    limite: int = Query(300, ge=10, le=1000),
):
    """La red para el explorador del panel.

    - modo=vecinos: solo vecinos, unidos por quién confirma o desmiente a quién; el
      peso de cada unión es cuántas veces lo hizo.
    - modo=completa: vecinos y reportes, más las capas pedidas (lugares, categorias,
      zonas, incidentes, sospechosos, grupos).
    `dias` limita a la actividad de los últimos N días (sin él, toda la historia).
    """
    pedidas = {c.strip() for c in capas.split(",") if c.strip()}
    desde = None
    if dias:
        from datetime import datetime, timedelta

        desde = (datetime.now() - timedelta(days=dias)).isoformat()

    def consultar_red():
        if modo == "vecinos":
            filas = grafo.consultar_grafo(
                """
                MATCH (a:Usuario)-[v:VOTO]->(r:Reporte)<-[:CREO]-(b:Usuario)
                WHERE a <> b AND ($desde IS NULL OR r.fecha_creacion >= $desde)
                WITH a, b, sum(CASE v.tipo WHEN 'CONFIRMA' THEN 1 ELSE 0 END) AS confirma,
                           sum(CASE v.tipo WHEN 'DESMIENTE' THEN 1 ELSE 0 END) AS desmiente
                ORDER BY confirma + desmiente DESC LIMIT $limite
                RETURN 'Usuario' AS tipo_a, properties(a) AS a,
                       CASE WHEN confirma >= desmiente THEN 'CONFIRMA_A' ELSE 'DESMIENTE_A' END AS tipo_rel,
                       {peso: confirma + desmiente, confirma: confirma, desmiente: desmiente} AS datos_rel,
                       'Usuario' AS tipo_b, properties(b) AS b
                """,
                desde=desde,
                limite=limite,
            )
            # También los vecinos que reportaron sin recibir votos, para que la red esté completa.
            solos = grafo.consultar_grafo(
                """
                MATCH (u:Usuario)-[:CREO]->(r:Reporte)
                WHERE NOT u.es_admin AND ($desde IS NULL OR r.fecha_creacion >= $desde)
                RETURN DISTINCT properties(u) AS u LIMIT $limite
                """,
                desde=desde,
                limite=limite,
            )
            red = _armar_red(filas, [_nodo("Usuario", f["u"]) for f in solos])
        else:
            tipos = ["CREO", "VOTO"]
            if "lugares" in pedidas:
                tipos.append("OCURRIO_EN")
            if "categorias" in pedidas:
                tipos.append("ES_DE")
            if "zonas" in pedidas:
                tipos += ["TIENE_ZONA", "ALERTO_A"]
            if "incidentes" in pedidas:
                tipos.append("AGRUPA")
            if "sospechosos" in pedidas:
                tipos.append("MIEMBRO_DE")
            if "grupos" in pedidas:
                tipos.append("COMPARTIDO_EN")
            filas = grafo.consultar_grafo(
                f"""
                MATCH (r:Reporte) WHERE $desde IS NULL OR r.fecha_creacion >= $desde
                WITH r ORDER BY r.fecha_creacion DESC LIMIT $limite
                WITH collect(r) AS reportes
                UNWIND reportes AS r
                MATCH (r)-[rel:{"|".join(tipos)}]-(x)
                WITH DISTINCT rel
                {_PROYECCION_RELACION}
                """,
                desde=desde,
                limite=limite,
            )
            if "sospechosos" in pedidas:
                filas += grafo.consultar_grafo("MATCH ()-[rel:MIEMBRO_DE]->() " + _PROYECCION_RELACION)
            if "grupos" in pedidas:
                filas += grafo.consultar_grafo("MATCH ()-[rel:INTEGRA]->(:Grupo) " + _PROYECCION_RELACION)
            red = _armar_red(filas)
        _comunidades(red)
        return {**red, "sincronizacion": grafo.ultima_sincronizacion}

    return _grafo_o_503(consultar_red)


@router.get("/grafo/buscar")
def buscar_en_grafo(q: str = Query(min_length=1, max_length=60)):
    """Vecinos por seudónimo, reportes o incidentes por número, y lugares o categorías por nombre."""
    texto = q.strip().lstrip("#").lower()
    numero = int(texto) if texto.isdigit() else -1

    def consultar_busqueda():
        filas = grafo.consultar_grafo(
            """
            CALL () {
                MATCH (u:Usuario) WHERE toLower(u.alias) CONTAINS $texto
                RETURN 'Usuario' AS tipo, properties(u) AS n, 0 AS orden LIMIT 8
                UNION
                MATCH (r:Reporte) WHERE r.id = $numero
                RETURN 'Reporte' AS tipo, properties(r) AS n, 1 AS orden
                UNION
                MATCH (i:Incidente) WHERE i.id = $numero
                RETURN 'Incidente' AS tipo, properties(i) AS n, 2 AS orden
                UNION
                MATCH (l) WHERE (l:Localidad OR l:Comuna OR l:Categoria OR l:Grupo) AND toLower(l.nombre) CONTAINS $texto
                RETURN labels(l)[0] AS tipo, properties(l) AS n, 3 AS orden LIMIT 8
            }
            RETURN tipo, n ORDER BY orden LIMIT 15
            """,
            texto=texto,
            numero=numero,
        )
        return [_nodo(f["tipo"], f["n"]) for f in filas]

    return _grafo_o_503(consultar_busqueda)


@router.get("/grafo/camino")
def camino_mas_corto(
    desde: str = Query(pattern=r"^[A-Za-z]+:\d+$"),
    hasta: str = Query(pattern=r"^[A-Za-z]+:\d+$"),
):
    """El camino más corto entre dos elementos (hasta 8 pasos), con shortestPath de Neo4j."""
    (tipo_a, id_a), (tipo_b, id_b) = (c.split(":") for c in (desde, hasta))
    if tipo_a not in TIPOS_NODO or tipo_b not in TIPOS_NODO:
        raise HTTPException(status_code=422, detail="Tipo de nodo no válido")
    if desde == hasta:
        raise HTTPException(status_code=422, detail="Elige dos elementos distintos")

    # Solo relaciones reales: los grupos sospechosos e incidentes los calcula el sistema
    # y no cuentan como camino, salvo que uno de los extremos sea justamente uno de ellos.
    relaciones = ["CREO", "VOTO", "OCURRIO_EN", "ES_DE", "PERTENECE_A", "TIENE_ZONA", "ALERTO_A", "INTEGRA", "COMPARTIDO_EN"]
    if "Coordinacion" in (tipo_a, tipo_b):
        relaciones.append("MIEMBRO_DE")
    if "Incidente" in (tipo_a, tipo_b):
        relaciones.append("AGRUPA")

    def consultar_camino():
        filas = grafo.consultar_grafo(
            f"""
            MATCH (a:{tipo_a} {{id: $id_a}}), (b:{tipo_b} {{id: $id_b}})
            MATCH p = shortestPath((a)-[:{"|".join(relaciones)}*..8]-(b))
            UNWIND relationships(p) AS rel
            {_PROYECCION_RELACION}
            """,
            id_a=int(id_a),
            id_b=int(id_b),
        )
        if not filas:
            raise HTTPException(status_code=404, detail="Esos dos elementos no están conectados")
        red = _armar_red(filas)
        return {**red, "pasos": len(filas)}

    return _grafo_o_503(consultar_camino)


@router.get("/grafo/nodo/{tipo}/{id_nodo}")
def foco_grafo(
    tipo: Literal[
        "Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura", "Coordinacion", "Incidente", "Grupo"
    ],
    id_nodo: int = PathParam(ge=1),
):
    """El elemento en foco y lo conectado hasta 2 pasos, con el anillo de cada nodo (0, 1 o 2)."""
    # Cypher no acepta la etiqueta como parámetro: va en el texto, y por eso
    # solo se aceptan los valores fijos de TIPOS_NODO.
    if tipo not in TIPOS_NODO:
        raise HTTPException(status_code=422, detail="Tipo de nodo no válido")

    def consultar_foco():
        centro = grafo.consultar_grafo(f"MATCH (n:{tipo} {{id: $id}}) RETURN properties(n) AS n", id=id_nodo)
        if not centro:
            raise HTTPException(status_code=404, detail="Ese elemento no está en el grafo")
        # Primero las relaciones directas y después las del segundo anillo, así el
        # tope de relaciones nunca deja fuera el primer anillo.
        filas = grafo.consultar_grafo(
            f"""
            MATCH (n:{tipo} {{id: $id}})-[r1]-(x)
            WITH n, collect(DISTINCT r1) AS primeras, collect(DISTINCT x) AS vecinos
            UNWIND vecinos AS x
            OPTIONAL MATCH (x)-[r2]-(y) WHERE y <> n
            WITH primeras, collect(DISTINCT r2) AS segundas
            UNWIND primeras + segundas AS rel
            WITH DISTINCT rel LIMIT $maximo
            RETURN labels(startNode(rel))[0] AS tipo_a, properties(startNode(rel)) AS a,
                   type(rel) AS tipo_rel, properties(rel) AS datos_rel,
                   labels(endNode(rel))[0] AS tipo_b, properties(endNode(rel)) AS b
            """,
            id=id_nodo,
            maximo=MAXIMO_RELACIONES_FOCO,
        )
        foco = _nodo(tipo, centro[0]["n"])
        nodos = {foco["clave"]: foco}
        aristas = []
        for fila in filas:
            a, b = _nodo(fila["tipo_a"], fila["a"]), _nodo(fila["tipo_b"], fila["b"])
            nodos.setdefault(a["clave"], a)
            nodos.setdefault(b["clave"], b)
            aristas.append({"origen": a["clave"], "destino": b["clave"], "tipo": fila["tipo_rel"], "datos": fila["datos_rel"] or {}})

        # Anillo de cada nodo: distancia (en pasos) desde el foco.
        anillo = {foco["clave"]: 0}
        for nivel in (1, 2):
            for arista in aristas:
                for desde, hacia in ((arista["origen"], arista["destino"]), (arista["destino"], arista["origen"])):
                    if anillo.get(desde) == nivel - 1 and hacia not in anillo:
                        anillo[hacia] = nivel
        lista = [{**n, "anillo": anillo[c]} for c, n in nodos.items() if c in anillo]
        visibles = {n["clave"] for n in lista}
        return {
            "foco": foco["clave"],
            "nodos": lista,
            "aristas": [a for a in aristas if a["origen"] in visibles and a["destino"] in visibles],
            "sincronizacion": grafo.ultima_sincronizacion,
        }

    return _grafo_o_503(consultar_foco)


@router.post("/grafo/sincronizar")
def sincronizar_grafo():
    """Rehace el grafo ahora, sin esperar la sincronización automática."""
    return _grafo_o_503(lambda: {"totales": grafo.sincronizar(), "sincronizacion": grafo.ultima_sincronizacion})
