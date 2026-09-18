from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from app.rutas import reportes, usuarios

app = FastAPI(title = "API de RB Alertas")

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
