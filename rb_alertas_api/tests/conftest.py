import mysql.connector.pooling as pooling

# app.db abre el pool de MySQL al importarse; las pruebas no usan la base de datos.
pooling.MySQLConnectionPool.__init__ = lambda self, **k: None
