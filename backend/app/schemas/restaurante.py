from pydantic import BaseModel
from typing import Optional


class RestauranteCercano(BaseModel):
    id: int
    nombre: str
    direccion: Optional[str] = None
    categoria: Optional[str] = None
    latitud: Optional[str] = None
    longitud: Optional[str] = None
    distancia_km: float