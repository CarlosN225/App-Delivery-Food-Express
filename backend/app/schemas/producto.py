from decimal import Decimal
from typing import Optional

from pydantic import BaseModel


class ProductoRespuesta(BaseModel):
    id: int
    restaurante_id: int
    nombre: str
    descripcion: Optional[str] = None
    precio: Decimal
    categoria: Optional[str] = None
    imagen: Optional[str] = None

    class Config:
        from_attributes = True