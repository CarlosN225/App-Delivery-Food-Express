"""
Lógica de logística del Sprint 3: distancias, costo de envío, tiempos
estimados y ruta óptima básica para el repartidor (historia #11).

Es Python puro (sin base de datos ni FastAPI) para poder probarlo aislado.

Ruta óptima básica
------------------
Con varios pedidos activos, el orden de paradas se calcula con el criterio del
"vecino más cercano": desde la posición actual del repartidor se va siempre a
la parada disponible más cercana, respetando que un pedido solo se puede
entregar después de recogerlo en el restaurante. Las distancias son en línea
recta (Haversine), suficiente para esta versión; en un Sprint posterior se
puede reemplazar por Google Directions sin cambiar la interfaz.
"""

import math
from dataclasses import dataclass
from typing import Optional

RADIO_TIERRA_KM = 6371.0

# Parámetros de negocio (fáciles de ajustar)
VELOCIDAD_PROMEDIO_KMH = 25.0
TARIFA_BASE_ENVIO = 20.0
TARIFA_POR_KM = 4.0
ENVIO_MINIMO = 30.0

Coordenada = tuple[float, float]  # (latitud, longitud)


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distancia en kilómetros entre dos coordenadas."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat = p2 - p1
    dlon = math.radians(lon2) - math.radians(lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return RADIO_TIERRA_KM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def minutos_estimados(distancia_km: float) -> int:
    """Tiempo estimado de traslado (mínimo 1 minuto si hay que moverse)."""
    if distancia_km <= 0:
        return 0
    return max(1, math.ceil(distancia_km / VELOCIDAD_PROMEDIO_KMH * 60))


def calcular_envio(distancia_km: Optional[float]) -> float:
    """Costo de envío: tarifa base + tarifa por km, con un mínimo."""
    if distancia_km is None:
        return ENVIO_MINIMO
    return round(max(ENVIO_MINIMO, TARIFA_BASE_ENVIO + TARIFA_POR_KM * distancia_km), 2)


def a_float(valor) -> Optional[float]:
    """Convierte lat/lon guardadas como texto a float; None si no son válidas."""
    try:
        return float(valor)
    except (TypeError, ValueError):
        return None


@dataclass
class PedidoRuta:
    """Datos mínimos de un pedido activo para calcular la ruta."""

    id: int
    restaurante: str
    rest_coord: Coordenada
    cliente_direccion: str
    cliente_coord: Coordenada
    recogido: bool = False  # True si ya salió del restaurante


@dataclass
class Parada:
    pedido_id: int
    tipo: str  # "recoger" | "entregar"
    nombre: str
    coord: Coordenada


def ordenar_paradas(origen: Coordenada, pedidos: list[PedidoRuta]) -> list[Parada]:
    """Orden de paradas por vecino más cercano, recoger siempre antes de entregar."""
    disponibles: list[Parada] = []
    for p in pedidos:
        if p.recogido:
            disponibles.append(
                Parada(p.id, "entregar", p.cliente_direccion, p.cliente_coord)
            )
        else:
            disponibles.append(Parada(p.id, "recoger", p.restaurante, p.rest_coord))

    por_id = {p.id: p for p in pedidos}
    orden: list[Parada] = []
    actual = origen

    while disponibles:
        siguiente = min(
            disponibles,
            key=lambda s: (haversine_km(*actual, *s.coord), s.pedido_id, s.tipo),
        )
        disponibles.remove(siguiente)
        orden.append(siguiente)
        actual = siguiente.coord

        if siguiente.tipo == "recoger":
            p = por_id[siguiente.pedido_id]
            disponibles.append(
                Parada(p.id, "entregar", p.cliente_direccion, p.cliente_coord)
            )

    return orden


def construir_tramos(origen: Optional[Coordenada], paradas: list[Parada]) -> dict:
    """Calcula distancia y tiempo de cada tramo y los totales de una ruta."""
    tramos = []
    actual = origen
    total_km = 0.0
    total_min = 0

    for parada in paradas:
        if actual is None:
            km = 0.0
        else:
            km = haversine_km(*actual, *parada.coord)
        minutos = minutos_estimados(km)
        tramos.append(
            {
                "pedido_id": parada.pedido_id,
                "tipo": parada.tipo,
                "destino": parada.nombre,
                "latitud": parada.coord[0],
                "longitud": parada.coord[1],
                "distancia_km": round(km, 2),
                "minutos": minutos,
            }
        )
        total_km += km
        total_min += minutos
        actual = parada.coord

    return {
        "tramos": tramos,
        "distancia_total_km": round(total_km, 2),
        "minutos_total": total_min,
    }


def ruta_de_pedido(
    estado: str,
    repartidor: Optional[Coordenada],
    restaurante: PedidoRuta,
) -> dict:
    """
    Ruta restante de un solo pedido según su estado:
      - aceptado: repartidor -> restaurante -> cliente
      - recogido / en_camino: repartidor -> cliente
      - entregado / cancelado / pendiente: sin ruta
    Si no se conoce la posición del repartidor, el primer tramo parte desde el
    restaurante.
    """
    p = restaurante
    entregar = Parada(p.id, "entregar", p.cliente_direccion, p.cliente_coord)
    recoger = Parada(p.id, "recoger", p.restaurante, p.rest_coord)

    if estado == "aceptado":
        paradas = [recoger, entregar]
        origen = repartidor
    elif estado in ("recogido", "en_camino"):
        paradas = [entregar]
        origen = repartidor if repartidor is not None else p.rest_coord
    else:
        return {"tramos": [], "distancia_total_km": 0.0, "minutos_total": 0}

    # Sin posición del repartidor, el trayecto empieza en el restaurante.
    if origen is None:
        origen = p.rest_coord
        paradas = [entregar]

    return construir_tramos(origen, paradas)
