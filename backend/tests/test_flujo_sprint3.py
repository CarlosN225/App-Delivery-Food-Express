"""Flujo completo del Sprint 3: carrito -> pedido -> pago -> repartidor -> entrega."""

import re

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _pedido_body(menu, metodo="efectivo", **extra):
    body = {
        "restaurante_id": menu["pizza"],
        "items": [
            {"producto_id": menu["pepperoni"], "cantidad": 1},
            {"producto_id": menu["coca"], "cantidad": 2},
        ],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": metodo,
        **ENTREGA,
    }
    body.update(extra)
    return body


# ---------------------------------------------------------------- #9 carrito

def test_cotizar_calcula_en_servidor(client, menu, cliente):
    r = client.post("/pedidos/cotizar", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1},
                  {"producto_id": menu["coca"], "cantidad": 2}],
        **ENTREGA,
    })
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["subtotal"] == 180.0
    assert d["costo_envio"] >= 30.0
    assert abs(d["total"] - (d["subtotal"] + d["costo_envio"])) < 0.01


def test_crear_pedido_efectivo(client, menu, cliente):
    r = client.post("/pedidos", headers=cliente, json=_pedido_body(menu))
    assert r.status_code == 201, r.text
    p = r.json()
    assert p["estado"] == "pendiente"
    assert p["estado_pago"] == "contra_entrega"
    assert p["subtotal"] == 180.0
    assert len(p["items"]) == 2
    assert {i["nombre"] for i in p["items"]} == {"Pepperoni", "Coca-Cola"}

    mis = client.get("/pedidos/mis-pedidos", headers=cliente).json()
    assert [x["id"] for x in mis] == [p["id"]]
    assert client.get(f"/pedidos/{p['id']}", headers=cliente).status_code == 200


def test_crear_pedido_validaciones(client, menu, cliente, repartidor):
    # Producto de otro restaurante
    mal = _pedido_body(menu, items=[{"producto_id": menu["taco"], "cantidad": 1}])
    assert client.post("/pedidos", headers=cliente, json=mal).status_code == 400
    # Producto inexistente
    mal = _pedido_body(menu, items=[{"producto_id": 9999, "cantidad": 1}])
    assert client.post("/pedidos", headers=cliente, json=mal).status_code == 400
    # Carrito vacío / cantidad inválida
    assert client.post("/pedidos", headers=cliente, json=_pedido_body(menu, items=[])).status_code == 422
    mal = _pedido_body(menu, items=[{"producto_id": menu["coca"], "cantidad": 0}])
    assert client.post("/pedidos", headers=cliente, json=mal).status_code == 422
    # Restaurante inexistente
    assert client.post("/pedidos", headers=cliente, json=_pedido_body(menu, restaurante_id=999)).status_code == 404
    # Sin sesión y con rol equivocado
    assert client.post("/pedidos", json=_pedido_body(menu)).status_code == 401
    assert client.post("/pedidos", headers=repartidor, json=_pedido_body(menu)).status_code == 403


def test_el_cliente_no_puede_inyectar_precios(client, menu, cliente):
    body = _pedido_body(menu)
    body["items"][0]["precio"] = 1  # campo extra: se ignora
    body["total"] = 1
    p = client.post("/pedidos", headers=cliente, json=body).json()
    assert p["subtotal"] == 180.0


def test_cancelar_pedido(client, menu, cliente, repartidor):
    pid = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    r = client.post(f"/pedidos/{pid}/cancelar", headers=cliente)
    assert r.status_code == 200 and r.json()["estado"] == "cancelado"

    pid2 = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    client.put(f"/pedidos/{pid2}/aceptar", headers=repartidor)
    assert client.post(f"/pedidos/{pid2}/cancelar", headers=cliente).status_code == 400


# ------------------------------------------------------------------ #10 pagos

def _ruta_de(url: str) -> str:
    return re.sub(r"^https?://[^/]+", "", url)


def test_pago_mercado_pago_modo_demo(client, menu, cliente, repartidor):
    p = client.post("/pedidos", headers=cliente, json=_pedido_body(menu, "mercado_pago")).json()
    pid = p["id"]
    assert p["estado_pago"] == "pendiente"

    # Mientras no se pague, no aparece para los repartidores ni se puede aceptar.
    assert client.get("/pedidos/disponibles", headers=repartidor).json() == []
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 400

    pref = client.post(f"/pagos/pedido/{pid}/preferencia", headers=cliente).json()
    assert pref["modo"] == "demo"
    enlace = _ruta_de(pref["init_point"])
    assert client.get(enlace).status_code == 200  # página del simulador

    # Rechazado: sigue sin estar disponible
    assert client.post(enlace.replace("?t=", "/rechazar?t=")).status_code == 200
    v = client.post(f"/pagos/pedido/{pid}/verificar", headers=cliente).json()
    assert v["estado_pago"] == "rechazado"
    assert client.get("/pedidos/disponibles", headers=repartidor).json() == []

    # Segundo intento: aprobado
    pref = client.post(f"/pagos/pedido/{pid}/preferencia", headers=cliente).json()
    enlace = _ruta_de(pref["init_point"])
    assert client.post(enlace.replace("?t=", "/aprobar?t=")).status_code == 200
    v = client.post(f"/pagos/pedido/{pid}/verificar", headers=cliente).json()
    assert v["estado_pago"] == "pagado"
    assert [x["id"] for x in client.get("/pedidos/disponibles", headers=repartidor).json()] == [pid]

    # Ya pagado: no se puede volver a pagar ni cancelar
    assert client.post(f"/pagos/pedido/{pid}/preferencia", headers=cliente).status_code == 400
    assert client.post(f"/pedidos/{pid}/cancelar", headers=cliente).status_code == 400


def test_pagos_requieren_ser_dueno_y_token_valido(client, menu, cliente, repartidor):
    pid = client.post("/pedidos", headers=cliente, json=_pedido_body(menu, "mercado_pago")).json()["id"]
    assert client.post(f"/pagos/pedido/{pid}/preferencia", headers=repartidor).status_code == 403
    assert client.get(f"/pagos/simulador/{pid}?t=basura").status_code == 403
    # Pedido en efectivo no usa Mercado Pago
    pe = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    assert client.post(f"/pagos/pedido/{pe}/preferencia", headers=cliente).status_code == 400


# ------------------------------------------------- repartidor, #11 y #12

def test_disponibles_aceptar_rechazar(client, menu, cliente, repartidor, repartidor2):
    pid = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]

    # El cliente no ve el panel de repartidor
    assert client.get("/pedidos/disponibles", headers=cliente).status_code == 403

    lista = client.get("/pedidos/disponibles?latitud=19.60&longitud=-99.30", headers=repartidor).json()
    assert len(lista) == 1
    assert lista[0]["restaurante"] == "Pizza Express"
    assert lista[0]["distancia_km"] is not None
    assert lista[0]["distancia_entrega_km"] is not None

    # Rechazar solo lo oculta para quien rechazó
    assert client.put(f"/pedidos/{pid}/rechazar", headers=repartidor).status_code == 200
    assert client.put(f"/pedidos/{pid}/rechazar", headers=repartidor).status_code == 200  # idempotente
    assert client.get("/pedidos/disponibles", headers=repartidor).json() == []
    assert len(client.get("/pedidos/disponibles", headers=repartidor2).json()) == 1
    assert client.get(f"/pedidos/{pid}", headers=cliente).json()["estado"] == "pendiente"

    # Aceptar: solo uno gana
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor2).status_code == 200
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 400
    assert client.get("/pedidos/disponibles", headers=repartidor2).json() == []


def test_estado_de_entrega_y_cobro_en_efectivo(client, menu, cliente, repartidor, repartidor2):
    pid = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    client.put(f"/pedidos/{pid}/aceptar", headers=repartidor)

    def cambiar(estado, headers=repartidor):
        return client.put(f"/pedidos/{pid}/estado", headers=headers, json={"estado": estado})

    # Orden obligatorio y solo el repartidor asignado
    assert cambiar("entregado").status_code == 400
    assert cambiar("en_camino").status_code == 400
    assert cambiar("recogido", repartidor2).status_code == 403
    assert cambiar("recogido", cliente).status_code == 403

    assert cambiar("recogido").json()["estado"] == "recogido"
    assert client.get(f"/pedidos/{pid}", headers=cliente).json()["estado"] == "recogido"
    assert cambiar("recogido").status_code == 400  # no se repite
    assert cambiar("en_camino").json()["estado"] == "en_camino"

    final = cambiar("entregado").json()
    assert final["estado"] == "entregado"
    assert final["estado_pago"] == "pagado"  # efectivo cobrado al entregar
    assert cambiar("entregado").status_code == 400  # ya terminado


def test_ruta_optima_y_ruta_de_pedido(client, menu, cliente, repartidor):
    a = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    b = client.post("/pedidos", headers=cliente, json=_pedido_body(
        menu, restaurante_id=menu["tacos"],
        items=[{"producto_id": menu["taco"], "cantidad": 3}],
        latitud_entrega=19.5900, longitud_entrega=-99.3250,
    )).json()["id"]

    vacia = client.get("/pedidos/ruta-optima", headers=repartidor).json()
    assert vacia["tramos"] == []

    client.put(f"/pedidos/{a}/aceptar", headers=repartidor)
    client.put(f"/pedidos/{b}/aceptar", headers=repartidor)

    activos = client.get("/pedidos/activos", headers=repartidor).json()
    assert {p["id"] for p in activos} == {a, b}

    ruta = client.get("/pedidos/ruta-optima?latitud=19.6000&longitud=-99.3000", headers=repartidor).json()
    assert len(ruta["tramos"]) == 4
    assert ruta["distancia_total_km"] > 0 and ruta["minutos_total"] > 0
    # Cada pedido se recoge antes de entregarse
    for pid in (a, b):
        tipos = [t["tipo"] for t in ruta["tramos"] if t["pedido_id"] == pid]
        assert tipos == ["recoger", "entregar"]

    # Ruta individual según estado
    r1 = client.get(f"/pedidos/{a}/ruta?latitud=19.6000&longitud=-99.3000", headers=repartidor).json()
    assert [t["tipo"] for t in r1["tramos"]] == ["recoger", "entregar"]
    client.put(f"/pedidos/{a}/estado", headers=repartidor, json={"estado": "recogido"})
    r2 = client.get(f"/pedidos/{a}/ruta?latitud=19.6000&longitud=-99.3000", headers=repartidor).json()
    assert [t["tipo"] for t in r2["tramos"]] == ["entregar"]

    # Pedido entregado deja de estar en la ruta
    client.put(f"/pedidos/{a}/estado", headers=repartidor, json={"estado": "en_camino"})
    client.put(f"/pedidos/{a}/estado", headers=repartidor, json={"estado": "entregado"})
    ruta = client.get("/pedidos/ruta-optima", headers=repartidor).json()
    assert {t["pedido_id"] for t in ruta["tramos"]} == {b}


def test_detalle_de_pedido_ajeno_prohibido(client, menu, cliente, repartidor):
    pid = client.post("/pedidos", headers=cliente, json=_pedido_body(menu)).json()["id"]
    assert client.get(f"/pedidos/{pid}", headers=repartidor).status_code == 403
    assert client.get("/pedidos/9999", headers=cliente).status_code == 404
