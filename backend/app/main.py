from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import Base, engine
from app.routers import auth

# Crea las tablas automáticamente si no existen (suficiente para desarrollo;
# para producción se recomendaría manejar migraciones con Alembic).
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Food Express API",
    description="Backend del proyecto Food Express — Sprint 1: arquitectura y autenticación.",
    version="0.1.0",
)

# Habilitado en modo abierto para desarrollo, así la app Flutter (móvil o web)
# puede llamar al backend sin problemas de CORS mientras se prueba localmente.
# En producción, cambiar allow_origins por la URL real del frontend.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)


@app.get("/", tags=["Salud"])
def estado():
    return {"status": "ok", "proyecto": "Food Express", "sprint": "Sprint 1"}
