"""
Carga los restaurantes de demostración (negocios reales de Nicolás Romero,
ver datos_demo.py). Se puede ejecutar varias veces sin duplicar datos.

Uso (desde la carpeta backend):

    python -m app.insertar_restaurantes
"""

from app.database import SessionLocal
from app.datos_demo import RESTAURANTES, RESTAURANTES_ANTERIORES
from app.models.pedido import Pedido
from app.models.producto import Producto
from app.models.restaurante import Restaurante


db = SessionLocal()

# 1) Quitar los restaurantes ficticios anteriores (si no tienen pedidos).
for nombre in RESTAURANTES_ANTERIORES:
    viejo = db.query(Restaurante).filter(Restaurante.nombre == nombre).first()
    if viejo is None:
        continue
    tiene_pedidos = (
        db.query(Pedido).filter(Pedido.restaurante_id == viejo.id).first()
    )
    if tiene_pedidos:
        print(f"Se conserva '{nombre}' porque ya tiene pedidos.")
        continue
    db.query(Producto).filter(Producto.restaurante_id == viejo.id).delete()
    db.delete(viejo)
    print(f"Se eliminó el restaurante de prueba anterior '{nombre}'.")

# 2) Insertar o actualizar los restaurantes reales.
for datos in RESTAURANTES:
    existente = (
        db.query(Restaurante).filter(Restaurante.nombre == datos["nombre"]).first()
    )
    if existente:
        existente.direccion = datos["direccion"]
        existente.categoria = datos["categoria"]
        existente.latitud = datos["latitud"]
        existente.longitud = datos["longitud"]
    else:
        db.add(
            Restaurante(
                nombre=datos["nombre"],
                direccion=datos["direccion"],
                categoria=datos["categoria"],
                latitud=datos["latitud"],
                longitud=datos["longitud"],
            )
        )

db.commit()

print(f"Restaurantes cargados correctamente: {len(RESTAURANTES)}.")

db.close()
