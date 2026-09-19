from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from app.rutas import reportes, usuarios

app = FastAPI(title = "API de RB Alertas")

# Tope al cuerpo de la petición antes de que FastAPI lea el formulario: si no,
# un archivo gigante se guarda completo en disco antes de validar sus 20 MB.
# Va antes del CORS para que CORS quede por fuera y el navegador pueda leer el error.
TAMANO_MAXIMO_PETICION = 21 * 1024 * 1024

@app.middleware("http")
async def limitar_tamano_peticion(request: Request, call_next):
    if request.method in ("POST", "PUT", "PATCH"):
        largo = request.headers.get("content-length")
        if largo is None or not largo.isdigit():
            return JSONResponse(status_code = 411, content = {"detail": "Falta el tamaño de la petición"})
        if int(largo) > TAMANO_MAXIMO_PETICION:
            return JSONResponse(status_code = 413, content = {"detail": "La evidencia no puede superar los 20 MB"})
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
    return {"ok" : True, "hora" : datetime.now().isoformat()}

app.include_router(usuarios.router, prefix = "/api/usuarios")
app.include_router(reportes.router, prefix = "/api/reportes")

# Evidencias (fotos/videos) adjuntas a los reportes.
app.mount("/uploads", StaticFiles(directory = reportes.CARPETA_UPLOADS), name = "uploads")
