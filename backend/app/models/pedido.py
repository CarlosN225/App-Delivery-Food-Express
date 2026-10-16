import enum
from datetime import datetime

from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Numeric,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.database import Base


class EstadoPedido(str, enum.Enum):
    """
    Ciclo de vida de un pedido (Sprint 3, historia #12):

        pendiente -> aceptado -> recogido -> en_camino -> entregado
                 \\-> cancelado

    - pendiente: creado por el cliente, esperando repartidor.
    - aceptado: un repartidor lo tomó y va al restaurante.
    - recogido: el repartidor ya tiene la comida.
    - en_camino: va rumbo al cliente.
    - entregado: el cliente lo recibió.
    """

    pendiente = "pendiente"
    aceptado = "aceptado"
    recogido = "recogido"
    en_camino = "en_camino"
    entregado = "entregado"
    cancelado = "cancelado"


class MetodoPago(str, enum.Enum):
    mercado_pago = "mercado_pago"
    efectivo = "efectivo"


class EstadoPago(str, enum.Enum):
    pendiente = "pendiente"  # Mercado Pago: aún sin pagar
    pagado = "pagado"
    rechazado = "rechazado"
    contra_entrega = "contra_entrega"  # efectivo: se cobra al entregar


class Pedido(Base):
    """
    Pedido dentro del flujo cliente -> restaurante -> repartidor.
    El total siempre lo calcula el backend (subtotal + envío); la app nunca
    manda precios.
    """

    __tablename__ = "pedidos"

    id = Column(Integer, primary_key=True, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    repartidor_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    restaurante_id = Column(Integer, ForeignKey("restaurantes.id"), nullable=False)

    estado = Column(Enum(EstadoPedido), default=EstadoPedido.pendiente, nullable=False)

    subtotal = Column(Numeric(10, 2), default=0)
    costo_envio = Column(Numeric(10, 2), default=0)
    total = Column(Numeric(10, 2), default=0)

    direccion_entrega = Column(String(255), nullable=True)
    latitud_entrega = Column(Float, nullable=True)
    longitud_entrega = Column(Float, nullable=True)

    metodo_pago = Column(Enum(MetodoPago), nullable=True)
    estado_pago = Column(Enum(EstadoPago), nullable=True)
    mp_preference_id = Column(String(120), nullable=True)
    mp_payment_id = Column(String(60), nullable=True)

    fecha_creacion = Column(DateTime, default=datetime.utcnow)
    fecha_actualizacion = Column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    cliente = relationship(
        "Usuario", back_populates="pedidos_como_cliente", foreign_keys=[cliente_id]
    )
    repartidor = relationship(
        "Usuario", back_populates="pedidos_como_repartidor", foreign_keys=[repartidor_id]
    )
    restaurante = relationship("Restaurante", back_populates="pedidos")
    items = relationship(
        "ItemPedido",
        back_populates="pedido",
        cascade="all, delete-orphan",
        order_by="ItemPedido.id",
    )


class ItemPedido(Base):
    """Línea de un pedido. Guarda nombre y precio al momento de la compra."""

    __tablename__ = "items_pedido"

    id = Column(Integer, primary_key=True, index=True)
    pedido_id = Column(Integer, ForeignKey("pedidos.id"), nullable=False, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=True)
    nombre = Column(String(150), nullable=False)
    cantidad = Column(Integer, nullable=False)
    precio_unitario = Column(Numeric(10, 2), nullable=False)

    pedido = relationship("Pedido", back_populates="items")

    @property
    def importe(self):
        return self.cantidad * self.precio_unitario


class PedidoRechazado(Base):
    """
    Un repartidor que rechaza un pedido solo deja de verlo él; el pedido sigue
    disponible para los demás (no se cancela el pedido del cliente).
    """

    __tablename__ = "pedidos_rechazados"
    __table_args__ = (UniqueConstraint("pedido_id", "repartidor_id"),)

    id = Column(Integer, primary_key=True)
    pedido_id = Column(Integer, ForeignKey("pedidos.id"), nullable=False)
    repartidor_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
