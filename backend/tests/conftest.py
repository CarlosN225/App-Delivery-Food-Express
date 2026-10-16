import os
import tempfile

# La base de pruebas es un SQLite temporal y los pagos corren en modo demo.
# Esto debe ejecutarse ANTES de importar la app.
_dir = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_dir}/prueba.db"
os.environ["MERCADO_PAGO_ACCESS_TOKEN"] = ""
os.environ["SECRET_KEY"] = "llave-de-pruebas"

import pytest
from fastapi.testclient import TestClient

from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import Producto, Restaurante


@pytest.fixture()
def client():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def db():
    sesion = SessionLocal()
    try:
        yield sesion
    finally:
        sesion.close()


@pytest.fixture()
def menu(client, db):
    """Dos restaurantes con coordenadas y productos. Devuelve sus ids."""
    pizza = Restaurante(
        nombre="Pizza Express", direccion="Calle Hidalgo 100",
        categoria="Pizza", latitud="19.6010", longitud="-99.3085",
    )
    tacos = Restaurante(
        nombre="Tacos Don Juan", direccion="Calle Juárez 50",
        categoria="Mexicana", latitud="19.5950", longitud="-99.3200",
    )
    db.add_all([pizza, tacos])
    db.commit()
    p1 = Producto(restaurante_id=pizza.id, nombre="Pepperoni", precio=120)
    p2 = Producto(restaurante_id=pizza.id, nombre="Coca-Cola", precio=30)
    p3 = Producto(restaurante_id=tacos.id, nombre="Taco al pastor", precio=25)
    db.add_all([p1, p2, p3])
    db.commit()
    return {
        "pizza": pizza.id, "tacos": tacos.id,
        "pepperoni": p1.id, "coca": p2.id, "taco": p3.id,
    }


def _usuario(client, nombre, rol):
    correo = f"{nombre.lower()}@correo.com"
    r = client.post("/auth/registro", json={
        "nombre": nombre, "correo": correo, "contrasena": "secreto1", "rol": rol,
    })
    assert r.status_code == 201, r.text
    r = client.post("/auth/login", data={"username": correo, "password": "secreto1"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture()
def cliente(client):
    return _usuario(client, "Ana", "cliente")


@pytest.fixture()
def repartidor(client):
    return _usuario(client, "Beto", "repartidor")


@pytest.fixture()
def repartidor2(client):
    return _usuario(client, "Carla", "repartidor")
