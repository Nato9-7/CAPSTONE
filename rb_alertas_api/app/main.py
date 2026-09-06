from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from app.rutas import usuarios

app = FastAPI(title = "API de RB Alertas")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/ping")
def ping():
    return {"ok" : True, "hora" : datetime.now().isoformat()}

app.include_router(usuarios.router, prefix = "/api/usuarios")
