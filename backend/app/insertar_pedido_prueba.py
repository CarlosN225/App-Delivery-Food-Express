"""
Crea un pedido de prueba en efectivo para poder probar el panel del repartidor
sin pasar por la app del cliente.   Uso (desde la carpeta backend):

    python -m app.insertar_pedido_prueba
"""

from decimal import Decimal

from app.database import SessionLocal
from app.models.pedido import (
    EstadoPago,
    EstadoPedido,
    ItemPedido,
    MetodoPago,
    Pedido,
)
from app.models.producto import Producto
from app.models.restaurante import Restaurante
from app.models.usuario import RolUsuario, Usuario
from app.services import logistica


db = SessionLocal()

cliente = db.query(Usuario).filter(Usuario.rol == RolUsuario.cliente).first()
restaurante = db.query(Restaurante).first()

if cliente is None:
    print("No existe ningún usuario con rol cliente.")
    print("Primero registra un usuario cliente.")
    db.close()
    raise SystemExit

if restaurante is None:
    print("No existe ningún restaurante.")
    db.close()
    raise SystemExit

producto = (
    db.query(Producto).filter(Producto.restaurante_id == restaurante.id).first()
)
precio = Decimal(str(producto.precio)) if producto else Decimal("220.00")

rlat = logistica.a_float(restaurante.latitud)
rlon = logistica.a_float(restaurante.longitud)
# Punto de entrega ~1 km al noreste del restaurante (o un punto fijo sin coordenadas).
elat = (rlat + 0.007) if rlat is not None else 19.4326
elon = (rlon + 0.007) if rlon is not None else -99.1332
distancia = (
    logistica.haversine_km(rlat, rlon, elat, elon)
    if rlat is not None and rlon is not None
    else None
)
envio = Decimal(str(logistica.calcular_envio(distancia)))

pedido = Pedido(
    cliente_id=cliente.id,
    restaurante_id=restaurante.id,
    estado=EstadoPedido.pendiente,
    subtotal=precio,
    costo_envio=envio,
    total=precio + envio,
    direccion_entrega="Dirección de prueba 123",
    latitud_entrega=elat,
    longitud_entrega=elon,
    metodo_pago=MetodoPago.efectivo,
    estado_pago=EstadoPago.contra_entrega,
)
pedido.items = [
    ItemPedido(
        producto_id=producto.id if producto else None,
        nombre=producto.nombre if producto else "Producto de prueba",
        cantidad=1,
        precio_unitario=precio,
    )
]

db.add(pedido)
db.commit()
db.refresh(pedido)

print("Pedido de prueba creado correctamente.")
print(f"Pedido ID: {pedido.id}")
print(f"Cliente ID: {cliente.id}")
print(f"Restaurante: {restaurante.nombre}")
print(f"Total: ${pedido.total}")

db.close()
