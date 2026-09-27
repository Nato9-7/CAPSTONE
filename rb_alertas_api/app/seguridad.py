import hashlib
import ipaddress
import secrets

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.correo import HORAS_VIGENCIA_VERIFICACION
from app.db import consultar, ejecutar

DURACION_SESION_DIAS = 30

esquema_bearer = HTTPBearer(auto_error=False)


def _ip_valida(ip: str | None) -> str | None:
    """INET6_ATON da error con textos que no son IP (p. ej. 'testclient'): esos se guardan como NULL."""
    try:
        return str(ipaddress.ip_address(ip)) if ip else None
    except ValueError:
        return None


def hash_token(token: str) -> str:
    """En la BD solo se guarda el SHA-256 del token: si se filtra la tabla, no sirve para entrar."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def crear_sesion(id_usuario: int, ip: str | None, user_agent: str | None) -> str:
    """Registra una sesión en usuario_sesion y devuelve el token que usará la app."""
    token = secrets.token_urlsafe(32)
    ejecutar(
        """
        INSERT INTO usuario_sesion (
            id_usuario, refresh_token_hash, ip_origen, user_agent, fecha_expiracion
        ) VALUES (%s, %s, INET6_ATON(%s), %s, DATE_ADD(NOW(), INTERVAL %s DAY))
        """,
        (id_usuario, hash_token(token), _ip_valida(ip), (user_agent or "")[:255] or None, DURACION_SESION_DIAS),
    )
    return token


def crear_token_verificacion(cursor, id_usuario: int, ip: str | None) -> str:
    """Token de un solo uso para verificar el correo (usuario_token, tipo VERIFICACION_EMAIL).

    Recibe un cursor para quedar en la misma transacción que la creación del usuario.
    """
    token = secrets.token_urlsafe(32)
    cursor.execute(
        """
        INSERT INTO usuario_token (id_usuario, tipo, token_hash, fecha_expiracion, ip_solicitud)
        VALUES (%s, 'VERIFICACION_EMAIL', %s, DATE_ADD(NOW(), INTERVAL %s HOUR), INET6_ATON(%s))
        """,
        (id_usuario, hash_token(token), HORAS_VIGENCIA_VERIFICACION, _ip_valida(ip)),
    )
    return token


def revocar_sesion(token: str) -> None:
    ejecutar(
        "UPDATE usuario_sesion SET fecha_revocacion = NOW() WHERE refresh_token_hash = %s AND fecha_revocacion IS NULL",
        (hash_token(token),),
    )


def _usuario_de_sesion(token: str) -> dict | None:
    filas = consultar(
        """
        SELECT u.id_usuario, u.uuid_publico
        FROM usuario_sesion s
        JOIN usuario u ON u.id_usuario = s.id_usuario
        WHERE s.refresh_token_hash = %s
          AND s.fecha_revocacion IS NULL
          AND s.fecha_expiracion > NOW()
          AND u.estado NOT IN ('SUSPENDIDO', 'ELIMINADO')
        """,
        (hash_token(token),),
    )
    return filas[0] if filas else None


def usuario_actual(credenciales: HTTPAuthorizationCredentials | None = Depends(esquema_bearer)) -> dict:
    """Dependencia para rutas protegidas: exige `Authorization: Bearer <token>` de una sesión vigente."""
    usuario = _usuario_de_sesion(credenciales.credentials) if credenciales else None
    if usuario is None:
        raise HTTPException(
            status_code=401,
            detail="Tu sesión no es válida o expiró. Vuelve a iniciar sesión",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return usuario


def usuario_opcional(credenciales: HTTPAuthorizationCredentials | None = Depends(esquema_bearer)) -> dict | None:
    """Como usuario_actual, pero sin exigir sesión: devuelve None si no hay token válido."""
    return _usuario_de_sesion(credenciales.credentials) if credenciales else None
