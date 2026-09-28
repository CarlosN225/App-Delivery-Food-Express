import enum
from datetime import datetime

from sqlalchemy import Column, Integer, String, DateTime, Enum
from sqlalchemy.orm import relationship

from app.database import Base


class RolUsuario(str, enum.Enum):
    cliente = "cliente"
    repartidor = "repartidor"
    administrador = "administrador"


class Usuario(Base):
    """
    Tabla central de usuarios. Un mismo modelo cubre clientes, repartidores
    y administradores, diferenciados por el campo `rol`.
    """

    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(120), nullable=False)
    correo = Column(String(150), unique=True, index=True, nullable=False)
    contrasena_hash = Column(String(255), nullable=False)
    rol = Column(Enum(RolUsuario), nullable=False, default=RolUsuario.cliente)
    fecha_registro = Column(DateTime, default=datetime.utcnow)

    pedidos_como_cliente = relationship(
        "Pedido",
        back_populates="cliente",
        foreign_keys="Pedido.cliente_id",
    )
    pedidos_como_repartidor = relationship(
        "Pedido",
        back_populates="repartidor",
        foreign_keys="Pedido.repartidor_id",
    )
