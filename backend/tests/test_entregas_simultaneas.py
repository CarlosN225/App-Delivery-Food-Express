"""Entregas simultáneas (Sprint 5): hasta 2 pedidos a la vez, con restaurantes cercanos."""

from app.models import Producto, Restaurante

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _pedido(client, cliente, restaurante_id, producto_id):
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": restaurante_id,
        "items": [{"producto_id": producto_id, "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_lleva_dos_pedidos_y_la_ruta_los_ordena(client, menu, cliente, repartidor):
    p1 = _pedido(client, cliente, menu["pizza"], menu["pepperoni"])
    p2 = _pedido(client, cliente, menu["tacos"], menu["taco"])
    assert client.put(f"/pedidos/{p1}/aceptar", headers=repartidor).status_code == 200
    # Segundo pedido: restaurantes a ~1.3 km, se permite.
    assert client.put(f"/pedidos/{p2}/aceptar", headers=repartidor).status_code == 200

    activos = client.get("/pedidos/activos", headers=repartidor).json()
    assert len(activos) == 2

    ruta = client.get("/pedidos/ruta-optima", headers=repartidor).json()
    tipos = [t["tipo"] for t in ruta["tramos"]]
    assert len(tipos) == 4
    # Siempre recoge antes de entregar cada pedido.
    for pid in (p1, p2):
        orden = [t["tipo"] for t in ruta["tramos"] if t["pedido_id"] == pid]
        assert orden == ["recoger", "entregar"]


def test_no_acepta_un_tercer_pedido(client, menu, cliente, repartidor):
    ids = [_pedido(client, cliente, menu["pizza"], menu["pepperoni"]) for _ in range(3)]
    assert client.put(f"/pedidos/{ids[0]}/aceptar", headers=repartidor).status_code == 200
    assert client.put(f"/pedidos/{ids[1]}/aceptar", headers=repartidor).status_code == 200
    r = client.put(f"/pedidos/{ids[2]}/aceptar", headers=repartidor)
    assert r.status_code == 409
    assert "2 pedidos" in r.json()["detail"]


def test_rechaza_segundo_pedido_de_restaurante_lejano(client, db, menu, cliente, repartidor):
    lejos = Restaurante(
        nombre="Lejos", direccion="Otro municipio", categoria="Pizza",
        latitud="19.7000", longitud="-99.2000",
    )
    db.add(lejos)
    db.commit()
    prod = Producto(restaurante_id=lejos.id, nombre="Pizza", precio=100)
    db.add(prod)
    db.commit()

    p1 = _pedido(client, cliente, menu["pizza"], menu["pepperoni"])
    p2 = _pedido(client, cliente, lejos.id, prod.id)
    assert client.put(f"/pedidos/{p1}/aceptar", headers=repartidor).status_code == 200
    r = client.put(f"/pedidos/{p2}/aceptar", headers=repartidor)
    assert r.status_code == 409
    assert "menos de 3 km" in r.json()["detail"]


def test_no_toma_otro_si_ya_va_en_camino(client, menu, cliente, repartidor):
    p1 = _pedido(client, cliente, menu["pizza"], menu["pepperoni"])
    p2 = _pedido(client, cliente, menu["tacos"], menu["taco"])
    assert client.put(f"/pedidos/{p1}/aceptar", headers=repartidor).status_code == 200
    for estado in ("recogido", "en_camino"):
        r = client.put(f"/pedidos/{p1}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text
    r = client.put(f"/pedidos/{p2}/aceptar", headers=repartidor)
    assert r.status_code == 409
    assert "en camino" in r.json()["detail"]


def test_al_entregar_uno_puede_tomar_otro(client, menu, cliente, repartidor):
    ids = [_pedido(client, cliente, menu["pizza"], menu["pepperoni"]) for _ in range(3)]
    for pid in ids[:2]:
        assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200
    for estado in ("recogido", "en_camino", "entregado"):
        r = client.put(f"/pedidos/{ids[0]}/estado", headers=repartidor, json={"estado": estado})
        assert r.status_code == 200, r.text
    assert client.put(f"/pedidos/{ids[2]}/aceptar", headers=repartidor).status_code == 200
