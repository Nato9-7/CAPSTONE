from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.comun.archivos import CARPETA_UPLOADS
from app.rutas import admin, grupos, reportes, usuarios
from app.servicios import grafo

# Tope al cuerpo de la petición antes de que FastAPI lea el formulario: si no,
# un archivo gigante se guarda completo en disco antes de validar sus 20 MB.
TAMANO_MAXIMO_PETICION = 21 * 1024 * 1024

CARPETA_ESTATICOS = Path(__file__).parent / "estaticos"


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    # Copia periódica MySQL -> Neo4j para el grafo del panel (no hace nada sin NEO4J_URI).
    grafo.iniciar_sincronizacion_periodica()
    yield


app = FastAPI(title="API de RB Alertas", lifespan=ciclo_de_vida)


# Va antes del CORS para que CORS quede por fuera y el navegador pueda leer el error.
@app.middleware("http")
async def limitar_tamano_peticion(request: Request, call_next):
    if request.method in ("POST", "PUT", "PATCH"):
        largo = request.headers.get("content-length")
        if largo is None or not largo.isdigit():
            return JSONResponse(status_code=411, content={"detail": "Falta el tamaño de la petición"})
        if int(largo) > TAMANO_MAXIMO_PETICION:
            return JSONResponse(status_code=413, content={"detail": "La evidencia no puede superar los 20 MB"})
    return await call_next(request)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/ping")
def ping():
    return {"ok": True, "hora": datetime.now().isoformat()}


app.include_router(usuarios.router, prefix="/api/usuarios")
app.include_router(reportes.router, prefix="/api/reportes")
app.include_router(grupos.router, prefix="/api/grupos")
app.include_router(admin.router, prefix="/api/admin")

# Logo para las páginas que abren los enlaces del correo y para los correos, y
# evidencias (fotos/videos) de reportes y comentarios. Solo si la carpeta existe:
# si falta (p. ej. por permisos), la API arranca igual y esa ruta responde 404.
if CARPETA_ESTATICOS.is_dir():
    app.mount("/estaticos", StaticFiles(directory=CARPETA_ESTATICOS), name="estaticos")
if CARPETA_UPLOADS.is_dir():
    app.mount("/uploads", StaticFiles(directory=CARPETA_UPLOADS), name="uploads")
