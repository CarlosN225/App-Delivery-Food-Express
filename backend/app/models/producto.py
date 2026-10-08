from sqlalchemy import Column, Integer, String, Numeric, ForeignKey
from sqlalchemy.orm import relationship

from app.database import Base


class Producto(Base):
    __tablename__ = "productos"

    id = Column(
        Integer,
        primary_key=True,
        index=True
    )

    restaurante_id = Column(
        Integer,
        ForeignKey("restaurantes.id"),
        nullable=False
    )

    nombre = Column(
        String(150),
        nullable=False
    )

    descripcion = Column(
        String(255),
        nullable=True
    )

    precio = Column(
        Numeric(10, 2),
        nullable=False
    )

    categoria = Column(
        String(80),
        nullable=True
    )

    imagen = Column(
        String(255),
        nullable=True
    )

    restaurante = relationship(
        "Restaurante",
        back_populates="productos"
    )