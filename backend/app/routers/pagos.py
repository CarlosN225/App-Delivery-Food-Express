"""
Pagos — Sprint 3, historia #10 (Integración de pasarela de pagos).

Flujo con Mercado Pago (Checkout Pro):
  1. La app crea el pedido y llama POST /pagos/pedido/{id}/preferencia.
  2. El backend crea la preferencia en Mercado Pago y devuelve `init_point`.
  3. La app abre ese enlace; el cliente paga en Mercado Pago.
  4. El backend confirma el pago consultando a Mercado Pago (webhook o
     POST /pagos/pedido/{id}/verificar). Nunca se confía en lo que diga la app.

Sin MERCADO_PAGO_ACCESS_TOKEN el backend funciona en MODO DEMO: `init_point`
apunta a una página de pago simulada con botones "Aprobar" / "Rechazar".
"""

import os
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import Pedido, EstadoPedido, EstadoPago, MetodoPago
from app.models.usuario import Usuario, RolUsuario
from app.routers.auth import requerir_rol
from app.services import mercadopago
from app.services.security import crear_access_token, decodificar_access_token


router = APIRouter(prefix="/pagos", tags=["Pagos"])


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

def _url_base(request: Request) -> str:
    """
    URL pública del backend. Se puede forzar con PUBLIC_BASE_URL (por ejemplo
    una URL https de ngrok para recibir webhooks); si no, se usa la misma con
    la que el cliente llamó al API (así funciona en emulador y en celular real).
    """
    return os.getenv("PUBLIC_BASE_URL", "").strip() or str(request.base_url)


def _pedido_del_cliente(db: Session, pedido_id: int, cliente: Usuario) -> Pedido:
    pedido = db.query(Pedido).filter(Pedido.id == pedido_id).first()
    if pedido is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")
    if pedido.cliente_id != cliente.id:
        raise HTTPException(status_code=403, detail="No tienes acceso a este pedido.")
    return pedido


def _estado_pago_desde_mp(status_mp: Optional[str]) -> EstadoPago:
    if status_mp == "approved":
        return EstadoPago.pagado
    if status_mp in ("rejected", "cancelled", "refunded", "charged_back"):
        return EstadoPago.rechazado
    return EstadoPago.pendiente  # pending, in_process, authorized...


def _aplicar_pago_mp(db: Session, pedido: Pedido, pago: dict) -> Pedido:
    """Actualiza el pedido con un pago de Mercado Pago, validando que sea el correcto."""
    if str(pago.get("external_reference")) != str(pedido.id):
        raise HTTPException(status_code=400, detail="El pago no corresponde a este pedido.")

    nuevo = _estado_pago_desde_mp(pago.get("status"))

    if nuevo == EstadoPago.pagado:
        monto = float(pago.get("transaction_amount") or 0)
        if abs(monto - float(pedido.total or 0)) > 0.01:
            raise HTTPException(
                status_code=400, detail="El monto pagado no coincide con el total del pedido."
            )

    # Un pedido ya pagado nunca regresa a rechazado/pendiente por un pago posterior.
    if pedido.estado_pago != EstadoPago.pagado:
        pedido.estado_pago = nuevo
        if pago.get("id") is not None:
            pedido.mp_payment_id = str(pago["id"])
        db.commit()
        db.refresh(pedido)
    return pedido


def _respuesta_estado(pedido: Pedido) -> dict:
    return {
        "pedido_id": pedido.id,
        "estado_pago": pedido.estado_pago.value if pedido.estado_pago else None,
        "estado": pedido.estado.value,
    }


# --------------------------------------------------------------------------
# Endpoints para la app
# --------------------------------------------------------------------------

@router.post("/pedido/{pedido_id}/preferencia")
def crear_preferencia_pago(
    pedido_id: int,
    request: Request,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    """Crea (o recrea) el enlace de pago de un pedido con método Mercado Pago."""
    pedido = _pedido_del_cliente(db, pedido_id, cliente)

    if pedido.metodo_pago != MetodoPago.mercado_pago:
        raise HTTPException(status_code=400, detail="Este pedido es en efectivo.")
    if pedido.estado != EstadoPedido.pendiente:
        raise HTTPException(status_code=400, detail="Este pedido ya no admite pago.")
    if pedido.estado_pago == EstadoPago.pagado:
        raise HTTPException(status_code=400, detail="Este pedido ya está pagado.")

    base = _url_base(request)

    if mercadopago.modo_demo():
        token = crear_access_token({"sim_pago": pedido.id})
        enlace = f"{base.rstrip('/')}/pagos/simulador/{pedido.id}?t={token}"
        return {"modo": "demo", "preference_id": None, "init_point": enlace}

    preferencia = mercadopago.crear_preferencia(pedido, base)
    pedido.mp_preference_id = preferencia["id"]
    if pedido.estado_pago == EstadoPago.rechazado:
        pedido.estado_pago = EstadoPago.pendiente  # nuevo intento de pago
    db.commit()
    return {
        "modo": "mercadopago",
        "preference_id": preferencia["id"],
        "init_point": preferencia["init_point"],
    }


@router.post("/pedido/{pedido_id}/verificar")
def verificar_pago(
    pedido_id: int,
    payment_id: Optional[str] = None,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    """
    La app llama aquí cuando el cliente regresa de Mercado Pago. El backend
    consulta a Mercado Pago y actualiza el estado del pago.
    """
    pedido = _pedido_del_cliente(db, pedido_id, cliente)

    if mercadopago.modo_demo() or pedido.estado_pago in (
        EstadoPago.pagado,
        EstadoPago.contra_entrega,
    ):
        return _respuesta_estado(pedido)

    pago = (
        mercadopago.obtener_pago(payment_id)
        if payment_id
        else mercadopago.buscar_pago_por_pedido(pedido.id)
    )
    if pago is not None:
        pedido = _aplicar_pago_mp(db, pedido, pago)
    return _respuesta_estado(pedido)


@router.post("/webhook")
async def webhook_mercado_pago(request: Request, db: Session = Depends(get_db)):
    """
    Notificación de Mercado Pago. No se confía en el contenido: solo se toma el
    id del pago y se consulta directamente a Mercado Pago.
    """
    if mercadopago.modo_demo():
        return {"ok": True}

    payment_id = request.query_params.get("data.id") or request.query_params.get("id")
    tipo = request.query_params.get("type") or request.query_params.get("topic")
    if not payment_id:
        try:
            cuerpo = await request.json()
        except Exception:
            cuerpo = {}
        tipo = tipo or cuerpo.get("type")
        payment_id = (cuerpo.get("data") or {}).get("id")

    if payment_id and tipo == "payment":
        pago = mercadopago.obtener_pago(str(payment_id))
        referencia = pago.get("external_reference")
        if referencia and str(referencia).isdigit():
            pedido = db.query(Pedido).filter(Pedido.id == int(referencia)).first()
            if pedido is not None:
                try:
                    _aplicar_pago_mp(db, pedido, pago)
                except HTTPException:
                    pass  # pago inconsistente: se ignora, no se reintenta

    return {"ok": True}


# --------------------------------------------------------------------------
# Páginas de retorno y simulador (modo demo)
# --------------------------------------------------------------------------

def _pagina(titulo: str, cuerpo: str) -> str:
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titulo}</title>
<style>
 body{{font-family:system-ui,sans-serif;background:#E8F8F8;color:#085858;margin:0;
      display:flex;min-height:100vh;align-items:center;justify-content:center}}
 .tarjeta{{background:#fff;border:2px solid #BFE3DE;border-radius:18px;padding:28px;
          max-width:360px;width:90%;text-align:center}}
 h1{{font-size:22px;margin:0 0 8px}} p{{margin:6px 0}}
 button{{width:100%;padding:14px;border:0;border-radius:12px;font-size:16px;
        font-weight:600;margin-top:12px;cursor:pointer}}
 .ok{{background:#0AA89A;color:#fff}} .no{{background:#fff;color:#0AA89A;border:2px solid #0AA89A}}
 .demo{{display:inline-block;background:#68D888;border-radius:8px;padding:2px 10px;font-size:12px}}
</style></head><body><div class="tarjeta">{cuerpo}</div></body></html>"""


@router.get("/retorno", response_class=HTMLResponse, include_in_schema=False)
def retorno_pago():
    return _pagina(
        "Food Express",
        "<h1>Gracias</h1><p>Ya puedes regresar a la app de Food Express.</p>"
        "<p>Ahí tocarás «Ya pagué» para confirmar tu pedido.</p>",
    )


def _validar_token_simulador(pedido_id: int, t: str) -> None:
    if not mercadopago.modo_demo():
        raise HTTPException(status_code=404, detail="No encontrado.")
    payload = decodificar_access_token(t)
    if not payload or payload.get("sim_pago") != pedido_id:
        raise HTTPException(status_code=403, detail="Enlace de pago inválido o vencido.")


@router.get("/simulador/{pedido_id}", response_class=HTMLResponse, include_in_schema=False)
def simulador_pago(pedido_id: int, t: str, db: Session = Depends(get_db)):
    _validar_token_simulador(pedido_id, t)
    pedido = db.query(Pedido).filter(Pedido.id == pedido_id).first()
    if pedido is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")

    return _pagina(
        "Pago simulado",
        f"""<span class="demo">MODO DEMO · sin cobro real</span>
        <h1>Pedido #{pedido.id}</h1>
        <p>Total a pagar</p><h1>${float(pedido.total or 0):.2f} MXN</h1>
        <form method="post" action="/pagos/simulador/{pedido.id}/aprobar?t={t}">
          <button class="ok" type="submit">Aprobar pago</button></form>
        <form method="post" action="/pagos/simulador/{pedido.id}/rechazar?t={t}">
          <button class="no" type="submit">Rechazar pago</button></form>""",
    )


@router.post(
    "/simulador/{pedido_id}/{resultado}",
    response_class=HTMLResponse,
    include_in_schema=False,
)
def resolver_simulador(
    pedido_id: int, resultado: str, t: str, db: Session = Depends(get_db)
):
    _validar_token_simulador(pedido_id, t)
    if resultado not in ("aprobar", "rechazar"):
        raise HTTPException(status_code=404, detail="No encontrado.")

    pedido = db.query(Pedido).filter(Pedido.id == pedido_id).first()
    if pedido is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")

    if pedido.estado_pago != EstadoPago.pagado:
        pedido.estado_pago = (
            EstadoPago.pagado if resultado == "aprobar" else EstadoPago.rechazado
        )
        pedido.mp_payment_id = f"demo-{pedido.id}"
        db.commit()

    if resultado == "aprobar":
        return _pagina(
            "Pago aprobado",
            "<h1>✅ Pago aprobado</h1><p>Regresa a la app de Food Express "
            "y toca «Ya pagué».</p>",
        )
    return _pagina(
        "Pago rechazado",
        "<h1>❌ Pago rechazado</h1><p>Regresa a la app para intentarlo de nuevo.</p>",
    )
