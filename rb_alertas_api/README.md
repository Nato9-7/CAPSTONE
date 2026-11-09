# API `rb_alertas`  🐮

API REST que consumen la aplicación móvil `rb_alertas` y su panel de administración.
Está hecha en **Python** con **FastAPI** y usa **MySQL** como base principal. Opcionalmente
se conecta a **Neo4j** (grafo del panel), a un servidor **SMTP** (correos) y a
**Firebase Cloud Messaging** (notificaciones push); sin ellos la API funciona igual.

## Requisitos

* Python 3.12 o superior y `pip`
* Acceso a la base MySQL (en desarrollo, por túnel SSH al servidor)

## Instalación

Desde la carpeta `rb_alertas_api`:

```bash
python -m venv venv
venv\Scripts\activate          # Windows
source venv/bin/activate       # Linux / macOS
pip install -r requirements.txt
```

Para desarrollo (incluye `pytest`): `pip install -r requirements-dev.txt`.

## Configuración

Copia `.env.example` a `.env` y completa los valores. Las variables principales:

| Variable | Para qué sirve |
| --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | Conexión a MySQL (obligatorias). |
| `ADMIN_EMAILS` | Correos (verificados) con acceso al panel de administración. |
| `URL_PUBLICA_API` | URL pública usada en los enlaces de los correos. |
| `SMTP_*`, `CORREO_*` | Envío de correos. Sin `SMTP_HOST` los correos solo se imprimen en el log. |
| `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD` | Grafo del panel. Sin `NEO4J_URI` el grafo responde 503 y el resto funciona. |
| `FIREBASE_CREDENCIALES` | Ruta al JSON de la cuenta de servicio de Firebase. Sin ella los avisos push solo se imprimen en el log. |

`.env.example` documenta también las opcionales (pool de conexiones, carpeta de
uploads, reglas de incidentes y de zonas de riesgo). El `.env` y el JSON de Firebase
**no se suben al repositorio**.

## Ejecución

```bash
uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload
```

La documentación interactiva queda en `http://localhost:3000/docs`.

## Pruebas

```bash
pytest tests
```

Las pruebas no necesitan base de datos: `tests/conftest.py` desactiva el pool de MySQL.

## Estructura

```
app/
├── main.py            Crea la app: middlewares, routers y archivos estáticos.
├── db.py              Pool de MySQL: consultar(), ejecutar() y transaccion().
├── seguridad.py       Sesiones, tokens, contraseñas y dependencias de autenticación.
├── comun/             Utilidades compartidas sin lógica de negocio.
│   ├── alias.py       Nombres de fantasía («Suricata Valiente 23»): el nombre real nunca sale de la API.
│   ├── archivos.py    Validación, guardado y borrado de fotos y videos subidos.
│   ├── formato.py     Conversión de fechas y números para las respuestas JSON.
│   ├── geo.py         Puntos geográficos para las consultas espaciales.
│   └── sql.py         Marcadores IN y traducción de errores de MySQL a respuestas HTTP.
├── servicios/         Reglas de negocio reutilizables (sin rutas HTTP).
│   ├── reportes.py    Quién puede ver un reporte, su incidente y su historial de estado.
│   ├── ubicacion.py   Comuna y localidad de un punto.
│   ├── avisos.py      Avisos (tabla notificacion) por zonas seguras, grupos y comentarios.
│   ├── comentarios.py Consultas y eliminación de comentarios.
│   ├── grupos.py      Reglas de los grupos vecinales (membresía, cupos, códigos).
│   ├── moderacion.py  Suspensión de cuentas y cierre de denuncias.
│   ├── incidentes.py  Agrupa reportes del mismo hecho (funciones puras).
│   ├── zonas_riesgo.py Zonas de riesgo y mapa de calor (funciones puras).
│   ├── analisis_grafo.py Cuentas coordinadas y reputación (funciones puras).
│   ├── correo.py      Envío y plantillas de correo.
│   ├── push.py        Notificaciones push con Firebase.
│   └── grafo/         Copia en Neo4j: conexión, sincronización, red del explorador y zonas.
├── rutas/             Endpoints, un paquete por recurso.
│   ├── usuarios/      /api/usuarios: cuenta, verificación, recuperación, zonas, alertas, dispositivos.
│   ├── reportes/      /api/reportes: consultas, creación, detalle, votos, comentarios, denuncias.
│   ├── grupos/        /api/grupos: gestión, membresía y chat del grupo.
│   └── admin/         /api/admin: resumen, moderación y grafo del panel.
└── estaticos/         Logo usado en los correos y en las páginas de los enlaces.
sql/                   Scripts SQL de cambios en la base (ejecutar a mano con respaldo previo).
tests/                 Pruebas con pytest.
```

Convenciones:

* Las rutas solo validan la petición y arman la respuesta; lo que usan varias rutas
  va en `servicios/` o `comun/`.
* Dentro de cada paquete de `rutas/` el orden de inclusión importa: las rutas fijas
  (p. ej. `/mios`) se incluyen antes que las que tienen parámetros (`/{id_reporte}`).
* Los errores de MySQL no se envían tal cual al cliente: se registran en el log y la
  respuesta lleva un mensaje genérico (salvo los mensajes de los triggers, `SIGNAL 45000`).
* Las fotos y videos se validan por su contenido (no por el nombre ni el `Content-Type`)
  y se sirven desde `/uploads`.

## Tecnologías

* **FastAPI** y **Uvicorn**: framework y servidor ASGI.
* **mysql-connector-python**: conexión a MySQL con pool.
* **bcrypt**: hash de contraseñas.
* **neo4j**: driver del grafo del panel.
* **firebase-admin**: notificaciones push.
* **python-dotenv**: variables de entorno desde `.env`.
