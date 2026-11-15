"""Regiones y comunas que se pueden elegir al crear una cuenta."""

from fastapi import APIRouter

from app.db import consultar

router = APIRouter()


def comuna_operativa(id_comuna: int) -> bool:
    """True si la comuna existe, tiene cobertura y su región está activa."""
    return bool(
        consultar(
            """
            SELECT 1 FROM comuna c JOIN region r ON r.id_region = c.id_region
            WHERE c.id_comuna = %s AND c.operativa = 1 AND r.activa = 1
            """,
            (id_comuna,),
        )
    )


@router.get("/comunas")
def listar_comunas():
    """Regiones activas con sus comunas operativas, en el orden oficial de las regiones.

    Ruta pública: la usa el formulario de registro antes de que exista una sesión.
    """
    filas = consultar(
        """
        SELECT r.id_region, r.nombre AS region, r.numero_romano, c.id_comuna, c.nombre AS comuna
        FROM region r
        JOIN comuna c ON c.id_region = r.id_region
        WHERE r.activa = 1 AND c.operativa = 1
        ORDER BY r.orden, c.nombre
        """
    )
    regiones: dict[int, dict] = {}
    for fila in filas:
        region = regiones.setdefault(
            fila["id_region"],
            {
                "id_region": fila["id_region"],
                "nombre": fila["region"],
                "numero_romano": fila["numero_romano"],
                "comunas": [],
            },
        )
        region["comunas"].append({"id_comuna": fila["id_comuna"], "nombre": fila["comuna"]})
    return list(regiones.values())
