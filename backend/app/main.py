from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import Base, engine
from app import models
from app.migraciones import aplicar_migraciones
from app.routers import auth, restaurantes, productos, pedidos, pagos


# Crea las tablas automáticamente si no existen y agrega a `pedidos` las
# columnas nuevas del Sprint 3 en bases de datos de Sprints anteriores
# (suficiente para desarrollo; para producción se recomienda Alembic).
Base.metadata.create_all(bind=engine)
aplicar_migraciones(engine)

app = FastAPI(
    title="Food Express API",
    description="Backend del proyecto Food Express — Sprint 3: carrito, pagos y ruta óptima.",
    version="0.3.0",
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
app.include_router(restaurantes.router)
app.include_router(productos.router)
app.include_router(pedidos.router)
app.include_router(pagos.router)


@app.get("/", tags=["Salud"])
def estado():
    return {"status": "ok", "proyecto": "Food Express", "sprint": "Sprint 3"}
