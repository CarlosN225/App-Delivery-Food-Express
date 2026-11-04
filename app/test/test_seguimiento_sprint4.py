"""Sprint 4, historia #14: seguimiento del pedido en tiempo real."""

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _pedido_aceptado(client, menu, cliente, repartidor):
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    return pid


def test_repartidor_reporta_y_cliente_ve_ubicacion(client, menu, cliente, repartidor):
    pid = _pedido_aceptado(client, menu, cliente, repartidor)

    # Antes de que el repartidor reporte nada, el cliente ve estado y destino.
    s = client.get(f"/pedidos/{pid}/seguimiento", headers=cliente).json()
    assert s["estado"] == "aceptado"
    assert s["repartidor_nombre"] == "Beto"
    assert s["repartidor_latitud"] is None
    assert s["segundos_desde_ubicacion"] is None
    assert s["minutos_restantes"] >= 1

    r = client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
                   json={"latitud": 19.5990, "longitud": -99.3150})
    assert r.status_code == 200, r.text

    s = client.get(f"/pedidos/{pid}/seguimiento", headers=cliente).json()
    assert s["repartidor_latitud"] == 19.5990
    assert s["repartidor_longitud"] == -99.3150
    assert s["segundos_desde_ubicacion"] < 10
    assert s["distancia_restante_km"] > 0


def test_tiempo_restante_baja_al_acercarse(client, menu, cliente, repartidor):
    pid = _pedido_aceptado(client, menu, cliente, repartidor)
    for estado in ("recogido", "en_camino"):
        client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})

    client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
               json={"latitud": 19.5500, "longitud": -99.3500})
    lejos = client.get(f"/pedidos/{pid}/seguimiento", headers=cliente).json()

    client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
               json={"latitud": 19.6099, "longitud": -99.3001})
    cerca = client.get(f"/pedidos/{pid}/seguimiento", headers=cliente).json()

    assert cerca["distancia_restante_km"] < lejos["distancia_restante_km"]
    assert cerca["minutos_restantes"] <= lejos["minutos_restantes"]


def test_seguimiento_permisos_y_validaciones(client, menu, cliente, repartidor, repartidor2):
    pid = _pedido_aceptado(client, menu, cliente, repartidor)

    # Otro repartidor no puede reportar ubicación de un pedido que no es suyo.
    assert client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor2,
                      json={"latitud": 19.6, "longitud": -99.3}).status_code == 403
    # El cliente no reporta ubicación (solo repartidores).
    assert client.put(f"/pedidos/{pid}/ubicacion", headers=cliente,
                      json={"latitud": 19.6, "longitud": -99.3}).status_code == 403
    # Coordenadas fuera de rango.
    assert client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
                      json={"latitud": 123, "longitud": -99.3}).status_code == 422

    # Otro cliente no puede espiar el seguimiento.
    r = client.post("/auth/registro", json={
        "nombre": "Dani", "correo": "dani@correo.com",
        "contrasena": "secreto1", "rol": "cliente"})
    assert r.status_code == 201, r.text
    token = client.post("/auth/login", data={
        "username": "dani@correo.com", "password": "secreto1"}).json()["access_token"]
    ajeno = {"Authorization": f"Bearer {token}"}
    assert client.get(f"/pedidos/{pid}/seguimiento", headers=ajeno).status_code == 403
    assert client.get(f"/pedidos/{pid}/seguimiento").status_code == 401

    # Con el pedido entregado ya no se reporta ubicación.
    for estado in ("recogido", "en_camino", "entregado"):
        client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})
    assert client.put(f"/pedidos/{pid}/ubicacion", headers=repartidor,
                      json={"latitud": 19.6, "longitud": -99.3}).status_code == 400
    s = client.get(f"/pedidos/{pid}/seguimiento", headers=cliente).json()
    assert s["estado"] == "entregado"
    assert s["minutos_restantes"] is None