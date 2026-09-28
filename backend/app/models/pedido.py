import enum
from datetime import datetime

from sqlalchemy import Column, Integer, String, DateTime, Enum, ForeignKey, Numeric
from sqlalchemy.orm import relationship

from app.database import Base


class EstadoPedido(str, enum.Enum):
    pendiente = "pendiente"
    en_camino = "en_camino"
    entregado = "entregado"
    cancelado = "cancelado"


class Pedido(Base):
    """
    Representa un pedido dentro del flujo cliente -> restaurante -> repartidor.
    Se define desde el Sprint 1 como parte de la arquitectura de datos general,
    y se conecta con la lógica de carrito/pagos/GPS en los Sprints siguientes.
    """

    __tablename__ = "pedidos"

    id = Column(Integer, primary_key=True, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    repartidor_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    restaurante_id = Column(Integer, ForeignKey("restaurantes.id"), nullable=False)

    estado = Column(Enum(EstadoPedido), default=EstadoPedido.pendiente, nullable=False)
    total = Column(Numeric(10, 2), default=0)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)

    cliente = relationship(
        "Usuario", back_populates="pedidos_como_cliente", foreign_keys=[cliente_id]
    )
    repartidor = relationship(
        "Usuario", back_populates="pedidos_como_repartidor", foreign_keys=[repartidor_id]
    )
    restaurante = relationship("Restaurante", back_populates="pedidos")
