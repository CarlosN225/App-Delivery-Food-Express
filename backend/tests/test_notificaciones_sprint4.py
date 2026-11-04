"""Sprint 4, historia #15: notificaciones del estado del pedido."""

from app.models import TokenDispositivo

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


def test_cada_cambio_de_estado_notifica_al_cliente(client, menu, cliente, repartidor):
    pid = _pedido_aceptado(client, menu, cliente, repartidor)

    n = client.get("/notificaciones", headers=cliente).json()
    assert [x["titulo"] for x in n] == ["Pedido aceptado"]
    assert n[0]["pedido_id"] == pid
    assert n[0]["leida"] is False
    assert n[0]["hace_segundos"] < 10

    for estado in ("recogido", "en_camino", "entregado"):
        r = client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text

    n = client.get("/notificaciones", headers=cliente).json()
    assert [x["titulo"] for x in n] == [
        "Pedido entregado",
        "¡Tu pedido va en camino!",
        "Pedido recogido",
        "Pedido aceptado",
    ]
    assert client.get("/notificaciones/no-leidas", headers=cliente).json() == {"no_leidas": 4}
    # Las notificaciones son del cliente: el repartidor no recibe ninguna.
    assert client.get("/notificaciones", headers=repartidor).json() == []


def test_marcar_leidas_y_desde_id(client, menu, cliente, repartidor):
    pid = _pedido_aceptado(client, menu, cliente, repartidor)
    client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": "recogido"})

    n = client.get("/notificaciones", headers=cliente).json()
    nueva, vieja = n[0], n[1]

    # desde_id devuelve solo las posteriores.
    r = client.get("/notificaciones", headers=cliente, params={"desde_id": vieja["id"]}).json()
    assert [x["id"] for x in r] == [nueva["id"]]

    assert client.put(f"/notificaciones/{vieja['id']}/leida", headers=cliente).status_code == 200
    assert client.get("/notificaciones/no-leidas", headers=cliente).json() == {"no_leidas": 1}
    assert client.put("/notificaciones/leidas", headers=cliente).status_code == 200
    assert client.get("/notificaciones/no-leidas", headers=cliente).json() == {"no_leidas": 0}

    # No se puede marcar una notificación ajena ni una que no existe.
    assert client.put(f"/notificaciones/{nueva['id']}/leida", headers=repartidor).status_code == 404
    assert client.put("/notificaciones/9999/leida", headers=cliente).status_code == 404
    assert client.get("/notificaciones").status_code == 401


def test_registrar_token_no_duplica(client, db, cliente, repartidor):
    body = {"token": "t" * 40, "plataforma": "android"}
    assert client.post("/notificaciones/token", headers=cliente, json=body).status_code == 200
    assert client.post("/notificaciones/token", headers=cliente, json=body).status_code == 200
    db.expire_all()
    assert db.query(TokenDispositivo).count() == 1

    # El mismo celular con otra cuenta: el token pasa a ese usuario, sin duplicarse.
    assert client.post("/notificaciones/token", headers=repartidor, json=body).status_code == 200
    db.expire_all()
    assert db.query(TokenDispositivo).count() == 1

    # Un token demasiado corto se rechaza.
    corto = {"token": "corto"}
    assert client.post("/notificaciones/token", headers=cliente, json=corto).status_code == 422