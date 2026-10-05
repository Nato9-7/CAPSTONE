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
#
# El panel trabaja con "foco": se elige un elemento y se muestra con sus
# conexiones en dos anillos. /grafo/inicio da los hallazgos y los puntos de partida.

TIPOS_NODO = ("Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura")
MAXIMO_RELACIONES_FOCO = 90


def _etiqueta(tipo: str, datos: dict) -> str:
    if tipo == "Usuario":
        return datos.get("alias") or f"Vecino {datos.get('id')}"
    if tipo == "Reporte":
        return f"#{datos.get('id')}"
    return str(datos.get("nombre") or datos.get("id"))


def _nodo(tipo: str, datos: dict) -> dict:
    return {"clave": f"{tipo}:{datos['id']}", "tipo": tipo, "etiqueta": _etiqueta(tipo, datos), "datos": datos}


def _grafo_o_503(funcion):
    try:
        return funcion()
    except grafo.GrafoNoDisponible as error:
        raise HTTPException(status_code=503, detail=str(error))


@router.get("/grafo/inicio")
def inicio_grafo():
    """Hallazgos (lo que conviene revisar) y elementos desde donde empezar a explorar."""

    def consultar_inicio():
        hallazgos = []
        for p in grafo.consultar_grafo(
            """
            MATCH (a:Usuario)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(b:Usuario),
                  (b)-[:VOTO {tipo: 'CONFIRMA'}]->(:Reporte)<-[:CREO]-(a)
            WHERE a.id < b.id
            RETURN DISTINCT properties(a) AS a, b.alias AS otro LIMIT 8
            """
        ):
            hallazgos.append({
                "nivel": "alerta",
                "texto": f"{p['a']['alias']} y {p['otro']} se confirman los reportes mutuamente",
                "nodo": _nodo("Usuario", p["a"]),
            })
        for d in grafo.consultar_grafo(
            """
            MATCH (u:Usuario)-[:CREO]->(r:Reporte)
            WITH u, count(r) AS total, sum(CASE r.estado WHEN 'DESCARTADO' THEN 1 ELSE 0 END) AS descartados
            WHERE descartados >= 2
            RETURN properties(u) AS u, descartados, total ORDER BY descartados DESC LIMIT 8
            """
        ):
            hallazgos.append({
                "nivel": "alerta",
                "texto": f"{d['u']['alias']} tiene {d['descartados']} de {d['total']} reportes descartados",
                "nodo": _nodo("Usuario", d["u"]),
            })
        lugares = grafo.consultar_grafo(
            """
            MATCH (r:Reporte)-[:OCURRIO_EN]->(l)
            WHERE r.fecha_creacion >= toString(localdatetime() - duration('P30D'))
            RETURN labels(l)[0] AS tipo, properties(l) AS l, count(r) AS total
            ORDER BY total DESC LIMIT 6
            """
        )
        for l in lugares[:3]:
            hallazgos.append({
                "nivel": "info",
                "texto": f"{l['l']['nombre']}: {l['total']} reportes en los últimos 30 días",
                "nodo": _nodo(l["tipo"], l["l"]),
            })

        reportes = grafo.consultar_grafo(
            "MATCH (r:Reporte) RETURN properties(r) AS r ORDER BY r.fecha_creacion DESC LIMIT 8"
        )
        vecinos = grafo.consultar_grafo(
            """
            MATCH (u:Usuario)-[x:CREO|VOTO]->()
            WITH u, count(x) AS actividad ORDER BY actividad DESC LIMIT 8
            RETURN properties(u) AS u, actividad
            """
        )
        return {
            "hallazgos": hallazgos,
            "reportes": [_nodo("Reporte", r["r"]) for r in reportes],
            "vecinos": [{**_nodo("Usuario", v["u"]), "detalle": f"{v['actividad']} acciones"} for v in vecinos],
            "lugares": [{**_nodo(l["tipo"], l["l"]), "detalle": f"{l['total']} reportes"} for l in lugares],
            "sincronizacion": grafo.ultima_sincronizacion,
        }

    return _grafo_o_503(consultar_inicio)


@router.get("/grafo/nodo/{tipo}/{id_nodo}")
def foco_grafo(
    tipo: Literal["Usuario", "Reporte", "Categoria", "Comuna", "Localidad", "ZonaSegura"],
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
