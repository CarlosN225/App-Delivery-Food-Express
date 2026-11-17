"""Recuperación de contraseña con Firebase: sincronización tras restablecer."""

from app.routers import auth as auth_router
from app.services import firebase_auth


def _registrar(client, correo="ana@correo.com", contrasena="vieja123"):
    r = client.post("/auth/registro", json={
        "nombre": "Ana López", "correo": correo, "contrasena": contrasena,
    })
    assert r.status_code == 201, r.text


def _login(client, correo, contrasena):
    return client.post("/auth/login", data={"username": correo, "password": contrasena})


def _falso_firebase(monkeypatch, correo, verificado=True):
    monkeypatch.setattr(
        auth_router, "consultar_cuenta",
        lambda token: {"correo": correo, "verificado": verificado},
    )


TOKEN = "t" * 40


def test_sincronizar_cambia_la_contrasena_y_abre_sesion(client, monkeypatch):
    _registrar(client)
    _falso_firebase(monkeypatch, "ana@correo.com")

    r = client.post("/auth/firebase/sincronizar", json={"id_token": TOKEN, "contrasena": "nueva456"})
    assert r.status_code == 200, r.text
    assert r.json()["access_token"]

    assert _login(client, "ana@correo.com", "nueva456").status_code == 200
    assert _login(client, "ana@correo.com", "vieja123").status_code == 401


def test_correo_sin_verificar_no_cambia_nada(client, monkeypatch):
    """Alguien que creó una cuenta de Firebase con el correo de otro no puede apoderarse."""
    _registrar(client)
    _falso_firebase(monkeypatch, "ana@correo.com", verificado=False)

    r = client.post("/auth/firebase/sincronizar", json={"id_token": TOKEN, "contrasena": "hackeada1"})
    assert r.status_code == 401
    assert _login(client, "ana@correo.com", "vieja123").status_code == 200


def test_token_invalido_o_correo_desconocido(client, monkeypatch):
    _registrar(client)
    monkeypatch.setattr(auth_router, "consultar_cuenta", lambda token: None)
    r = client.post("/auth/firebase/sincronizar", json={"id_token": TOKEN, "contrasena": "nueva456"})
    assert r.status_code == 401

    _falso_firebase(monkeypatch, "otro@correo.com")
    r = client.post("/auth/firebase/sincronizar", json={"id_token": TOKEN, "contrasena": "nueva456"})
    assert r.status_code == 401


def test_contrasena_nueva_debe_tener_6_caracteres(client, monkeypatch):
    _registrar(client)
    _falso_firebase(monkeypatch, "ana@correo.com")
    r = client.post("/auth/firebase/sincronizar", json={"id_token": TOKEN, "contrasena": "123"})
    assert r.status_code == 422


def test_sin_clave_de_firebase_no_hay_consulta(monkeypatch):
    monkeypatch.delenv("FIREBASE_API_KEY", raising=False)
    assert firebase_auth.disponible() is False
    assert firebase_auth.consultar_cuenta("x" * 40) is None
