"""Sprint 4, historias #16 y #17: panel administrativo."""

from app.models.usuario import RolUsuario, Usuario
from app.services.security import hash_contrasena

ENTREGA = {"latitud_entrega": 19.6100, "longitud_entrega": -99.3000}


def _admin(client, db):
    """El registro público no crea administradores: se inserta directo en la base."""
    db.add(Usuario(
        nombre="Admin", correo="admin@correo.com",
        contrasena_hash=hash_contrasena("secreto1"), rol=RolUsuario.administrador,
    ))
    db.commit()
    r = client.post("/auth/login", data={"username": "admin@correo.com", "password": "secreto1"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_registro_publico_no_crea_administradores(client):
    r = client.post("/auth/registro", json={
        "nombre": "Mala", "correo": "mala@correo.com",
        "contrasena": "secreto1", "rol": "administrador"})
    assert r.status_code == 403
    r = client.post("/auth/registro", json={
        "nombre": "Buena", "correo": "buena@correo.com",
        "contrasena": "secreto1", "rol": "cliente"})
    assert r.status_code == 201


def test_solo_el_administrador_entra_al_panel(client, cliente, repartidor):
    for headers in (cliente, repartidor):
        assert client.get("/admin/restaurantes", headers=headers).status_code == 403
        assert client.get("/admin/usuarios", headers=headers).status_code == 403
    assert client.get("/admin/restaurantes").status_code == 401


def test_crud_de_restaurantes(client, db):
    admin = _admin(client, db)

    r = client.post("/admin/restaurantes", headers=admin, json={
        "nombre": "Pizza Palace", "direccion": "Av. Reforma 123",
        "categoria": "Pizzas", "latitud": 19.6010, "longitud": -99.3085})
    assert r.status_code == 201, r.text
    rid = r.json()["id"]
    assert r.json()["latitud"] == 19.6010

    lista = client.get("/admin/restaurantes", headers=admin).json()
    assert [x["nombre"] for x in lista] == ["Pizza Palace"]

    # El restaurante nuevo ya aparece en la búsqueda pública de los clientes.
    cercanos = client.get("/restaurantes/cercanos", params={
        "latitud": 19.60, "longitud": -99.30, "radio_km": 5}).json()
    assert rid in [x["id"] for x in cercanos]

    r = client.put(f"/admin/restaurantes/{rid}", headers=admin, json={
        "nombre": "Pizza Palace Centro", "direccion": "Av. Reforma 456",
        "categoria": "Pizzas", "latitud": 19.6020, "longitud": -99.3090})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Pizza Palace Centro"

    # Validaciones: coordenadas incompletas, fuera de rango y nombre vacío.
    base = {"nombre": "Otro", "direccion": "X"}
    assert client.post("/admin/restaurantes", headers=admin,
                       json={**base, "latitud": 19.6}).status_code == 422
    assert client.post("/admin/restaurantes", headers=admin,
                       json={**base, "latitud": 123, "longitud": 0}).status_code == 422
    assert client.post("/admin/restaurantes", headers=admin,
                       json={"nombre": ""}).status_code == 422

    assert client.delete(f"/admin/restaurantes/{rid}", headers=admin).status_code == 204
    assert client.put(f"/admin/restaurantes/{rid}", headers=admin,
                      json={"nombre": "Fantasma"}).status_code == 404
    assert client.delete(f"/admin/restaurantes/{rid}", headers=admin).status_code == 404


def test_no_se_elimina_un_restaurante_con_pedidos(client, db, menu, cliente):
    admin = _admin(client, db)
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    assert r.status_code == 201, r.text
    r = client.delete(f"/admin/restaurantes/{menu['pizza']}", headers=admin)
    assert r.status_code == 409
    assert "pedidos" in r.json()["detail"]


def test_gestion_de_usuarios_y_repartidores(client, db, menu, cliente, repartidor):
    admin = _admin(client, db)

    todos = client.get("/admin/usuarios", headers=admin).json()
    assert {u["correo"] for u in todos} == {
        "admin@correo.com", "ana@correo.com", "beto@correo.com"}
    assert all(u["activo"] for u in todos)

    reps = client.get("/admin/usuarios", headers=admin, params={"rol": "repartidor"}).json()
    assert [u["nombre"] for u in reps] == ["Beto"]
    busqueda = client.get("/admin/usuarios", headers=admin, params={"q": "ana"}).json()
    assert [u["nombre"] for u in busqueda] == ["Ana"]

    ana = busqueda[0]
    # Desactivar: ya no puede iniciar sesión y su sesión actual deja de servir.
    r = client.put(f"/admin/usuarios/{ana['id']}/activo", headers=admin, json={"activo": False})
    assert r.status_code == 200 and r.json()["activo"] is False
    login = client.post("/auth/login", data={"username": "ana@correo.com", "password": "secreto1"})
    assert login.status_code == 403
    assert client.get("/auth/me", headers=cliente).status_code == 401

    # Reactivar: vuelve a entrar.
    client.put(f"/admin/usuarios/{ana['id']}/activo", headers=admin, json={"activo": True})
    login = client.post("/auth/login", data={"username": "ana@correo.com", "password": "secreto1"})
    assert login.status_code == 200

    # El administrador no puede desactivarse ni cambiarse el rol a sí mismo.
    yo = client.get("/auth/me", headers=admin).json()
    assert client.put(f"/admin/usuarios/{yo['id']}/activo", headers=admin,
                      json={"activo": False}).status_code == 400
    assert client.put(f"/admin/usuarios/{yo['id']}/rol", headers=admin,
                      json={"rol": "cliente"}).status_code == 400

    # Cambiar el rol de un cliente a repartidor.
    r = client.put(f"/admin/usuarios/{ana['id']}/rol", headers=admin, json={"rol": "repartidor"})
    assert r.status_code == 200 and r.json()["rol"] == "repartidor"

    assert client.put("/admin/usuarios/9999/activo", headers=admin,
                      json={"activo": False}).status_code == 404
    assert client.put(f"/admin/usuarios/{ana['id']}/rol", headers=admin,
                      json={"rol": "jefe"}).status_code == 422


def test_no_se_cambia_el_rol_de_un_repartidor_con_pedido_en_curso(
        client, db, menu, cliente, repartidor):
    admin = _admin(client, db)
    r = client.post("/pedidos", headers=cliente, json={
        "restaurante_id": menu["pizza"],
        "items": [{"producto_id": menu["pepperoni"], "cantidad": 1}],
        "direccion_entrega": "Av. Reforma 123",
        "metodo_pago": "efectivo",
        **ENTREGA,
    })
    pid = r.json()["id"]
    assert client.put(f"/pedidos/{pid}/aceptar", headers=repartidor).status_code == 200

    beto = client.get("/admin/usuarios", headers=admin, params={"q": "beto"}).json()[0]
    r = client.put(f"/admin/usuarios/{beto['id']}/rol", headers=admin, json={"rol": "cliente"})
    assert r.status_code == 409