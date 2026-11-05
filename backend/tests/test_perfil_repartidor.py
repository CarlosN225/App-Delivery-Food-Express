"""Perfil del repartidor: resumen, ganancias e historial de entregas."""

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _entregar(client, menu, cliente, repartidor, metodo="efectivo"):
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": metodo,
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    pedido = r.json()
    pid = pedido["id"]
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    for estado in ("recogido", "en_camino", "entregado"):
        r = client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text
    return pedido


def test_resumen_vacio(client, repartidor):
    r = client.get("/pedidos/repartidor/resumen", headers=repartidor)
    assert r.status_code == 200
    datos = r.json()
    assert datos["hoy"]["entregas"] == 0
    assert datos["hoy"]["ganancias"] == 0
    assert len(datos["dias"]) == 7
    assert datos["historial"] == []
    assert datos["en_entrega"] is False


def test_resumen_con_entregas(client, menu, cliente, repartidor):
    p1 = _entregar(client, menu, cliente, repartidor)
    p2 = _entregar(client, menu, cliente, repartidor)
    r = client.get(
        "/pedidos/repartidor/resumen", headers=repartidor, params={"zona_min": -360}
    )
    assert r.status_code == 200
    datos = r.json()
    envios = p1["costo_envio"] + p2["costo_envio"]
    assert datos["hoy"]["entregas"] == 2
    assert datos["hoy"]["ganancias"] == round(envios, 2)
    assert datos["hoy"]["efectivo"] == round(p1["total"] + p2["total"], 2)
    assert datos["hoy"]["km"] > 0
    assert datos["semana"]["entregas"] == 2
    assert datos["mes"]["entregas"] == 2
    assert datos["dias"][-1]["entregas"] == 2
    assert [h["id"] for h in datos["historial"]] == [p2["id"], p1["id"]]
    assert datos["historial"][0]["restaurante"] == "Pizza Express"


def test_resumen_no_incluye_pedidos_de_otro_repartidor(
    client, menu, cliente, repartidor, repartidor2
):
    _entregar(client, menu, cliente, repartidor)
    r = client.get("/pedidos/repartidor/resumen", headers=repartidor2)
    assert r.json()["hoy"]["entregas"] == 0
    assert r.json()["historial"] == []


def test_resumen_solo_para_repartidores(client, cliente):
    r = client.get("/pedidos/repartidor/resumen", headers=cliente)
    assert r.status_code == 403
    assert client.get("/pedidos/repartidor/resumen").status_code in (401, 403)
