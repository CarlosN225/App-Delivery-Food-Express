from typing import Optional

from pydantic import BaseModel, Field


class NotificacionOut(BaseModel):
    id: int
    pedido_id: Optional[int] = None
    titulo: str
    mensaje: str
    leida: bool
    # Segundos desde que se creó (evita problemas de zona horaria en la app).
    hace_segundos: int


class ConteoOut(BaseModel):
    no_leidas: int


class TokenIn(BaseModel):
    """Token de Firebase del dispositivo (lo manda la app al iniciar sesión)."""

    token: str = Field(min_length=10, max_length=255)
    plataforma: str = Field(default="desconocida", max_length=20)