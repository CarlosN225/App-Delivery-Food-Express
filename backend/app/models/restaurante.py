from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship

from app.database import Base


class Restaurante(Base):
    """
    Catálogo de restaurantes disponibles en la plataforma.
    Se desarrolla a fondo en el Sprint 2 (visualización de restaurantes),
    pero se define aquí desde la arquitectura base para que el resto
    del modelo de datos (Pedido) pueda referenciarlo desde ahora.
    """

    __tablename__ = "restaurantes"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    direccion = Column(String(255), nullable=True)
    categoria = Column(String(80), nullable=True)
    latitud = Column(String(30), nullable=True)
    longitud = Column(String(30), nullable=True)

    pedidos = relationship("Pedido", back_populates="restaurante")
