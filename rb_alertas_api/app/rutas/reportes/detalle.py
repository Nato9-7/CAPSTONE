"""Detalle de un reporte: datos, evidencias, voto propio, organismo de emergencia e incidente."""

from fastapi import APIRouter, Depends, Path as PathParam

from app.comun.alias import alias_autor
from app.db import consultar
from app.seguridad import usuario_opcional
from app.servicios.reportes import exigir_visible, reportes_del_incidente

router = APIRouter()


def _entidad_emergencia(id_entidad: int | None, id_comuna: int) -> dict | None:
    """Organismo a llamar: el de la categoría; si no tiene, Seguridad Ciudadana (u otro) de la comuna."""
    if id_entidad is not None:
        filas = consultar(
            "SELECT nombre, tipo, telefono FROM entidad_emergencia WHERE id_entidad = %s AND activa = 1",
            (id_entidad,),
        )
        if filas:
            return filas[0]
    filas = consultar(
        """
        SELECT nombre, tipo, telefono FROM entidad_emergencia
        WHERE id_comuna = %s AND activa = 1
        ORDER BY tipo = 'SEGURIDAD_CIUDADANA' DESC, id_entidad
        LIMIT 1
        """,
        (id_comuna,),
    )
    return filas[0] if filas else None


def _resumen_incidente(id_reporte: int) -> dict:
    """Reportes del mismo incidente para el detalle; el autor va siempre con su alias."""
    grupo = reportes_del_incidente(id_reporte) or [{"id_reporte": id_reporte}]
    return {
        "id_incidente": grupo[0]["id_reporte"],
        "total_reportes": len(grupo),
        "reportes": [
            {
                "id_reporte": g["id_reporte"],
                "autor": alias_autor(g["id_reporte"]),
                "descripcion": g.get("descripcion"),
                "fecha_creacion": g.get("fecha_creacion"),
                "es_este": g["id_reporte"] == id_reporte,
            }
            for g in grupo
        ],
    }


def _mi_voto(id_reporte: int, usuario: dict | None) -> str | None:
    """Voto propio, para que la app muestre cuál de los dos botones está marcado."""
    if usuario is None:
        return None
    votos = consultar(
        "SELECT tipo_voto FROM reporte_voto WHERE id_reporte = %s AND id_usuario = %s",
        (id_reporte, usuario["id_usuario"]),
    )
    return votos[0]["tipo_voto"] if votos else None


@router.get("/{id_reporte}")
def detalle_reporte(
    id_reporte: int = PathParam(ge=1),
    usuario: dict | None = Depends(usuario_opcional),
):
    filas = consultar(
        """
        SELECT r.id_reporte, r.id_usuario, r.id_comuna, r.estado, r.visibilidad,
               r.total_confirmaciones, r.total_desmentidos,
               c.codigo AS categoria_codigo, c.nombre AS categoria, c.color_hex, c.id_entidad,
               ST_Latitude(r.ubicacion) AS latitud, ST_Longitude(r.ubicacion) AS longitud,
               r.direccion_referencia AS direccion, r.descripcion,
               r.fecha_creacion, r.fecha_expiracion
        FROM reporte r
        JOIN categoria_incidente c ON c.id_categoria = r.id_categoria
        WHERE r.id_reporte = %s
        """,
        (id_reporte,),
    )
    id_usuario = usuario["id_usuario"] if usuario is not None else None
    r = exigir_visible(filas[0] if filas else None, id_reporte, id_usuario)

    imagenes = consultar(
        "SELECT url_archivo FROM reporte_imagen WHERE id_reporte = %s ORDER BY orden",
        (id_reporte,),
    )
    # Mismo total que muestra la conversación: los comentarios publicados.
    comentarios = consultar(
        "SELECT COUNT(*) AS total FROM comentario WHERE id_reporte = %s AND estado = 'PUBLICADO'",
        (id_reporte,),
    )
    # El id del autor no se expone: solo se indica si quien consulta es el autor.
    return {
        "id_reporte": r["id_reporte"],
        "categoria_codigo": r["categoria_codigo"],
        "categoria": r["categoria"],
        "color_hex": r["color_hex"],
        "latitud": r["latitud"],
        "longitud": r["longitud"],
        "direccion": r["direccion"],
        "descripcion": r["descripcion"],
        "estado": r["estado"],
        "visibilidad": r["visibilidad"],
        "fecha_creacion": r["fecha_creacion"],
        "fecha_expiracion": r["fecha_expiracion"],
        "autor": alias_autor(r["id_reporte"]),
        "es_autor": id_usuario is not None and id_usuario == r["id_usuario"],
        "total_confirmaciones": r["total_confirmaciones"],
        "total_desmentidos": r["total_desmentidos"],
        "mi_voto": _mi_voto(id_reporte, usuario),
        "imagenes": [fila["url_archivo"] for fila in imagenes],
        "total_comentarios": int(comentarios[0]["total"]) if comentarios else 0,
        "emergencia": _entidad_emergencia(r["id_entidad"], r["id_comuna"]),
        "incidente": _resumen_incidente(id_reporte) if r["visibilidad"] == "PUBLICO" else None,
    }
