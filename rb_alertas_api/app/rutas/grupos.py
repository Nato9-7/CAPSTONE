import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, Path as PathParam, Query
from pydantic import BaseModel, Field
import mysql.connector

from app.db import consultar, ejecutar, transaccion
from app.rutas.reportes import ADJETIVOS_SURICATA, alias_autor
from app.seguridad import usuario_actual

router = APIRouter()

# Prototipo: crear grupos será una función pagada (juntas de vecinos, edificios).
MAXIMO_GRUPOS_CREADOS = 1
MAXIMO_GRUPOS_POR_USUARIO = 5
RADIOS_PERMITIDOS = (500, 1000, 2000)
DIAS_VIGENCIA_CODIGO = 7

# Sin 0/O ni 1/I/L: el código se dicta y se escribe a mano.
ALFABETO_CODIGO = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LARGO_CODIGO = 8

# Con SRID 4326 MySQL lee el WKT como latitud-longitud; se fija el orden.
PUNTO_SQL = "ST_GeomFromText(%s, 4326, 'axis-order=long-lat')"


class DatosGrupo(BaseModel):
    nombre: str = Field(min_length=1, max_length=60)
    descripcion: str | None = Field(None, max_length=255)
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)
    radio_metros: int
    direccion_referencia: str | None = Field(None, max_length=255)


class CodigoInvitacion(BaseModel):
    codigo: str = Field(min_length=4, max_length=20)


def _nuevo_codigo() -> str:
    return "".join(secrets.choice(ALFABETO_CODIGO) for _ in range(LARGO_CODIGO))


def _normalizar_codigo(codigo: str) -> str:
    """Acepta el código con espacios, guiones o en minúsculas, como suele llegar al copiarlo."""
    return "".join(caracter for caracter in codigo.upper() if caracter.isalnum())


def alias_miembro(id_grupo: int, id_usuario: int) -> str:
    """Alias fijo del vecino dentro de un grupo, p. ej. «Suricata Serena 27».

    Depende del grupo, así el mismo vecino tiene alias distintos en grupos
    distintos y no se le puede seguir de un grupo a otro.
    """
    semilla = int.from_bytes(hashlib.sha256(f"alias-grupo:{id_grupo}:{id_usuario}".encode()).digest()[:8], "big")
    adjetivo = ADJETIVOS_SURICATA[semilla % len(ADJETIVOS_SURICATA)]
    numero = 10 + (semilla // len(ADJETIVOS_SURICATA)) % 90
    return f"Suricata {adjetivo} {numero}"


def _validar_datos(datos: DatosGrupo) -> tuple[str, str | None, str | None]:
    nombre = datos.nombre.strip()
    if not nombre:
        raise HTTPException(status_code=422, detail="Escribe un nombre para el grupo")
    if datos.radio_metros not in RADIOS_PERMITIDOS:
        raise HTTPException(status_code=422, detail="El radio debe ser 500, 1000 o 2000 metros")
    descripcion = (datos.descripcion or "").strip() or None
    direccion = (datos.direccion_referencia or "").strip() or None
    return nombre, descripcion, direccion


def _membresia(id_grupo: int, id_usuario: int) -> dict:
    """Rol de quien consulta en un grupo activo. 404 si no es miembro: no se revela si el grupo existe."""
    filas = consultar(
        """
        SELECT m.id_miembro, m.rol
        FROM grupo_miembro m
        JOIN grupo g ON g.id_grupo = m.id_grupo
        WHERE m.id_grupo = %s AND m.id_usuario = %s AND g.activo = 1
        """,
        (id_grupo, id_usuario),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="El grupo no existe")
    return filas[0]


def _solo_admin(id_grupo: int, id_usuario: int) -> None:
    if _membresia(id_grupo, id_usuario)["rol"] != "ADMIN":
        raise HTTPException(status_code=403, detail="Solo el administrador del grupo puede hacer esto")


def _total_grupos(id_usuario: int) -> int:
    filas = consultar(
        """
        SELECT COUNT(*) AS total
        FROM grupo_miembro m JOIN grupo g ON g.id_grupo = m.id_grupo
        WHERE m.id_usuario = %s AND g.activo = 1
        """,
        (id_usuario,),
    )
    return int(filas[0]["total"]) if filas else 0


def _grupo_json(fila: dict) -> dict:
    es_admin = fila["rol"] == "ADMIN"
    return {
        "id_grupo": fila["id_grupo"],
        "nombre": fila["nombre"],
        "descripcion": fila["descripcion"],
        "latitud": float(fila["latitud"]),
        "longitud": float(fila["longitud"]),
        "radio_metros": int(fila["radio_metros"]),
        "direccion_referencia": fila["direccion_referencia"],
        "rol": fila["rol"],
        "es_admin": es_admin,
        "total_miembros": int(fila["total_miembros"]),
        "ultimo_reporte": fila["ultimo_reporte"].isoformat() if fila["ultimo_reporte"] else None,
        # El código solo lo ve el admin, que es quien lo comparte y lo regenera.
        "codigo_invitacion": fila["codigo_invitacion"] if es_admin else None,
        "codigo_expira": fila["codigo_expira"].isoformat() if es_admin and fila["codigo_expira"] else None,
        "codigo_vencido": bool(fila["codigo_vencido"]) if es_admin else None,
        "fecha_creacion": fila["fecha_creacion"].isoformat() if fila["fecha_creacion"] else None,
    }


SELECT_GRUPO = """
    SELECT g.id_grupo, g.nombre, g.descripcion,
           ST_Latitude(g.centro) AS latitud, ST_Longitude(g.centro) AS longitud,
           g.radio_metros, g.direccion_referencia, g.codigo_invitacion, g.codigo_expira,
           (g.codigo_expira <= NOW()) AS codigo_vencido, g.fecha_creacion, m.rol,
           (SELECT COUNT(*) FROM grupo_miembro t WHERE t.id_grupo = g.id_grupo) AS total_miembros,
           (SELECT MAX(gr.fecha_publicacion) FROM grupo_reporte gr WHERE gr.id_grupo = g.id_grupo) AS ultimo_reporte
    FROM grupo g
    JOIN grupo_miembro m ON m.id_grupo = g.id_grupo AND m.id_usuario = %s
    WHERE g.activo = 1
"""


def _grupo_de_usuario(id_grupo: int, id_usuario: int) -> dict:
    filas = consultar(SELECT_GRUPO + " AND g.id_grupo = %s", (id_usuario, id_grupo))
    if not filas:
        raise HTTPException(status_code=404, detail="El grupo no existe")
    return _grupo_json(filas[0])


@router.get("/")
def listar_mis_grupos(usuario: dict = Depends(usuario_actual)):
    """Grupos de quien consulta, el de actividad más reciente primero."""
    id_usuario = usuario["id_usuario"]
    filas = consultar(
        SELECT_GRUPO + " ORDER BY COALESCE(ultimo_reporte, g.fecha_creacion) DESC",
        (id_usuario,),
    )
    creados = sum(1 for fila in filas if fila["rol"] == "ADMIN")
    return {
        "grupos": [_grupo_json(fila) for fila in filas],
        "maximo": MAXIMO_GRUPOS_POR_USUARIO,
        "puede_crear": creados < MAXIMO_GRUPOS_CREADOS and len(filas) < MAXIMO_GRUPOS_POR_USUARIO,
        "radios_permitidos": list(RADIOS_PERMITIDOS),
    }


@router.post("/", status_code=201)
def crear_grupo(datos: DatosGrupo, usuario: dict = Depends(usuario_actual)):
    id_usuario = usuario["id_usuario"]
    nombre, descripcion, direccion = _validar_datos(datos)

    creados = consultar(
        "SELECT COUNT(*) AS total FROM grupo WHERE id_creador = %s AND activo = 1",
        (id_usuario,),
    )
    if creados and creados[0]["total"] >= MAXIMO_GRUPOS_CREADOS:
        raise HTTPException(status_code=409, detail="Ya administras un grupo. Elimínalo para crear otro")
    if _total_grupos(id_usuario) >= MAXIMO_GRUPOS_POR_USUARIO:
        raise HTTPException(
            status_code=409,
            detail=f"Solo puedes estar en {MAXIMO_GRUPOS_POR_USUARIO} grupos. Sal de uno para crear otro",
        )

    punto_wkt = f"POINT({datos.longitud} {datos.latitud})"
    # Un choque de códigos es casi imposible (31^8), pero si pasa se reintenta.
    for _ in range(3):
        try:
            with transaccion() as cursor:
                cursor.execute(
                    f"""
                    INSERT INTO grupo (
                        id_creador, nombre, descripcion, centro, radio_metros,
                        direccion_referencia, codigo_invitacion, codigo_expira
                    ) VALUES (
                        %s, %s, %s, {PUNTO_SQL}, %s, %s, %s,
                        DATE_ADD(NOW(), INTERVAL %s DAY)
                    )
                    """,
                    (
                        id_usuario, nombre, descripcion, punto_wkt, datos.radio_metros,
                        direccion, _nuevo_codigo(), DIAS_VIGENCIA_CODIGO,
                    ),
                )
                id_grupo = cursor.lastrowid
                cursor.execute(
                    "INSERT INTO grupo_miembro (id_grupo, id_usuario, rol) VALUES (%s, %s, 'ADMIN')",
                    (id_grupo, id_usuario),
                )
            return _grupo_de_usuario(id_grupo, id_usuario)
        except mysql.connector.Error as error:
            if error.errno != 1062:
                raise HTTPException(status_code=400, detail=error.msg)
    raise HTTPException(status_code=503, detail="No se pudo generar el código del grupo. Inténtalo otra vez")


@router.get("/en-punto")
def grupos_en_punto(
    usuario: dict = Depends(usuario_actual),
    latitud: float = Query(ge=-90, le=90),
    longitud: float = Query(ge=-180, le=180),
):
    """Grupos de quien consulta cuyo círculo contiene el punto: los que puede
    elegir al crear un reporte en esa ubicación."""
    punto_wkt = f"POINT({longitud} {latitud})"
    return consultar(
        f"""
        SELECT g.id_grupo, g.nombre
        FROM grupo g
        JOIN grupo_miembro m ON m.id_grupo = g.id_grupo AND m.id_usuario = %s
        WHERE g.activo = 1
          AND ST_Distance_Sphere(g.centro, {PUNTO_SQL}) <= g.radio_metros
        ORDER BY g.nombre
        """,
        (usuario["id_usuario"], punto_wkt),
    )


@router.get("/invitacion/{codigo}")
def ver_invitacion(codigo: str, usuario: dict = Depends(usuario_actual)):
    """Vista previa antes de unirse. No muestra el centro exacto: a quien
    todavía no es miembro no se le revela dónde viven los vecinos."""
    filas = consultar(
        """
        SELECT g.id_grupo, g.nombre, g.descripcion, g.radio_metros,
               (SELECT COUNT(*) FROM grupo_miembro t WHERE t.id_grupo = g.id_grupo) AS total_miembros,
               EXISTS(
                   SELECT 1 FROM grupo_miembro m
                   WHERE m.id_grupo = g.id_grupo AND m.id_usuario = %s
               ) AS ya_es_miembro
        FROM grupo g
        WHERE g.codigo_invitacion = %s AND g.activo = 1 AND g.codigo_expira > NOW()
        """,
        (usuario["id_usuario"], _normalizar_codigo(codigo)),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="El código no existe o ya venció. Pide uno nuevo al administrador")
    fila = filas[0]
    return {
        "id_grupo": fila["id_grupo"],
        "nombre": fila["nombre"],
        "descripcion": fila["descripcion"],
        "radio_metros": int(fila["radio_metros"]),
        "total_miembros": int(fila["total_miembros"]),
        "ya_es_miembro": bool(fila["ya_es_miembro"]),
    }


@router.post("/unirse")
def unirse(datos: CodigoInvitacion, usuario: dict = Depends(usuario_actual)):
    """Ingreso automático con un código vigente."""
    id_usuario = usuario["id_usuario"]
    filas = consultar(
        """
        SELECT id_grupo FROM grupo
        WHERE codigo_invitacion = %s AND activo = 1 AND codigo_expira > NOW()
        """,
        (_normalizar_codigo(datos.codigo),),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="El código no existe o ya venció. Pide uno nuevo al administrador")
    id_grupo = filas[0]["id_grupo"]

    if _total_grupos(id_usuario) >= MAXIMO_GRUPOS_POR_USUARIO:
        raise HTTPException(
            status_code=409,
            detail=f"Solo puedes estar en {MAXIMO_GRUPOS_POR_USUARIO} grupos. Sal de uno para unirte a otro",
        )
    try:
        ejecutar(
            "INSERT INTO grupo_miembro (id_grupo, id_usuario, rol) VALUES (%s, %s, 'MIEMBRO')",
            (id_grupo, id_usuario),
        )
    except mysql.connector.Error as error:
        # uq_grupo_usuario: ya era miembro.
        if error.errno == 1062:
            raise HTTPException(status_code=409, detail="Ya eres parte de este grupo")
        raise HTTPException(status_code=400, detail=error.msg)
    return _grupo_de_usuario(id_grupo, id_usuario)


@router.get("/{id_grupo}")
def detalle_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    return _grupo_de_usuario(id_grupo, usuario["id_usuario"])


@router.put("/{id_grupo}")
def actualizar_grupo(
    datos: DatosGrupo,
    id_grupo: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """El admin cambia nombre, descripción o área. Los reportes ya compartidos se quedan en el grupo."""
    _solo_admin(id_grupo, usuario["id_usuario"])
    nombre, descripcion, direccion = _validar_datos(datos)
    punto_wkt = f"POINT({datos.longitud} {datos.latitud})"
    ejecutar(
        f"""
        UPDATE grupo
           SET nombre = %s, descripcion = %s, centro = {PUNTO_SQL},
               radio_metros = %s, direccion_referencia = %s
         WHERE id_grupo = %s AND activo = 1
        """,
        (nombre, descripcion, punto_wkt, datos.radio_metros, direccion, id_grupo),
    )
    return _grupo_de_usuario(id_grupo, usuario["id_usuario"])


@router.delete("/{id_grupo}", status_code=204)
def eliminar_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """El admin cierra el grupo. Queda inactivo (no se borra), así el admin general
    puede revisarlo; sus reportes privados dejan de verlos los ex miembros."""
    _solo_admin(id_grupo, usuario["id_usuario"])
    ejecutar("UPDATE grupo SET activo = 0 WHERE id_grupo = %s", (id_grupo,))
    return None


@router.post("/{id_grupo}/codigo")
def regenerar_codigo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """Nuevo código con vigencia renovada; el anterior deja de servir de inmediato."""
    _solo_admin(id_grupo, usuario["id_usuario"])
    for _ in range(3):
        try:
            ejecutar(
                """
                UPDATE grupo
                   SET codigo_invitacion = %s, codigo_expira = DATE_ADD(NOW(), INTERVAL %s DAY)
                 WHERE id_grupo = %s
                """,
                (_nuevo_codigo(), DIAS_VIGENCIA_CODIGO, id_grupo),
            )
            return _grupo_de_usuario(id_grupo, usuario["id_usuario"])
        except mysql.connector.Error as error:
            if error.errno != 1062:
                raise HTTPException(status_code=400, detail=error.msg)
    raise HTTPException(status_code=503, detail="No se pudo generar el código del grupo. Inténtalo otra vez")


@router.get("/{id_grupo}/miembros")
def listar_miembros(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    """Miembros con su alias del grupo; el nombre real nunca sale de la API."""
    id_usuario = usuario["id_usuario"]
    _membresia(id_grupo, id_usuario)
    filas = consultar(
        """
        SELECT id_miembro, id_usuario, rol, fecha_union
        FROM grupo_miembro WHERE id_grupo = %s
        ORDER BY rol = 'ADMIN' DESC, fecha_union
        """,
        (id_grupo,),
    )
    return [
        {
            "id_miembro": fila["id_miembro"],
            "alias": alias_miembro(id_grupo, fila["id_usuario"]),
            "rol": fila["rol"],
            "soy_yo": fila["id_usuario"] == id_usuario,
            "fecha_union": fila["fecha_union"].isoformat() if fila["fecha_union"] else None,
        }
        for fila in filas
    ]


def _quitar_miembro(id_grupo: int, id_usuario: int) -> None:
    """Saca al vecino y borra sus avisos del grupo: dejan de mostrarle reportes que ya no puede abrir."""
    with transaccion() as cursor:
        cursor.execute(
            "DELETE FROM grupo_miembro WHERE id_grupo = %s AND id_usuario = %s",
            (id_grupo, id_usuario),
        )
        cursor.execute(
            "DELETE FROM notificacion WHERE id_usuario = %s AND id_grupo = %s AND motivo = 'GRUPO'",
            (id_usuario, id_grupo),
        )


@router.delete("/{id_grupo}/miembros/{id_miembro}", status_code=204)
def expulsar_miembro(
    id_grupo: int = PathParam(ge=1),
    id_miembro: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
):
    """El admin expulsa a un vecino. Para que no vuelva a entrar, conviene regenerar el código."""
    _solo_admin(id_grupo, usuario["id_usuario"])
    filas = consultar(
        "SELECT id_usuario, rol FROM grupo_miembro WHERE id_miembro = %s AND id_grupo = %s",
        (id_miembro, id_grupo),
    )
    if not filas:
        raise HTTPException(status_code=404, detail="Ese vecino ya no está en el grupo")
    if filas[0]["rol"] == "ADMIN":
        raise HTTPException(status_code=409, detail="El administrador no puede expulsarse a sí mismo")
    _quitar_miembro(id_grupo, filas[0]["id_usuario"])
    return None


@router.post("/{id_grupo}/salir", status_code=204)
def salir_del_grupo(id_grupo: int = PathParam(ge=1), usuario: dict = Depends(usuario_actual)):
    if _membresia(id_grupo, usuario["id_usuario"])["rol"] == "ADMIN":
        raise HTTPException(
            status_code=409,
            detail="Eres el administrador: si quieres irte, elimina el grupo",
        )
    _quitar_miembro(id_grupo, usuario["id_usuario"])
    return None


@router.get("/{id_grupo}/reportes")
def listar_reportes_grupo(
    id_grupo: int = PathParam(ge=1),
    usuario: dict = Depends(usuario_actual),
    antes_de: int | None = Query(None, ge=1, description="id_reporte del último reporte recibido, para paginar"),
    limite: int = Query(30, ge=1, le=100),
):
    """El "chat" del grupo: los reportes compartidos, del más reciente al más antiguo.

    El autor aparece con el mismo alias que en el detalle del reporte, así la
    tarjeta del chat y la conversación del reporte coinciden.
    """
    id_usuario = usuario["id_usuario"]
    _membresia(id_grupo, id_usuario)
    condicion_pagina = "AND gr.id_reporte < %s" if antes_de else ""
    parametros = (id_grupo, antes_de, limite) if antes_de else (id_grupo, limite)
    filas = consultar(
        f"""
        SELECT r.id_reporte, r.id_usuario, r.visibilidad,
               c.codigo AS categoria_codigo, c.nombre AS categoria, c.color_hex,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               CASE
                   WHEN r.estado IN ('PENDIENTE', 'VALIDADO')
                        AND r.fecha_expiracion IS NOT NULL
                        AND r.fecha_expiracion <= NOW() THEN 'EXPIRADO'
                   ELSE r.estado
               END AS estado,
               r.fecha_creacion, gr.fecha_publicacion,
               (SELECT COUNT(*) FROM comentario co
                 WHERE co.id_reporte = r.id_reporte AND co.estado = 'PUBLICADO') AS total_comentarios,
               (SELECT i.url_archivo FROM reporte_imagen i
                 WHERE i.id_reporte = r.id_reporte ORDER BY i.orden LIMIT 1) AS imagen
        FROM grupo_reporte gr
        JOIN reporte r ON r.id_reporte = gr.id_reporte
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE gr.id_grupo = %s AND r.estado <> 'DESCARTADO'
          {condicion_pagina}
        ORDER BY gr.id_reporte DESC
        LIMIT %s
        """,
        parametros,
    )
    return [
        {
            "id_reporte": fila["id_reporte"],
            "autor": alias_autor(fila["id_reporte"]),
            "es_mio": fila["id_usuario"] == id_usuario,
            "visibilidad": fila["visibilidad"],
            "categoria_codigo": fila["categoria_codigo"],
            "categoria": fila["categoria"],
            "color_hex": fila["color_hex"],
            "latitud": float(fila["latitud"]),
            "longitud": float(fila["longitud"]),
            "direccion": fila["direccion"],
            "descripcion": fila["descripcion"],
            "estado": fila["estado"],
            "fecha_creacion": fila["fecha_creacion"].isoformat() if fila["fecha_creacion"] else None,
            "fecha_publicacion": fila["fecha_publicacion"].isoformat() if fila["fecha_publicacion"] else None,
            "total_comentarios": int(fila["total_comentarios"]),
            "imagen": fila["imagen"],
        }
        for fila in filas
    ]
