"""Sprint 5: geocoding y ruta por calles (Google se sustituye por datos falsos)."""

import pytest

from app.routers import mapas
from app.services import google_maps

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


@pytest.fixture(autouse=True)
def _limpiar(monkeypatch):
    google_maps._CACHE_GEOCODIFICACION.clear()
    google_maps._CACHE_INVERSA.clear()
    mapas._CACHE_RUTAS.clear()
    mapas._historial_geocodificacion.clear()
    monkeypatch.setenv("GOOGLE_MAPS_SERVER_KEY", "llave-falsa-de-pruebas")


def _crear_pedido(client, menu, cliente):
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _respuesta_geocoding(lat=19.6187, lng=-99.3085, estado="OK"):
    if estado != "OK":
        return {"status": estado, "results": []}
    return {
        "status": "OK",
        "results": [{
            "formatted_address": "Av. Hidalgo 80, Nicolás Romero, Méx.",
            "place_id": "ChIJprueba",
            "geometry": {"location": {"lat": lat, "lng": lng}, "location_type": "ROOFTOP"},
        }],
    }


# ------------------------------------------------------------- polilínea

def test_decodificar_polilinea_ejemplo_de_google():
    puntos = google_maps.decodificar_polilinea("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    assert puntos == [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]


# ------------------------------------------------------------- geocoding

def test_geocodificar_requiere_sesion(client):
    r = client.post("/mapas/geocodificar", json={"direccion": "Av. Hidalgo 80"})
    assert r.status_code == 401


def test_geocodificar_ok_y_cache(client, cliente, monkeypatch):
    llamadas = []

    def falso(url):
        llamadas.append(url)
        return _respuesta_geocoding()

    monkeypatch.setattr(google_maps, "_get_json", falso)
    for _ in range(2):
        r = client.post("/mapas/geocodificar", headers=cliente,
                        json={"direccion": "Av. Hidalgo 80"})
        assert r.status_code == 200, r.text
        assert r.json()["latitud"] == 19.6187
        assert r.json()["place_id"] == "ChIJprueba"
    assert len(llamadas) == 1  # la segunda salió de la caché
    assert "Nicol%C3%A1s+Romero" in llamadas[0]  # se agregó la ciudad


def test_geocodificar_no_encontrada(client, cliente, monkeypatch):
    monkeypatch.setattr(google_maps, "_get_json",
                        lambda url: _respuesta_geocoding(estado="ZERO_RESULTS"))
    r = client.post("/mapas/geocodificar", headers=cliente,
                    json={"direccion": "Calle inexistente 999"})
    assert r.status_code == 404


def test_geocodificar_fuera_de_zona(client, cliente, monkeypatch):
    monkeypatch.setattr(google_maps, "_get_json",
                        lambda url: _respuesta_geocoding(lat=19.43, lng=-99.13))
    r = client.post("/mapas/geocodificar", headers=cliente,
                    json={"direccion": "Zócalo, Ciudad de México"})
    assert r.status_code == 422


def test_geocodificar_sin_llave(client, cliente, monkeypatch):
    monkeypatch.setenv("GOOGLE_MAPS_SERVER_KEY", "")
    monkeypatch.delenv("GOOGLE_MAPS_API_KEY", raising=False)
    r = client.post("/mapas/geocodificar", headers=cliente,
                    json={"direccion": "Av. Hidalgo 80"})
    assert r.status_code == 503
    assert "GOOGLE_MAPS_SERVER_KEY" in r.json()["detail"]


def test_geocodificar_limite_por_minuto(client, cliente, monkeypatch):
    monkeypatch.setattr(google_maps, "_get_json", lambda url: _respuesta_geocoding())
    monkeypatch.setattr(mapas, "MAX_GEOCODIFICACIONES_POR_MINUTO", 2)
    codigos = [
        client.post("/mapas/geocodificar", headers=cliente,
                    json={"direccion": "Av. Hidalgo 80"}).status_code
        for _ in range(3)
    ]
    assert codigos == [200, 200, 429]


# ------------------------------------------------------------------ ruta

def test_ruta_google_y_cache_por_estado(client, menu, cliente, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)
    llamadas = []

    def falsa(origen, destino, intermedios=None):
        llamadas.append((origen, destino, intermedios))
        return {"distancia_m": 2300, "duracion_s": 540,
                "puntos": [origen, (19.605, -99.304), destino]}

    monkeypatch.setattr(google_maps, "calcular_ruta", falsa)
    for _ in range(3):
        r = client.get(f"/mapas/ruta/{pid}", headers=cliente)
        assert r.status_code == 200, r.text
    d = r.json()
    assert d["fuente"] == "google"
    assert d["distancia_m"] == 2300 and d["duracion_s"] == 540
    assert len(d["puntos"]) == 3
    assert [p["tipo"] for p in d["paradas"]] == ["restaurante", "entrega"]
    assert len(llamadas) == 1  # se calcula una sola vez por pedido y estado


def test_ruta_con_repartidor_pasa_por_restaurante(client, menu, cliente, repartidor, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    assert client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
                      json={"latitud": 19.6200, "longitud": -99.3100}).status_code == 200

    capturado = {}

    def falsa(origen, destino, intermedios=None):
        capturado.update(origen=origen, destino=destino, intermedios=intermedios)
        return {"distancia_m": 1, "duracion_s": 1, "puntos": [origen, destino]}

    monkeypatch.setattr(google_maps, "calcular_ruta", falsa)
    r = client.get(f"/mapas/ruta/{pid}", headers=repartidor)
    assert r.status_code == 200, r.text
    assert capturado["origen"] == (19.62, -99.31)
    assert capturado["intermedios"] == [(19.601, -99.3085)]  # el restaurante
    assert capturado["destino"] == (19.61, -99.3)
    assert [p["tipo"] for p in r.json()["paradas"]] == ["repartidor", "restaurante", "entrega"]


def test_ruta_cae_a_linea_recta_si_google_falla(client, menu, cliente, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)

    def falla(*a, **k):
        raise google_maps.ErrorGoogleMaps("sin cuota")

    monkeypatch.setattr(google_maps, "calcular_ruta", falla)
    r = client.get(f"/mapas/ruta/{pid}", headers=cliente)
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["fuente"] == "linea_recta"
    assert d["distancia_m"] > 0 and len(d["puntos"]) == 2


def test_ruta_solo_para_participantes(client, menu, cliente, repartidor, repartidor2):
    pid = _crear_pedido(client, menu, cliente)
    # Pendiente: cualquier repartidor puede ver el trazo antes de aceptar.
    assert client.get(f"/mapas/ruta/{pid}", headers=repartidor2).status_code == 200
    # Ya aceptado por otro repartidor: solo participantes.
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    assert client.get(f"/mapas/ruta/{pid}", headers=repartidor2).status_code == 403
    assert client.get("/mapas/ruta/9999", headers=cliente).status_code == 404


# ------------------------------------------------------- zona de servicio

def test_cotizar_y_pedido_fuera_de_zona(client, cliente, menu):
    """Una entrega lejos de Nicolás Romero (Zócalo CDMX) se rechaza."""
    cuerpo = {
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "latitud_entrega": 19.4326,
        "longitud_entrega": -99.1332,
    }
    r = client.post("/pedidos/cotizar", headers=cliente, json=cuerpo)
    assert r.status_code == 422
    assert "fuera de la zona" in r.json()["detail"]

    r = client.post(
        "/pedidos",
        headers=cliente,
        json={**cuerpo, "direccion_entrega": "Zócalo CDMX", "metodo_pago": "efectivo"},
    )
    assert r.status_code == 422


# ------------------------------------------------- dirección de un punto (pin)

def _respuesta_inversa():
    return {
        "status": "OK",
        "results": [
            {"formatted_address": "7G8X+4M Nicolás Romero, Méx.", "types": ["plus_code"]},
            {"formatted_address": "Playa Alhelí 12, El Tráfico, Nicolás Romero, Méx., México",
             "types": ["street_address"]},
        ],
    }


def test_direccion_de_un_punto_ok_y_cache(client, cliente, monkeypatch):
    llamadas = []

    def falso(url):
        llamadas.append(url)
        return _respuesta_inversa()

    monkeypatch.setattr(google_maps, "_get_json", falso)
    for _ in range(2):
        r = client.post("/mapas/direccion", headers=cliente,
                        json={"latitud": 19.6187, "longitud": -99.3085})
        assert r.status_code == 200, r.text
        # se salta el "plus code" y toma la dirección real
        assert r.json()["direccion_formateada"].startswith("Playa Alhelí 12")
    assert len(llamadas) == 1


def test_direccion_de_un_punto_fuera_de_zona_y_sin_sesion(client, cliente, monkeypatch):
    monkeypatch.setattr(google_maps, "_get_json", lambda url: _respuesta_inversa())
    r = client.post("/mapas/direccion", headers=cliente,
                    json={"latitud": 19.4326, "longitud": -99.1332})
    assert r.status_code == 422
    r = client.post("/mapas/direccion", json={"latitud": 19.6187, "longitud": -99.3085})
    assert r.status_code == 401


def test_direccion_de_un_punto_sin_resultados(client, cliente, monkeypatch):
    monkeypatch.setattr(google_maps, "_get_json",
                        lambda url: {"status": "ZERO_RESULTS", "results": []})
    r = client.post("/mapas/direccion", headers=cliente,
                    json={"latitud": 19.6187, "longitud": -99.3085})
    assert r.status_code == 404


# ------------------------------------------------------- tramos por color

def test_ruta_devuelve_un_trazo_por_tramo(client, menu, cliente, repartidor, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    llamadas = []

    def falsa(origen, destino, intermedios=None):
        llamadas.append(origen)
        medio = intermedios[0]
        return {
            "distancia_m": 3000, "duracion_s": 600,
            "puntos": [origen, medio, destino],
            "tramos": [
                {"distancia_m": 1000, "duracion_s": 200, "puntos": [origen, medio]},
                {"distancia_m": 2000, "duracion_s": 400, "puntos": [medio, destino]},
            ],
        }

    monkeypatch.setattr(google_maps, "calcular_ruta", falsa)
    r = client.get(f"/mapas/ruta/{pid}?lat=19.62&lng=-99.31", headers=repartidor)
    assert r.status_code == 200, r.text
    tramos = r.json()["tramos"]
    assert [t["tipo"] for t in tramos] == ["hacia_restaurante", "hacia_cliente"]
    assert tramos[0]["distancia_m"] == 1000 and len(tramos[1]["puntos"]) == 2
    assert llamadas[0] == (19.62, -99.31)  # sale de la posición en vivo

    # Misma celda: no se vuelve a calcular; otra celda (se movió): sí.
    client.get(f"/mapas/ruta/{pid}?lat=19.6201&lng=-99.3101", headers=repartidor)
    assert len(llamadas) == 1
    client.get(f"/mapas/ruta/{pid}?lat=19.63&lng=-99.32", headers=repartidor)
    assert len(llamadas) == 2


def test_ruta_sin_tramos_de_google_se_parte_en_uno(client, menu, cliente, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)
    monkeypatch.setattr(google_maps, "calcular_ruta",
                        lambda o, d, i=None: {"distancia_m": 5, "duracion_s": 5, "puntos": [o, d]})
    d = client.get(f"/mapas/ruta/{pid}", headers=cliente).json()
    assert [t["tipo"] for t in d["tramos"]] == ["hacia_cliente"]


def test_ruta_de_pedido_pendiente_visible_para_repartidor(client, menu, cliente, repartidor, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)

    def falla(*a, **k):
        raise google_maps.ErrorGoogleMaps("sin cuota")

    monkeypatch.setattr(google_maps, "calcular_ruta", falla)
    r = client.get(f"/mapas/ruta/{pid}?lat=19.62&lng=-99.31", headers=repartidor)
    assert r.status_code == 200, r.text
    assert [t["tipo"] for t in r.json()["tramos"]] == ["hacia_restaurante", "hacia_cliente"]


def test_ruta_de_pedido_entregado_es_restaurante_a_cliente(client, menu, cliente, repartidor, monkeypatch):
    pid = _crear_pedido(client, menu, cliente)
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    for estado in ("recogido", "en_camino", "entregado"):
        r = client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text

    llamadas = []

    def falsa(origen, destino, intermedios=None):
        llamadas.append((origen, destino, intermedios))
        return {"distancia_m": 1200, "duracion_s": 300, "puntos": [origen, destino]}

    monkeypatch.setattr(google_maps, "calcular_ruta", falsa)
    r = client.get(f"/mapas/ruta/{pid}", headers=cliente)
    assert r.status_code == 200, r.text
    datos = r.json()
    assert datos["estado"] == "entregado"
    assert [t["tipo"] for t in datos["tramos"]] == ["hacia_cliente"]
    assert llamadas[0][2] is None  # solo restaurante -> cliente, sin repartidor


def test_ruta_de_pedido_cancelado_no_existe(client, menu, cliente):
    pid = _crear_pedido(client, menu, cliente)
    assert client.post(f"/pedidos/{pid}/cancelar", headers=cliente).status_code == 200
    r = client.get(f"/mapas/ruta/{pid}", headers=cliente)
    assert r.status_code == 400
