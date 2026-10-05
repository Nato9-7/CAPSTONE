from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field

from app import grafo
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


# -----------------------------------------------------------------------------
# Grafo (Neo4j). Ver app/grafo.py: los usuarios aparecen con seudónimo.

TIPOS_NODO = ("Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura")

# Cada consulta devuelve filas (a)-[rel]->(b) con esta misma forma.
_PROYECCION = """
RETURN DISTINCT labels(a)[0] AS tipo_a, properties(a) AS a, type(rel) AS tipo_rel, properties(rel) AS rel,
       labels(b)[0] AS tipo_b, properties(b) AS b
"""


def _etiqueta(tipo: str, datos: dict) -> str:
    if tipo == "Usuario":
        return datos.get("alias") or f"Vecino {datos.get('id')}"
    if tipo == "Reporte":
        return f"#{datos.get('id')}"
    return str(datos.get("nombre") or datos.get("id"))


def _armar_grafo(filas: list[dict], hallazgos: list[str] | None = None) -> dict:
    nodos, aristas = {}, []
    for fila in filas:
        claves = []
        for lado in ("a", "b"):
            tipo, datos = fila[f"tipo_{lado}"], fila[lado]
            clave = f"{tipo}:{datos['id']}"
            nodos.setdefault(clave, {"clave": clave, "tipo": tipo, "etiqueta": _etiqueta(tipo, datos), "datos": datos})
            claves.append(clave)
        aristas.append({"origen": claves[0], "destino": claves[1], "tipo": fila["tipo_rel"], "datos": fila["rel"] or {}})
    return {
        "nodos": list(nodos.values()),
        "aristas": aristas,
        "hallazgos": hallazgos or [],
        "sincronizacion": grafo.ultima_sincronizacion,
    }


def _grafo_o_503(funcion):
    try:
        return funcion()
    except grafo.GrafoNoDisponible as error:
        raise HTTPException(status_code=503, detail=str(error))


@router.get("/grafo")
def ver_grafo(
    vista: Literal["general", "votos", "sospechosos"] = "general",
    limite: int = Query(40, ge=5, le=200),
):
    """Subgrafo para el panel. `limite` acota cuántos reportes o usuarios se incluyen."""
    return _grafo_o_503(lambda: _VISTAS[vista](limite))


def _vista_general(limite: int) -> dict:
    filas = grafo.consultar_grafo(
        """
        MATCH (r:Reporte) WITH r ORDER BY r.fecha_creacion DESC LIMIT $limite
        WITH collect(r) AS reportes
        MATCH (a)-[rel]->(b) WHERE a IN reportes OR b IN reportes
        """ + _PROYECCION,
        limite=limite,
    )
    lugares = grafo.consultar_grafo(
        """
        MATCH (r:Reporte)-[:OCURRIO_EN]->(l)
        WHERE r.fecha_creacion >= toString(localdatetime() - duration('P30D'))
        RETURN l.nombre AS lugar, count(r) AS total ORDER BY total DESC LIMIT 3
        """
    )
    hallazgos = [f"{l['lugar']}: {l['total']} reportes en los últimos 30 días" for l in lugares]
    return _armar_grafo(filas, hallazgos)


def _vista_votos(limite: int) -> dict:
    # Une a quien vota con quien creó el reporte: muestra quién respalda a quién.
    filas = grafo.consultar_grafo(
        """
        MATCH (a:Usuario)-[v:VOTO]->(:Reporte)<-[:CREO]-(b:Usuario) WHERE a <> b
        WITH a, b, sum(CASE v.tipo WHEN 'CONFIRMA' THEN 1 ELSE 0 END) AS confirma,
                   sum(CASE v.tipo WHEN 'DESMIENTE' THEN 1 ELSE 0 END) AS desmiente
        ORDER BY confirma + desmiente DESC LIMIT $limite
        RETURN 'Usuario' AS tipo_a, properties(a) AS a,
               CASE WHEN confirma >= desmiente THEN 'CONFIRMA_A' ELSE 'DESMIENTE_A' END AS tipo_rel,
               {confirma: confirma, desmiente: desmiente} AS rel,
               'Usuario' AS tipo_b, properties(b) AS b
        """,
        limite=limite,
    )
    return _armar_grafo(filas, _hallazgos_mutuos())


def _hallazgos_mutuos() -> list[str]:
    pares = grafo.consultar_grafo(
        """
        MATCH (a:Usuario)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(b:Usuario),
              (b)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(a)
        WHERE a.id < b.id
        RETURN DISTINCT a.alias AS a, b.alias AS b LIMIT 10
        """
    )
    return [f"{p['a']} y {p['b']} se confirman los reportes mutuamente" for p in pares]


def _vista_sospechosos(limite: int) -> dict:
    # Pares que se confirman entre sí (con los votos y los reportes involucrados),
    # y cuentas con 2 o más reportes descartados.
    filas = grafo.consultar_grafo(
        """
        CALL () {
            MATCH (a:Usuario)-[rel:VOTO {tipo: 'CONFIRMA'}]->(b:Reporte)<-[:CREO]-(o:Usuario),
                  (o)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(a)
            WHERE a <> o
            RETURN a, rel, b
            UNION
            MATCH (a:Usuario)-[rel:CREO]->(b:Reporte)<-[:VOTO {tipo: 'CONFIRMA'}]-(o:Usuario),
                  (o)-[:CREO]->(:Reporte)<-[:VOTO {tipo: 'CONFIRMA'}]-(a)
            WHERE a <> o
            RETURN a, rel, b
            UNION
            MATCH (a:Usuario)-[rel:CREO]->(b:Reporte {estado: 'DESCARTADO'})
            WITH a, collect([rel, b]) AS descartados WHERE size(descartados) >= 2
            UNWIND descartados AS par
            RETURN a, par[0] AS rel, par[1] AS b
        }
        WITH a, rel, b LIMIT $limite
        """ + _PROYECCION,
        limite=limite * 3,
    )
    descartes = grafo.consultar_grafo(
        """
        MATCH (u:Usuario)-[:CREO]->(r:Reporte)
        WITH u, count(r) AS total, sum(CASE r.estado WHEN 'DESCARTADO' THEN 1 ELSE 0 END) AS descartados
        WHERE descartados >= 2
        RETURN u.alias AS alias, descartados, total ORDER BY descartados DESC LIMIT 10
        """
    )
    hallazgos = _hallazgos_mutuos() + [
        f"{d['alias']} tiene {d['descartados']} de {d['total']} reportes descartados" for d in descartes
    ]
    return _armar_grafo(filas, hallazgos or ["No se encontraron patrones sospechosos."])


_VISTAS = {"general": _vista_general, "votos": _vista_votos, "sospechosos": _vista_sospechosos}


@router.get("/grafo/nodo/{tipo}/{id_nodo}")
def vecindario(
    tipo: Literal["Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura"],
    id_nodo: int = PathParam(ge=1),
    limite: int = Query(60, ge=5, le=200),
):
    """Todo lo conectado directamente con un nodo, para seguir explorando desde el panel."""
    # Cypher no acepta la etiqueta como parámetro: va en el texto, y por eso
    # solo se aceptan los valores fijos de TIPOS_NODO.
    if tipo not in TIPOS_NODO:
        raise HTTPException(status_code=422, detail="Tipo de nodo no válido")

    def consultar_vecindario():
        filas = grafo.consultar_grafo(
            f"""
            MATCH (n:{tipo} {{id: $id}})-[rel]-()
            WITH rel LIMIT $limite
            WITH rel, startNode(rel) AS a, endNode(rel) AS b
            """ + _PROYECCION,
            id=id_nodo,
            limite=limite,
        )
        if not filas and not grafo.consultar_grafo(f"MATCH (n:{tipo} {{id: $id}}) RETURN n.id AS id", id=id_nodo):
            raise HTTPException(status_code=404, detail="Ese elemento no está en el grafo")
        return _armar_grafo(filas)

    return _grafo_o_503(consultar_vecindario)


@router.post("/grafo/sincronizar")
def sincronizar_grafo():
    """Rehace el grafo ahora, sin esperar la sincronización automática."""
    return _grafo_o_503(lambda: {"totales": grafo.sincronizar(), "sincronizacion": grafo.ultima_sincronizacion})
