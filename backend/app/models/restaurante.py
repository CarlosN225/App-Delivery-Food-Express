from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship

from app.database import Base


class Restaurante(Base):
    __tablename__ = "restaurantes"

    id = Column(
        Integer,
        primary_key=True,
        index=True
    )

    nombre = Column(
        String(150),
        nullable=False
    )

    direccion = Column(
        String(255),
        nullable=True
    )

    categoria = Column(
        String(80),
        nullable=True
    )

    latitud = Column(
        String(30),
        nullable=True
    )

    longitud = Column(
        String(30),
        nullable=True
    )

    # Relación con los pedidos
    pedidos = relationship(
        "Pedido",
        back_populates="restaurante"
    )

    # Relación con los productos
    productos = relationship(
        "Producto",
        back_populates="restaurante"
    )