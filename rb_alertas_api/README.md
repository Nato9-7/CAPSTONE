# API `rb_alertas`  🐮

Esta carpeta contiene la **API que será consumida por la aplicación `rb_alertas`**.

La API está desarrollada utilizando **Python** y se encarga de proporcionar los servicios y endpoints necesarios para la comunicación entre la aplicación móvil y la base de datos.

## Requisitos

Antes de ejecutar la API, es necesario tener instalado:

* Python 3
* `pip`
* Un entorno virtual de Python (`venv`)

## Configuración del entorno virtual

Se recomienda utilizar un entorno virtual para aislar las dependencias del proyecto.

Desde la carpeta principal de la API, crea el entorno virtual ejecutando:

```bash
python3 -m venv venv
```

Luego, activa el entorno virtual.

### Windows

```bash
venv\Scripts\activate
```

### Linux / macOS

```bash
source venv/bin/activate
```

## Instalación de dependencias

Una vez activado el entorno virtual, instala las dependencias necesarias para ejecutar la API.

Puedes instalarlas manualmente con el siguiente comando:

```bash
pip install fastapi uvicorn mysql-connector-python python-dotenv
```

También puedes instalar todas las dependencias directamente desde el archivo `requirements.txt`:

```bash
pip install -r requirements.txt
```

## Tecnologías utilizadas

La API utiliza las siguientes tecnologías:

* **FastAPI:** Framework utilizado para desarrollar la API.
* **Uvicorn:** Servidor ASGI utilizado para ejecutar la aplicación.
* **MySQL Connector:** Permite la conexión entre la API y la base de datos MySQL.
* **Python Dotenv:** Permite gestionar variables de entorno mediante archivos `.env`.

> Se recomienda utilizar el archivo `requirements.txt` para instalar las dependencias, ya que facilita la configuración del proyecto en diferentes equipos y asegura que todos los desarrolladores utilicen las mismas versiones de las librerías.
