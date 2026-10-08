from decimal import Decimal

from app.database import SessionLocal
from app.models.pedido import Pedido, EstadoPedido
from app.models.usuario import Usuario, RolUsuario
from app.models.restaurante import Restaurante


db = SessionLocal()

cliente = (
    db.query(Usuario)
    .filter(Usuario.rol == RolUsuario.cliente)
    .first()
)

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


pedido = Pedido(
    cliente_id=cliente.id,
    restaurante_id=restaurante.id,
    estado=EstadoPedido.pendiente,
    total=Decimal("250.00"),
)

db.add(pedido)
db.commit()
db.refresh(pedido)

print("Pedido de prueba creado correctamente.")
print(f"Pedido ID: {pedido.id}")
print(f"Cliente ID: {cliente.id}")
print(f"Restaurante: {restaurante.nombre}")
print(f"Total: ${pedido.total}")

db.close()