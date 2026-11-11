from typing import Optional

from pydantic import BaseModel, Field, field_validator

from app.services.seguridad import sanitizar_texto


class ResenaCrear(BaseModel):
    pedido_id: int
    calificacion_restaurante: int = Field(ge=1, le=5)
    calificacion_repartidor: Optional[int] = Field(default=None, ge=1, le=5)
    comentario: Optional[str] = Field(default=None, max_length=300)

    @field_validator("comentario")
    @classmethod
    def _limpiar_comentario(cls, valor: Optional[str]) -> Optional[str]:
        # Codificación segura: se quita HTML y símbolos de marcado (Actividad 2).
        limpio = sanitizar_texto(valor)
        return limpio or None


class ResenaOut(BaseModel):
    pedido_id: int
    calificacion_restaurante: int
    calificacion_repartidor: Optional[int] = None
    comentario: Optional[str] = None


class ResenaPublica(BaseModel):
    autor: str
    calificacion: int
    comentario: Optional[str] = None
    hace_dias: int


class ResenasRestaurante(BaseModel):
    promedio: Optional[float] = None
    total: int = 0
    resenas: list[ResenaPublica] = []
