import logging
import os
import time
from contextlib import contextmanager
from mysql.connector import pooling
from mysql.connector.errors import PoolError
from dotenv import load_dotenv

load_dotenv()

registro = logging.getLogger(__name__)

# mysql-connector-python no admite pools de más de 32 conexiones.
TAMANO_MAXIMO_POOL = 32


def _leer_entero_acotado(nombre: str, por_defecto: int, minimo: int, maximo: int) -> int:
    """Lee una variable de entorno entera y la acota al rango [minimo, maximo]."""
    try:
        valor = int(os.getenv(nombre, por_defecto))
    except ValueError:
        registro.warning("%s no es un entero válido; se usa %s.", nombre, por_defecto)
        valor = por_defecto
    return max(minimo, min(maximo, valor))


def _leer_decimal_positivo(nombre: str, por_defecto: float) -> float:
    """Lee una variable de entorno numérica mayor que cero."""
    try:
        valor = float(os.getenv(nombre, por_defecto))
    except ValueError:
        registro.warning("%s no es un número válido; se usa %s.", nombre, por_defecto)
        return por_defecto
    return valor if valor > 0 else por_defecto


TAMANO_POOL = _leer_entero_acotado("DB_POOL_SIZE", 32, 1, TAMANO_MAXIMO_POOL)
TIEMPO_MAXIMO_ESPERA = _leer_decimal_positivo("DB_POOL_TIMEOUT", 5.0)

# Espera incremental entre reintentos: 10 ms, 20 ms, 40 ms ... hasta 250 ms.
ESPERA_INICIAL = 0.01
ESPERA_MAXIMA = 0.25

pool = pooling.MySQLConnectionPool(
    pool_name = "rb_alertas_pool",
    pool_size = TAMANO_POOL,
    host = os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT", 3306)),
    user = os.getenv("DB_USER"),
    password = os.getenv("DB_PASSWORD"),
    database = os.getenv("DB_NAME"),
)


def _obtener_conexion():
    """Obtiene una conexión del pool; si está agotado, reintenta con espera incremental.

    Relanza PoolError si no se consigue una conexión dentro de DB_POOL_TIMEOUT segundos.
    """
    inicio = time.monotonic()
    espera = ESPERA_INICIAL

    while True:
        try:
            conexion = pool.get_connection()
            break
        except PoolError as error:
            restante = TIEMPO_MAXIMO_ESPERA - (time.monotonic() - inicio)

            if restante <= 0:
                registro.warning(
                    "Pool de BD agotado: no hubo conexión disponible tras %.2f s (pool_size=%s).",
                    time.monotonic() - inicio, TAMANO_POOL,
                )
                raise PoolError(
                    f"No se obtuvo una conexión de la base de datos en {TIEMPO_MAXIMO_ESPERA:g} s: "
                    f"pool agotado (pool_size={TAMANO_POOL})."
                ) from error

            time.sleep(min(espera, restante))
            espera = min(espera * 2, ESPERA_MAXIMA)

    esperado = time.monotonic() - inicio
    if esperado > ESPERA_INICIAL:
        registro.warning(
            "Petición esperó %.3f s por una conexión de BD (pool_size=%s).",
            esperado, TAMANO_POOL,
        )

    return conexion


def _revertir(conexion) -> None:
    """Rollback que nunca lanza: no debe tapar la excepción original."""
    try:
        conexion.rollback()
    except Exception:
        registro.exception("No se pudo revertir la transacción.")


def _liberar(conexion, cursor=None) -> None:
    """Cierra el cursor y devuelve la conexión al pool sin lanzar excepciones."""
    if cursor is not None:
        try:
            cursor.close()
        except Exception:
            registro.warning("No se pudo cerrar el cursor.", exc_info=True)

    try:
        # Un resultado sin leer haría fallar el cierre y la conexión no volvería al pool.
        if conexion.unread_result:
            conexion.consume_results()
    except Exception:
        registro.warning("No se pudieron descartar resultados pendientes.", exc_info=True)

    try:
        conexion.close()
    except Exception:
        registro.exception("No se pudo devolver la conexión al pool.")


def consultar(sql: str, parametros: tuple = ()):
    conexion = _obtener_conexion()
    cursor = None

    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(sql, parametros)

        return cursor.fetchall()
    finally:
        _liberar(conexion, cursor)

def ejecutar(sql: str, parametros: tuple = ()):
    """Para INSERT/UPDATE/DELETE. Hace commit y devuelve el lastrowid."""
    conexion = _obtener_conexion()
    cursor = None

    try:
        cursor = conexion.cursor()
        cursor.execute(sql, parametros)
        conexion.commit()

        return cursor.lastrowid
    except Exception:
        _revertir(conexion)
        raise
    finally:
        _liberar(conexion, cursor)

@contextmanager
def transaccion():
    """Varias sentencias en una sola transacción: commit al salir, rollback si algo falla."""
    conexion = _obtener_conexion()
    cursor = None

    try:
        cursor = conexion.cursor(dictionary=True)
        yield cursor
        conexion.commit()
    except Exception:
        _revertir(conexion)
        raise
    finally:
        _liberar(conexion, cursor)
