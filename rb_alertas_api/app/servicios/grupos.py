"""Grupos vecinales: un admin crea un grupo con un círculo (centro + radio) y los vecinos
entran con un código que vence. Los reportes compartidos aparecen en el chat del grupo."""

import secrets

from fastapi import HTTPException

from app.comun.formato import iso
from app.db import consultar

# Prototipo: crear grupos será una función pagada (juntas de vecinos, edificios).
MAXIMO_GRUPOS_CREADOS = 1
MAXIMO_GRUPOS_POR_USUARIO = 5
RADIOS_PERMITIDOS = (500, 1000, 2000)
DIAS_VIGENCIA_CODIGO = 7

# Sin 0/O ni 1/I/L: el código se dicta y se escribe a mano.
ALFABETO_CODIGO = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LARGO_CODIGO = 8

# Un choque de códigos es casi imposible (31^8), pero si pasa se reintenta.
INTENTOS_CODIGO = 3

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


def nuevo_codigo() -> str:
    return "".join(secrets.choice(ALFABETO_CODIGO) for _ in range(LARGO_CODIGO))


def normalizar_codigo(codigo: str) -> str:
    """Acepta el código con espacios, guiones o en minúsculas, como suele llegar al copiarlo."""
    return "".join(caracter for caracter in codigo.upper() if caracter.isalnum())


def membresia(id_grupo: int, id_usuario: int) -> dict:
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


def exigir_admin(id_grupo: int, id_usuario: int) -> None:
    if membresia(id_grupo, id_usuario)["rol"] != "ADMIN":
        raise HTTPException(status_code=403, detail="Solo el administrador del grupo puede hacer esto")


def total_grupos(id_usuario: int) -> int:
    filas = consultar(
        """
        SELECT COUNT(*) AS total
        FROM grupo_miembro m JOIN grupo g ON g.id_grupo = m.id_grupo
        WHERE m.id_usuario = %s AND g.activo = 1
        """,
        (id_usuario,),
    )
    return int(filas[0]["total"]) if filas else 0


def exigir_cupo(id_usuario: int, accion: str) -> None:
    """409 si el vecino ya está en el máximo de grupos. `accion`: "crear otro" o "unirte a otro"."""
    if total_grupos(id_usuario) >= MAXIMO_GRUPOS_POR_USUARIO:
        raise HTTPException(
            status_code=409,
            detail=f"Solo puedes estar en {MAXIMO_GRUPOS_POR_USUARIO} grupos. Sal de uno para {accion}",
        )


def grupo_json(fila: dict) -> dict:
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
        "ultimo_reporte": iso(fila["ultimo_reporte"]),
        # El código solo lo ve el admin, que es quien lo comparte y lo regenera.
        "codigo_invitacion": fila["codigo_invitacion"] if es_admin else None,
        "codigo_expira": iso(fila["codigo_expira"]) if es_admin else None,
        "codigo_vencido": bool(fila["codigo_vencido"]) if es_admin else None,
        "fecha_creacion": iso(fila["fecha_creacion"]),
    }


def grupo_de_usuario(id_grupo: int, id_usuario: int) -> dict:
    filas = consultar(SELECT_GRUPO + " AND g.id_grupo = %s", (id_usuario, id_grupo))
    if not filas:
        raise HTTPException(status_code=404, detail="El grupo no existe")
    return grupo_json(filas[0])
