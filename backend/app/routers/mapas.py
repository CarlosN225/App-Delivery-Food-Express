"""
Mapas — Sprint 5 (Google Maps Platform).

  POST /mapas/geocodificar   Dirección escrita -> coordenadas (Geocoding API).
  GET  /mapas/ruta/{pedido}  Trazo real por calles del pedido (Routes API).

La app de Flutter nunca llama a Google para estos datos: pide al backend, que
usa la llave del servidor. Si Google falla o no hay llave, la ruta se devuelve
en línea recta (`fuente: "linea_recta"`) para que la demo no se caiga.
"""

import time
from collections import defaultdict, deque
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import EstadoPedido, Pedido
from app.models.usuario import RolUsuario, Usuario
from app.routers.auth import obtener_usuario_actual
from app.services import google_maps, logistica

router = APIRouter(prefix="/mapas", tags=["Mapas"])

# Límite sencillo por usuario para cuidar la cuota de Google.
MAX_GEOCODIFICACIONES_POR_MINUTO = 20
_historial_geocodificacion: dict[int, deque] = defaultdict(deque)

# Una ruta por pedido, estado y "celda" de la posición del repartidor (~200 m):
# (pedido_id, estado, celda) -> (momento, ruta). Si el repartidor se mueve a otra
# celda, la ruta se recalcula para que siga su posición.
_CACHE_RUTAS: dict[tuple, tuple[float, dict]] = {}
VIGENCIA_RUTA_SEGUNDOS = 3600
MAX_RUTAS_EN_CACHE = 500


class DireccionIn(BaseModel):
    direccion: str = Field(min_length=5, max_length=255)


class GeocodificacionOut(BaseModel):
    latitud: float
    longitud: float
    direccion_formateada: str
    place_id: Optional[str] = None
    precision: Optional[str] = None
    coincidencia_parcial: bool = False


class PuntoIn(BaseModel):
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)


class DireccionOut(BaseModel):
    direccion_formateada: str


def _limitar_uso(usuario_id: int) -> None:
    ahora = time.time()
    historial = _historial_geocodificacion[usuario_id]
    while historial and ahora - historial[0] > 60:
        historial.popleft()
    if len(historial) >= MAX_GEOCODIFICACIONES_POR_MINUTO:
        raise HTTPException(
            status_code=429,
            detail="Demasiadas búsquedas de dirección. Espera un minuto.",
        )
    historial.append(ahora)


@router.post("/geocodificar", response_model=GeocodificacionOut)
def geocodificar_direccion(
    datos: DireccionIn,
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    """Busca las coordenadas de una dirección dentro de la zona de Nicolás Romero."""
    _limitar_uso(usuario.id)
    try:
        resultado = google_maps.geocodificar(datos.direccion)
    except google_maps.ErrorGoogleMaps as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if resultado is None:
        raise HTTPException(
            status_code=404,
            detail="No se encontró esa dirección. Agrega calle, número y colonia.",
        )

    distancia = logistica.haversine_km(
        resultado["latitud"], resultado["longitud"], *google_maps.CENTRO_ZONA
    )
    if distancia > google_maps.RADIO_ZONA_KM:
        raise HTTPException(
            status_code=422,
            detail="La dirección queda fuera de la zona de servicio (Nicolás Romero).",
        )
    return resultado


@router.post("/direccion", response_model=DireccionOut)
def direccion_de_un_punto(
    datos: PuntoIn,
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    """Dirección de un punto del mapa (cuando el cliente mueve el pin)."""
    distancia = logistica.haversine_km(
        datos.latitud, datos.longitud, *google_maps.CENTRO_ZONA
    )
    if distancia > google_maps.RADIO_ZONA_KM:
        raise HTTPException(
            status_code=422,
            detail="Ese punto queda fuera de la zona de servicio (Nicolás Romero).",
        )

    _limitar_uso(usuario.id)
    try:
        direccion = google_maps.geocodificar_inverso(datos.latitud, datos.longitud)
    except google_maps.ErrorGoogleMaps as exc:
        raise HTTPException(status_code=503, detail=str(exc))

    if direccion is None:
        raise HTTPException(
            status_code=404, detail="No se encontró una dirección para ese punto."
        )
    return {"direccion_formateada": direccion}


# --------------------------------------------------------------------------
# Ruta de un pedido
# --------------------------------------------------------------------------

def _coord(lat, lon) -> Optional[tuple[float, float]]:
    lat, lon = logistica.a_float(lat), logistica.a_float(lon)
    if lat is None or lon is None:
        return None
    return (lat, lon)


def _en_linea_recta(paradas: list[tuple[float, float]]) -> dict:
    tramos = []
    for a, b in zip(paradas, paradas[1:]):
        km_tramo = logistica.haversine_km(*a, *b)
        tramos.append(
            {
                "distancia_m": int(km_tramo * 1000),
                "duracion_s": logistica.minutos_estimados(km_tramo) * 60,
                "puntos": [list(a), list(b)],
            }
        )
    km = sum(t["distancia_m"] for t in tramos) / 1000
    return {
        "fuente": "linea_recta",
        "distancia_m": int(km * 1000),
        "duracion_s": logistica.minutos_estimados(km) * 60,
        "puntos": [list(p) for p in paradas],
        "tramos": tramos,
    }


def _con_tramos(ruta: dict, paradas: list, tipos: list[str]) -> list[dict]:
    """
    Un trazo por tramo, rotulado por su destino: 'hacia_restaurante' o
    'hacia_cliente'. Si Google no dio tramos sueltos, se parte el trazo.
    """
    crudos = ruta.get("tramos") or []
    if len(crudos) != len(paradas) - 1:
        crudos = [
            {
                "distancia_m": ruta["distancia_m"],
                "duracion_s": ruta["duracion_s"],
                "puntos": ruta["puntos"],
            }
        ]
        tipos = [tipos[0], tipos[-1]]
    return [
        {
            "tipo": "hacia_restaurante" if destino == "restaurante" else "hacia_cliente",
            "distancia_m": t["distancia_m"],
            "duracion_s": t["duracion_s"],
            "puntos": [list(p) for p in t["puntos"]],
        }
        for t, destino in zip(crudos, tipos[1:])
    ]


@router.get("/ruta/{pedido_id}")
def ruta_del_pedido(
    pedido_id: int,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    """
    Trazo del pedido según su estado:
      - pendiente / aceptado: (repartidor ->) restaurante -> cliente
      - recogido / en_camino: (repartidor ->) cliente
      - entregado: restaurante -> cliente (el recorrido de la entrega)
      - cancelado: sin ruta (400)
    Devuelve un trazo por tramo ("tramos": hacia_restaurante / hacia_cliente)
    para pintarlos de distinto color. El repartidor puede mandar su posición
    en vivo (?lat=&lng=) para que el trazo salga desde donde está; la ruta se
    recalcula solo cuando se mueve ~200 m. Un repartidor también puede ver el
    trazo de un pedido pendiente (antes de aceptarlo).
    """
    pedido = db.get(Pedido, pedido_id)
    if pedido is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")

    es_dueno = pedido.cliente_id == usuario.id
    es_repartidor = pedido.repartidor_id == usuario.id
    es_admin = usuario.rol == RolUsuario.administrador
    puede_tomarlo = (
        usuario.rol == RolUsuario.repartidor
        and pedido.estado == EstadoPedido.pendiente
    )
    if not (es_dueno or es_repartidor or es_admin or puede_tomarlo):
        raise HTTPException(status_code=403, detail="No tienes acceso a este pedido.")

    if pedido.estado == EstadoPedido.cancelado:
        raise HTTPException(status_code=400, detail="Un pedido cancelado no tiene ruta.")

    restaurante = _coord(pedido.restaurante.latitud, pedido.restaurante.longitud)
    entrega = _coord(pedido.latitud_entrega, pedido.longitud_entrega)
    if restaurante is None or entrega is None:
        raise HTTPException(
            status_code=400, detail="Faltan coordenadas para calcular la ruta."
        )
    repartidor = _coord(pedido.latitud_repartidor, pedido.longitud_repartidor)
    if (es_repartidor or puede_tomarlo) and lat is not None and lng is not None:
        en_vivo = _coord(lat, lng)
        if en_vivo is not None:
            repartidor = en_vivo

    estado = pedido.estado.value
    if estado == "entregado":
        # Recorrido que hizo la entrega: restaurante -> cliente.
        repartidor = None
        paradas = [restaurante, entrega]
        tipos = ["restaurante", "entrega"]
    elif estado in ("recogido", "en_camino"):
        paradas = [repartidor or restaurante, entrega]
        tipos = ["origen", "entrega"]
    else:
        paradas = ([repartidor] if repartidor else []) + [restaurante, entrega]
        tipos = (["repartidor"] if repartidor else []) + ["restaurante", "entrega"]

    celda = (round(repartidor[0], 3), round(repartidor[1], 3)) if repartidor else None
    clave = (pedido.id, estado, celda)
    guardada = _CACHE_RUTAS.get(clave)
    if guardada and time.time() - guardada[0] < VIGENCIA_RUTA_SEGUNDOS:
        ruta = guardada[1]
    else:
        try:
            calculada = google_maps.calcular_ruta(
                paradas[0], paradas[-1], paradas[1:-1] or None
            )
            ruta = {
                "fuente": "google",
                "distancia_m": calculada["distancia_m"],
                "duracion_s": calculada["duracion_s"],
                "puntos": [list(p) for p in calculada["puntos"]],
                "tramos": calculada.get("tramos") or [],
            }
        except google_maps.ErrorGoogleMaps:
            ruta = _en_linea_recta(paradas)
        if len(_CACHE_RUTAS) >= MAX_RUTAS_EN_CACHE:
            _CACHE_RUTAS.clear()
        _CACHE_RUTAS[clave] = (time.time(), ruta)

    return {
        "pedido_id": pedido.id,
        "estado": estado,
        **{k: v for k, v in ruta.items() if k != "tramos"},
        "tramos": _con_tramos(ruta, paradas, tipos),
        "paradas": [
            {"tipo": t, "latitud": p[0], "longitud": p[1]}
            for t, p in zip(tipos, paradas)
        ],
    }
