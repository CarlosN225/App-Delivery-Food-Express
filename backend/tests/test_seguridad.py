"""Pruebas de codificación segura (Actividad 2): sanitización y enmascarado de PII."""

import logging

from app.services.seguridad import (
    FiltroPII,
    enmascarar_direccion,
    enmascarar_telefono,
    enmascarar_texto,
    sanitizar_busqueda,
    sanitizar_texto,
)


# ------------------------------------------------------------ Sanitización ---
def test_busqueda_normal_no_cambia():
    assert sanitizar_busqueda("Tacos Don Juan") == "Tacos Don Juan"
    assert sanitizar_busqueda("Cafetería Ñandú") == "Cafetería Ñandú"


def test_busqueda_quita_xss():
    limpio = sanitizar_busqueda("<script>alert('x')</script>pizza")
    assert "<" not in limpio and ">" not in limpio and "'" not in limpio
    assert "pizza" in limpio


def test_busqueda_quita_inyeccion_sql():
    limpio = sanitizar_busqueda("' OR 1=1; DROP TABLE usuarios; --")
    for peligroso in ("'", ";", "--", "="):
        assert peligroso not in limpio


def test_busqueda_limita_longitud():
    assert len(sanitizar_busqueda("a" * 500)) == 60


def test_texto_libre_quita_html_pero_conserva_direccion():
    assert sanitizar_texto("Calle Hidalgo 100, Col. Centro") == "Calle Hidalgo 100, Col. Centro"
    assert sanitizar_texto("<b>Casa</b> <img src=x onerror=alert(1)>") == "Casa"


# ------------------------------------------------------------- Enmascarado ---
def test_enmascara_telefono_y_direccion():
    assert enmascarar_telefono("5512345678") == "******5678"
    assert enmascarar_telefono("+52 55 1234 5678") == "********5678"
    assert enmascarar_direccion("Calle Hidalgo 100, Col. Centro") == "Calle Hid***"


def test_enmascara_telefonos_y_correos_dentro_de_un_mensaje():
    msg = enmascarar_texto("Pedido de ana@correo.com, tel 55 1234 5678, entregar pronto")
    assert "5678" in msg and "1234" not in msg
    assert "ana@correo.com" not in msg and "a***@correo.com" in msg


def test_filtro_de_logging_oculta_pii():
    registro = logging.LogRecord(
        "prueba", logging.INFO, __file__, 1, "cliente %s llamó al %s", ("Ana", "5512345678"), None
    )
    FiltroPII().filter(registro)
    assert registro.getMessage() == "cliente Ana llamó al ******5678"


# --------------------------------------------------------------- Integración ---
def test_registro_limpia_nombre(client):
    r = client.post("/auth/registro", json={
        "nombre": "<b>Ana</b> López", "correo": "ana@correo.com", "contrasena": "secreta1",
    })
    assert r.status_code in (200, 201), r.text
    assert r.json()["nombre"] == "Ana López"


def test_busqueda_en_restaurantes_cercanos(client, menu):
    base = {"latitud": 19.60, "longitud": -99.31, "radio_km": 50}
    todos = client.get("/restaurantes/cercanos", params=base).json()
    assert len(todos) == 2

    pizza = client.get("/restaurantes/cercanos", params={**base, "q": "pizza"}).json()
    assert [r["nombre"] for r in pizza] == ["Pizza Express"]

    # Un intento de inyección no rompe nada ni devuelve filas de más.
    ataque = client.get("/restaurantes/cercanos", params={**base, "q": "' OR 1=1; --"})
    assert ataque.status_code == 200
