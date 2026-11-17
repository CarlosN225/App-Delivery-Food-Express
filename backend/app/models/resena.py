from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String

from app.database import Base


class Resena(Base):
    """
    Calificación de un pedido entregado (Sprint 5, historia #28).

    El cliente califica el restaurante (obligatorio) y, si quiere, al
    repartidor, de 1 a 5 estrellas, con un comentario opcional. Solo se puede
    reseñar un pedido entregado y solo una vez (pedido_id es único).
    """

    __tablename__ = "resenas"

    id = Column(Integer, primary_key=True, index=True)
    pedido_id = Column(Integer, ForeignKey("pedidos.id"), unique=True, nullable=False)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    restaurante_id = Column(Integer, ForeignKey("restaurantes.id"), nullable=False, index=True)
    repartidor_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True, index=True)

    calificacion_restaurante = Column(Integer, nullable=False)
    calificacion_repartidor = Column(Integer, nullable=True)
    comentario = Column(String(300), nullable=True)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)
