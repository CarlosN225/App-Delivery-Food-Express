"""
Cliente de Google Maps Platform para el backend (Sprint 5).

Usa la llave del SERVIDOR (`GOOGLE_MAPS_SERVER_KEY`, en el `.env`), nunca la
del navegador. APIs usadas:
  - Geocoding API: dirección escrita -> latitud/longitud.
  - Routes API (computeRoutes): ruta real por calles entre puntos.

Se usa solo la librería estándar (urllib), así no hay dependencias nuevas.

Ahorro de cuota (la facturación es por llamada):
  - Cada dirección se geocodifica una sola vez (caché en memoria).
  - Cada ruta se calcula una sola vez por pedido y estado (ver routers/mapas.py).
Los términos de Google solo permiten guardar latitud/longitud y place_id.
"""

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

GEOCODING_URL = "https://maps.googleapis.com/maps/api/geocode/json"
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
TIMEOUT_SEGUNDOS = 8

# Zona de servicio: Nicolás Romero, Edo. Méx. (centro aproximado y radio).
CENTRO_ZONA = (19.62, -99.31)
RADIO_ZONA_KM = 20.0
# Caja usada solo para sesgar la búsqueda hacia la zona (southwest | northeast).
SESGO_ZONA = "19.55,-99.40|19.70,-99.22"

_CACHE_GEOCODIFICACION: dict[str, tuple[float, dict]] = {}
VIGENCIA_CACHE_SEGUNDOS = 24 * 3600


class ErrorGoogleMaps(Exception):
    """Fallo al consultar Google (sin llave, red, cuota o respuesta inválida)."""


def llave_servidor() -> str:
    return (
        os.getenv("GOOGLE_MAPS_SERVER_KEY") or os.getenv("GOOGLE_MAPS_API_KEY") or ""
    ).strip()


def hay_llave() -> bool:
    return bool(llave_servidor())


# --------------------------------------------------------------------------
# Acceso HTTP (se separa para poder sustituirlo en las pruebas)
# --------------------------------------------------------------------------

def _get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT_SEGUNDOS) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as exc:  # no se incluye la URL: lleva la llave
        raise ErrorGoogleMaps(f"No se pudo consultar Google ({type(exc).__name__}).")


def _post_json(url: str, cuerpo: dict, cabeceras: dict) -> dict:
    datos = json.dumps(cuerpo).encode("utf-8")
    peticion = urllib.request.Request(
        url,
        data=datos,
        headers={"Content-Type": "application/json", **cabeceras},
        method="POST",
    )
    try:
        with urllib.request.urlopen(peticion, timeout=TIMEOUT_SEGUNDOS) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise ErrorGoogleMaps(f"Google respondió con error HTTP {exc.code}.")
    except Exception as exc:
        raise ErrorGoogleMaps(f"No se pudo consultar Google ({type(exc).__name__}).")


# --------------------------------------------------------------------------
# Geocoding
# --------------------------------------------------------------------------

def _normalizar(direccion: str) -> str:
    return " ".join(direccion.lower().split())


def geocodificar(direccion: str) -> Optional[dict]:
    """
    Convierte una dirección en coordenadas. Devuelve None si Google no la
    encuentra. Lanza ErrorGoogleMaps si no hay llave o falla la consulta.
    """
    if not hay_llave():
        raise ErrorGoogleMaps("Falta GOOGLE_MAPS_SERVER_KEY en el .env del backend.")

    consulta = direccion.strip()
    if "nicol" not in consulta.lower():
        consulta += ", Nicolás Romero, Estado de México"

    clave = _normalizar(consulta)
    en_cache = _CACHE_GEOCODIFICACION.get(clave)
    if en_cache and time.time() - en_cache[0] < VIGENCIA_CACHE_SEGUNDOS:
        return en_cache[1]

    parametros = urllib.parse.urlencode(
        {
            "address": consulta,
            "components": "country:MX",
            "region": "mx",
            "language": "es",
            "bounds": SESGO_ZONA,
            "key": llave_servidor(),
        }
    )
    respuesta = _get_json(f"{GEOCODING_URL}?{parametros}")

    estado = respuesta.get("status")
    if estado == "ZERO_RESULTS":
        return None
    if estado != "OK" or not respuesta.get("results"):
        raise ErrorGoogleMaps(f"Geocoding respondió con estado {estado}.")

    mejor = respuesta["results"][0]
    ubicacion = mejor["geometry"]["location"]
    resultado = {
        "latitud": float(ubicacion["lat"]),
        "longitud": float(ubicacion["lng"]),
        "direccion_formateada": mejor.get("formatted_address", ""),
        "place_id": mejor.get("place_id"),
        "precision": mejor["geometry"].get("location_type"),
        "coincidencia_parcial": bool(mejor.get("partial_match", False)),
    }
    _CACHE_GEOCODIFICACION[clave] = (time.time(), resultado)
    return resultado


# --------------------------------------------------------------------------
# Routes API
# --------------------------------------------------------------------------

def decodificar_polilinea(codificada: str) -> list[tuple[float, float]]:
    """Decodifica el formato 'encoded polyline' de Google a [(lat, lng), ...]."""
    puntos: list[tuple[float, float]] = []
    indice = lat = lng = 0
    while indice < len(codificada):
        for es_lat in (True, False):
            desplazamiento = resultado = 0
            while True:
                byte = ord(codificada[indice]) - 63
                indice += 1
                resultado |= (byte & 0x1F) << desplazamiento
                desplazamiento += 5
                if byte < 0x20:
                    break
            cambio = ~(resultado >> 1) if resultado & 1 else resultado >> 1
            if es_lat:
                lat += cambio
            else:
                lng += cambio
        puntos.append((lat / 1e5, lng / 1e5))
    return puntos


def _punto(coord: tuple[float, float]) -> dict:
    return {"location": {"latLng": {"latitude": coord[0], "longitude": coord[1]}}}


def calcular_ruta(
    origen: tuple[float, float],
    destino: tuple[float, float],
    intermedios: Optional[list[tuple[float, float]]] = None,
) -> dict:
    """
    Ruta por calles (en auto/moto) de origen a destino pasando por los
    intermedios en orden. Devuelve distancia en metros, duración en segundos y
    los puntos del trazo [(lat, lng), ...].
    """
    if not hay_llave():
        raise ErrorGoogleMaps("Falta GOOGLE_MAPS_SERVER_KEY en el .env del backend.")

    cuerpo = {
        "origin": _punto(origen),
        "destination": _punto(destino),
        "travelMode": "DRIVE",
        "languageCode": "es-MX",
        "units": "METRIC",
    }
    if intermedios:
        cuerpo["intermediates"] = [_punto(c) for c in intermedios]

    cabeceras = {
        "X-Goog-Api-Key": llave_servidor(),
        "X-Goog-FieldMask": (
            "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"
        ),
    }
    respuesta = _post_json(ROUTES_URL, cuerpo, cabeceras)

    rutas = respuesta.get("routes") or []
    if not rutas:
        raise ErrorGoogleMaps("Google no devolvió ninguna ruta.")
    ruta = rutas[0]
    try:
        puntos = decodificar_polilinea(ruta["polyline"]["encodedPolyline"])
        segundos = int(str(ruta.get("duration", "0s")).rstrip("s").split(".")[0])
        return {
            "distancia_m": int(ruta.get("distanceMeters", 0)),
            "duracion_s": segundos,
            "puntos": puntos,
        }
    except (KeyError, ValueError, IndexError):
        raise ErrorGoogleMaps("Respuesta de ruta con formato inesperado.")
