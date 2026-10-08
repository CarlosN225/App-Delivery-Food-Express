from decimal import Decimal

from app.database import SessionLocal
from app import models
from app.models.producto import Producto


db = SessionLocal()


productos = [
    Producto(
        restaurante_id=1,
        nombre="Pizza Pepperoni",
        descripcion="Pizza con salsa de tomate, queso y pepperoni.",
        precio=Decimal("150.00"),
        categoria="Pizzas",
    ),

    Producto(
        restaurante_id=1,
        nombre="Pizza Hawaiana",
        descripcion="Pizza con jamón, piña y queso.",
        precio=Decimal("160.00"),
        categoria="Pizzas",
    ),

    Producto(
        restaurante_id=1,
        nombre="Pizza Mexicana",
        descripcion="Pizza con chorizo, jalapeño, cebolla y queso.",
        precio=Decimal("170.00"),
        categoria="Pizzas",
    ),

    Producto(
        restaurante_id=2,
        nombre="Hamburguesa Clásica",
        descripcion="Hamburguesa con carne, queso, lechuga y tomate.",
        precio=Decimal("120.00"),
        categoria="Hamburguesas",
    ),

    Producto(
        restaurante_id=2,
        nombre="Hamburguesa BBQ",
        descripcion="Hamburguesa con carne, queso y salsa BBQ.",
        precio=Decimal("140.00"),
        categoria="Hamburguesas",
    ),

    Producto(
        restaurante_id=3,
        nombre="Tacos al Pastor",
        descripcion="Tacos al pastor con cebolla, cilantro y piña.",
        precio=Decimal("90.00"),
        categoria="Tacos",
    ),

    Producto(
        restaurante_id=3,
        nombre="Tacos de Suadero",
        descripcion="Tacos de suadero con cebolla y cilantro.",
        precio=Decimal("100.00"),
        categoria="Tacos",
    ),

    Producto(
        restaurante_id=4,
        nombre="Sushi California",
        descripcion="Rollo California con arroz, aguacate y pepino.",
        precio=Decimal("130.00"),
        categoria="Sushi",
    ),

    Producto(
        restaurante_id=4,
        nombre="Sushi Philadelphia",
        descripcion="Rollo Philadelphia con queso crema y salmón.",
        precio=Decimal("150.00"),
        categoria="Sushi",
    ),
]


for producto in productos:
    db.add(producto)


db.commit()

print("Productos insertados correctamente.")

db.close()