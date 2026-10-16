from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.models.pedido import EstadoPedido, EstadoPago, MetodoPago


class ItemCrear(BaseModel):
    producto_id: int
    cantidad: int = Field(ge=1, le=50)


class CotizacionIn(BaseModel):
    """Datos mínimos para calcular subtotal, envío y total (pantalla del carrito)."""

    restaurante_id: int
    items: list[ItemCrear] = Field(min_length=1)
    latitud_entrega: float = Field(ge=-90, le=90)
    longitud_entrega: float = Field(ge=-180, le=180)


class PedidoCrear(CotizacionIn):
    direccion_entrega: str = Field(min_length=3, max_length=255)
    metodo_pago: MetodoPago


class CotizacionOut(BaseModel):
    subtotal: float
    costo_envio: float
    total: float
    distancia_km: Optional[float] = None


class ItemOut(BaseModel):
    producto_id: Optional[int] = None
    nombre: str
    cantidad: int
    precio_unitario: float
    importe: float


class PedidoOut(BaseModel):
    id: int
    cliente_id: int
    repartidor_id: Optional[int] = None
    restaurante_id: int
    restaurante: str
    restaurante_direccion: Optional[str] = None
    restaurante_latitud: Optional[float] = None
    restaurante_longitud: Optional[float] = None
    estado: EstadoPedido
    estado_pago: Optional[EstadoPago] = None
    metodo_pago: Optional[MetodoPago] = None
    subtotal: float
    costo_envio: float
    total: float
    direccion_entrega: Optional[str] = None
    latitud_entrega: Optional[float] = None
    longitud_entrega: Optional[float] = None
    items: list[ItemOut] = []
    fecha_creacion: Optional[datetime] = None


class PedidoDisponibleOut(BaseModel):
    id: int
    restaurante_id: int
    restaurante: str
    restaurante_direccion: Optional[str] = None
    direccion_entrega: Optional[str] = None
    metodo_pago: Optional[MetodoPago] = None
    estado_pago: Optional[EstadoPago] = None
    total: float
    # Distancia del repartidor al restaurante (si mandó su ubicación).
    distancia_km: Optional[float] = None
    # Distancia restaurante -> cliente.
    distancia_entrega_km: Optional[float] = None
    minutos_estimados: Optional[int] = None
    fecha_creacion: Optional[datetime] = None


class CambioEstado(BaseModel):
    estado: EstadoPedido
