"""Reseñas y calificaciones (Sprint 5, historia #28)."""

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _pedido(client, menu, cliente):
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _entregado(client, menu, cliente, repartidor):
    pid = _pedido(client, menu, cliente)
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    for estado in ("recogido", "en_camino", "entregado"):
        r = client.put(f"/pedidos/{pid}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text
    return pid


def test_no_se_puede_calificar_un_pedido_sin_entregar(client, menu, cliente):
    pid = _pedido(client, menu, cliente)
    r = client.post("/resenas", headers=cliente, json={"pedido_id": pid, "calificacion_restaurante": 5})
    assert r.status_code == 400


def test_calificar_pedido_entregado_y_ver_promedios(client, menu, cliente, repartidor):
    pid = _entregado(client, menu, cliente, repartidor)
    r = client.post("/resenas", headers=cliente, json={
        "pedido_id": pid, "calificacion_restaurante": 4,
        "calificacion_repartidor": 5, "comentario": "<b>Rica</b> pizza",
    })
    assert r.status_code == 201, r.text
    assert r.json()["comentario"] == "Rica pizza"  # se sanitiza

    pub = client.get(f"/resenas/restaurante/{menu['pizza']}").json()
    assert pub["promedio"] == 4.0 and pub["total"] == 1
    assert pub["resenas"][0]["autor"] == "Ana"
    assert pub["resenas"][0]["comentario"] == "Rica pizza"

    cercanos = client.get("/restaurantes/cercanos", params={
        "latitud": 19.60, "longitud": -99.31, "radio_km": 50}).json()
    pizza = next(x for x in cercanos if x["nombre"] == "Pizza Express")
    assert pizza["calificacion_promedio"] == 4.0 and pizza["total_resenas"] == 1
    tacos = next(x for x in cercanos if x["nombre"] == "Tacos Don Juan")
    assert tacos["calificacion_promedio"] is None and tacos["total_resenas"] == 0

    perfil = client.get("/pedidos/repartidor/resumen", headers=repartidor).json()
    assert perfil["calificacion"] == {"promedio": 5.0, "total": 1}

    mias = client.get("/resenas/mias", headers=cliente).json()
    assert [m["pedido_id"] for m in mias] == [pid]


def test_no_se_califica_dos_veces(client, menu, cliente, repartidor):
    pid = _entregado(client, menu, cliente, repartidor)
    datos = {"pedido_id": pid, "calificacion_restaurante": 5}
    assert client.post("/resenas", headers=cliente, json=datos).status_code == 201
    assert client.post("/resenas", headers=cliente, json=datos).status_code == 409


def test_calificacion_fuera_de_rango_y_pedido_ajeno(client, menu, cliente, repartidor):
    pid = _entregado(client, menu, cliente, repartidor)
    r = client.post("/resenas", headers=cliente, json={"pedido_id": pid, "calificacion_restaurante": 6})
    assert r.status_code == 422
    # un repartidor no puede reseñar
    r = client.post("/resenas", headers=repartidor, json={"pedido_id": pid, "calificacion_restaurante": 5})
    assert r.status_code == 403
