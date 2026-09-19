import hashlib
import secrets

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.db import consultar, ejecutar

DURACION_SESION_DIAS = 30

esquema_bearer = HTTPBearer(auto_error=False)


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
        (id_usuario, hash_token(token), ip, (user_agent or "")[:255] or None, DURACION_SESION_DIAS),
    )
    return token


def revocar_sesion(token: str) -> None:
    ejecutar(
        "UPDATE usuario_sesion SET fecha_revocacion = NOW() WHERE refresh_token_hash = %s AND fecha_revocacion IS NULL",
        (hash_token(token),),
    )


def usuario_actual(credenciales: HTTPAuthorizationCredentials | None = Depends(esquema_bearer)) -> dict:
    """Dependencia para rutas protegidas: exige `Authorization: Bearer <token>` de una sesión vigente."""
    no_autorizado = HTTPException(
        status_code=401,
        detail="Tu sesión no es válida o expiró. Vuelve a iniciar sesión",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credenciales is None:
        raise no_autorizado

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
        (hash_token(credenciales.credentials),),
    )
    if not filas:
        raise no_autorizado
    return filas[0]
