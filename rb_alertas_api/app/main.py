from fastapi import FastAPI
from datetime import datetime
from app.rutas import usuarios

app = FastAPI(title = "API de RB Alertas")

@app.get("/api/ping")
def ping():
    return {"ok" : True, "hora" : datetime.now().isoformat()}

app.include_router(usuarios.router, prefix = "/api/usuarios")
