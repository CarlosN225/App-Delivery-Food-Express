"""
Integración con Mercado Pago (Checkout Pro) usando solo la API REST, sin
dependencias extra.

Dos modos:
  - Real: si MERCADO_PAGO_ACCESS_TOKEN está en el .env se crean preferencias de
    pago reales y se consulta el estado de los pagos en Mercado Pago.
  - Demo: si el token está vacío, el backend sirve una página de pago simulada
    (ver routers/pagos.py) para poder probar el flujo completo sin credenciales.
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request

from dotenv import load_dotenv
from fastapi import HTTPException

load_dotenv()

API_URL = "https://api.mercadopago.com"
MONEDA = "MXN"


def access_token() -> str:
    # Se lee en cada llamada para que un cambio en el .env + reinicio lo tome.
    return os.getenv("MERCADO_PAGO_ACCESS_TOKEN", "").strip()


def modo_demo() -> bool:
    return access_token() == ""


def _solicitud(metodo: str, ruta: str, cuerpo: dict | None = None) -> dict:
    datos = json.dumps(cuerpo).encode("utf-8") if cuerpo is not None else None
    req = urllib.request.Request(
        f"{API_URL}{ruta}",
        data=datos,
        method=metodo,
        headers={
            "Authorization": f"Bearer {access_token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Mercado Pago respondió con error {e.code}.",
        )
    except (urllib.error.URLError, TimeoutError):
        raise HTTPException(
            status_code=502,
            detail="No se pudo contactar a Mercado Pago. Intenta de nuevo.",
        )


def crear_preferencia(pedido, base_url: str) -> dict:
    """Crea la preferencia de pago de un pedido. Devuelve {id, init_point}."""
    items = [
        {
            "id": str(i.producto_id or i.id),
            "title": i.nombre,
            "quantity": int(i.cantidad),
            "unit_price": float(i.precio_unitario),
            "currency_id": MONEDA,
        }
        for i in pedido.items
    ]
    if pedido.costo_envio and float(pedido.costo_envio) > 0:
        items.append(
            {
                "id": "envio",
                "title": "Costo de envío",
                "quantity": 1,
                "unit_price": float(pedido.costo_envio),
                "currency_id": MONEDA,
            }
        )

    base = base_url.rstrip("/")
    cuerpo = {
        "items": items,
        "external_reference": str(pedido.id),
        "statement_descriptor": "FOOD EXPRESS",
        "back_urls": {
            "success": f"{base}/pagos/retorno",
            "failure": f"{base}/pagos/retorno",
            "pending": f"{base}/pagos/retorno",
        },
    }
    # Mercado Pago solo acepta auto_return y notificaciones con URLs https públicas.
    if base.startswith("https://"):
        cuerpo["auto_return"] = "approved"
        cuerpo["notification_url"] = f"{base}/pagos/webhook"

    respuesta = _solicitud("POST", "/checkout/preferences", cuerpo)
    return {"id": respuesta["id"], "init_point": respuesta["init_point"]}


def obtener_pago(payment_id: str) -> dict:
    """Consulta un pago en Mercado Pago (la fuente de verdad del estado)."""
    return _solicitud("GET", f"/v1/payments/{urllib.parse.quote(str(payment_id))}")


def buscar_pago_por_pedido(pedido_id: int) -> dict | None:
    """
    Busca el pago más relevante de un pedido por su external_reference:
    uno aprobado si existe; si no, el más reciente.
    """
    consulta = urllib.parse.urlencode(
        {
            "external_reference": str(pedido_id),
            "sort": "date_created",
            "criteria": "desc",
        }
    )
    resultado = _solicitud("GET", f"/v1/payments/search?{consulta}")
    pagos = resultado.get("results", [])
    if not pagos:
        return None
    for pago in pagos:
        if pago.get("status") == "approved":
            return pago
    return pagos[0]
