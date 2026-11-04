"""
Carga los menús de prueba de los restaurantes de demostración
(ver datos_demo.py). Los menús y precios son inventados.
Se puede ejecutar varias veces sin duplicar productos.

Antes hay que cargar los restaurantes. Uso (desde la carpeta backend):

    python -m app.insertar_restaurantes
    python -m app.insertar_productos
"""

from decimal import Decimal

from app.database import SessionLocal
from app.datos_demo import RESTAURANTES
from app.models.producto import Producto
from app.models.restaurante import Restaurante


db = SessionLocal()

total = 0
faltantes = []

for datos in RESTAURANTES:
    restaurante = (
        db.query(Restaurante).filter(Restaurante.nombre == datos["nombre"]).first()
    )
    if restaurante is None:
        faltantes.append(datos["nombre"])
        continue

    for nombre, descripcion, precio, categoria in datos["productos"]:
        existente = (
            db.query(Producto)
            .filter(
                Producto.restaurante_id == restaurante.id,
                Producto.nombre == nombre,
            )
            .first()
        )
        if existente:
            existente.descripcion = descripcion
            existente.precio = Decimal(precio)
            existente.categoria = categoria
        else:
            db.add(
                Producto(
                    restaurante_id=restaurante.id,
                    nombre=nombre,
                    descripcion=descripcion,
                    precio=Decimal(precio),
                    categoria=categoria,
                )
            )
        total += 1

db.commit()

if faltantes:
    print("Faltan restaurantes (ejecuta primero app.insertar_restaurantes):")
    for nombre in faltantes:
        print(f"  - {nombre}")

print(f"Productos cargados correctamente: {total}.")

db.close()
