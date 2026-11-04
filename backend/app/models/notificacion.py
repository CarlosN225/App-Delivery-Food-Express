from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String

from app.database import Base


class Notificacion(Base):
    """
    Aviso para un usuario (Sprint 4, historia #15). Se guarda siempre en la base
    de datos: así la app puede mostrarlo aunque el push no haya llegado.
    """

    __tablename__ = "notificaciones"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    pedido_id = Column(Integer, ForeignKey("pedidos.id"), nullable=True)
    titulo = Column(String(120), nullable=False)
    mensaje = Column(String(255), nullable=False)
    leida = Column(Boolean, nullable=False, default=False)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)


class TokenDispositivo(Base):
    """Token de Firebase (FCM) de un celular, para mandarle notificaciones push."""

    __tablename__ = "tokens_dispositivo"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    token = Column(String(255), unique=True, nullable=False)
    plataforma = Column(String(20), nullable=True)
    fecha_registro = Column(DateTime, default=datetime.utcnow)