import os
from mysql.connector import pooling
from dotenv import load_dotenv

load_dotenv()

pool = pooling.MySQLConnectionPool(
    pool_name = "rb_alertas_pool",
    pool_size = 5,
    host = os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT", 3306)),
    user = os.getenv("DB_USER"),
    password = os.getenv("DB_PASSWORD"),
    database = os.getenv("DB_NAME"),
)

def consultar(sql: str, parametros : tuple = ()):

    conexion = pool.get_connection()

    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.excute(sql, parametros)

        return cursor.fetchall()
    finally:
        conexion.close()
