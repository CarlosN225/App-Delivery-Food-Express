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
from html import escape
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import Pedido, EstadoPedido, EstadoPago, MetodoPago
from app.models.usuario import Usuario, RolUsuario
from app.routers.auth import requerir_rol
from app.services import mercadopago
from app.services.logo_pago import LOGO_PAGO, LOGO_PAGO_ALTO, LOGO_PAGO_ANCHO
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

_ESTILO_PAGINA = """
 *{box-sizing:border-box}
 body{font-family:'Poppins',system-ui,sans-serif;background:#F2FAF9;color:#085858;margin:0;
      min-height:100vh;display:flex;flex-direction:column}
 header{background:#fff;border-bottom:1px solid #D3E2DF;height:64px;display:flex;
        align-items:center;justify-content:space-between;padding:0 24px}
 .logo{display:block}
 .seguro{display:flex;align-items:center;gap:8px}
 .rotulo{font-size:10px;font-weight:700;letter-spacing:1.5px;color:#5E8F8B;text-transform:uppercase}
 main{flex:1;display:flex;align-items:center;justify-content:center;padding:24px}
 .tarjeta{background:#fff;border:1px solid #D3E2DF;width:100%;max-width:440px;padding:28px}
 h1{font-size:26px;margin:4px 0 2px;font-weight:700}
 p{margin:0}
 .sub{color:#5E8F8B;font-size:14px}
 .demo{display:inline-block;background:#E5F5F3;color:#085858;padding:5px 10px;margin-bottom:18px}
 hr{border:0;border-top:1px solid #D3E2DF;margin:18px 0}
 .fila{display:flex;justify-content:space-between;font-size:14px;color:#5E8F8B;margin:6px 0}
 .fila span:last-child{color:#085858;font-weight:600}
 .total{display:flex;justify-content:space-between;align-items:flex-end;margin:12px 0 14px}
 .total strong{font-size:32px;line-height:1}
 button{width:100%;height:52px;border:1.5px solid #085858;font:inherit;font-size:11px;font-weight:700;
        letter-spacing:1.5px;cursor:pointer;margin-top:10px;background:#fff;color:#085858;text-transform:uppercase}
 button.ok{background:#085858;color:#fff}
 button.ok:hover{background:#0AA89A;border-color:#0AA89A}
 button.no:hover{background:#E5F5F3}
 .nota{font-size:12px;color:#5E8F8B;margin-top:16px;line-height:1.5}
 .icono{width:64px;height:64px;display:flex;align-items:center;justify-content:center;
        font-size:34px;color:#fff;margin-bottom:16px}
 .icono.si{background:#0AA89A}.icono.no{background:#D1495B}
 .barra{height:3px;background:#D3E2DF;margin-top:20px;overflow:hidden}
 .barra i{display:block;height:100%;background:#0AA89A;width:0;animation:llenar 1.8s linear forwards}
 @keyframes llenar{to{width:100%}}
"""

_FUENTE = (
    '<link rel="preconnect" href="https://fonts.googleapis.com">'
    '<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap" '
    'rel="stylesheet">'
)


def _pagina(titulo: str, cuerpo: str, script: str = "") -> str:
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titulo}</title>{_FUENTE}
<style>{_ESTILO_PAGINA}</style></head><body>
<header><img class="logo" src="{LOGO_PAGO}" alt="Food Express"
 width="{LOGO_PAGO_ANCHO // 2}" height="{LOGO_PAGO_ALTO // 2}">
<span class="seguro"><svg width="18" height="20" viewBox="0 0 24 26" fill="none"
 stroke="#0AA89A" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
 <path d="M12 2 3 5.5v6.8c0 5.4 3.8 10 9 11.7 5.2-1.7 9-6.3 9-11.7V5.5L12 2z"/>
 <path d="m8.2 12.8 2.8 2.8 5-5.4"/></svg>
<span class="rotulo">Pago seguro</span></span></header>
<main><div class="tarjeta">{cuerpo}</div></main>{script}</body></html>"""


# Al terminar, la ventana de pago se cierra sola y la app (que revisa el pago
# cada pocos segundos) continúa. Si el navegador no deja cerrarla, queda un
# botón para hacerlo a mano.
_SCRIPT_CERRAR = """<script>
 try{if(window.opener){window.opener.postMessage({tipo:'pago-food-express'},'*');}}catch(e){}
 setTimeout(function(){window.close();},1800);
 setTimeout(function(){var b=document.getElementById('cerrar');if(b){b.style.display='block';}},2400);
</script>"""

_BOTON_CERRAR = (
    '<button id="cerrar" class="no" type="button" style="display:none" '
    'onclick="window.close()">Cerrar esta ventana</button>'
)


def _resultado(ok: bool) -> str:
    if ok:
        icono, titulo, texto = "si", "Pago aprobado", (
            "Listo, tu pedido ya está en marcha. Esta ventana se cerrará sola "
            "y volverás a Food Express."
        )
        marca = "✓"
    else:
        icono, titulo, texto = "no", "Pago rechazado", (
            "No se hizo ningún cargo. Esta ventana se cerrará sola y podrás "
            "intentarlo de nuevo desde la app."
        )
        marca = "✕"
    return _pagina(
        titulo,
        f"""<div class="icono {icono}">{marca}</div>
        <p class="rotulo">{'Completado' if ok else 'Sin cargo'}</p>
        <h1>{titulo}</h1>
        <p class="sub">{texto}</p>
        <div class="barra"><i></i></div>
        {_BOTON_CERRAR}""",
        _SCRIPT_CERRAR,
    )


@router.get("/retorno", response_class=HTMLResponse, include_in_schema=False)
def retorno_pago():
    return _pagina(
        "Food Express",
        """<div class="icono si">✓</div>
        <p class="rotulo">Pago enviado</p>
        <h1>Gracias</h1>
        <p class="sub">Ya puedes regresar a Food Express. Esta ventana se cerrará
        sola y tu pedido se confirmará en la app.</p>
        <div class="barra"><i></i></div>"""
        + _BOTON_CERRAR,
        _SCRIPT_CERRAR,
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

    restaurante = escape(pedido.restaurante.nombre) if pedido.restaurante else ""
    subtotal = float(pedido.subtotal or 0)
    envio = float(pedido.costo_envio or 0)

    return _pagina(
        "Pago simulado",
        f"""<span class="demo rotulo">Modo demo · sin cobro real</span>
        <p class="rotulo">Pedido #{pedido.id}</p>
        <h1>{restaurante}</h1>
        <p class="sub">Pago con Mercado Pago</p>
        <hr>
        <div class="fila"><span>Subtotal</span><span>${subtotal:.2f}</span></div>
        <div class="fila"><span>Envío</span><span>${envio:.2f}</span></div>
        <div class="total"><span class="rotulo">Total a pagar</span>
          <strong>${float(pedido.total or 0):.2f}</strong></div>
        <form method="post" action="/pagos/simulador/{pedido.id}/aprobar?t={t}" class="f">
          <button class="ok" type="submit">Aprobar pago</button></form>
        <form method="post" action="/pagos/simulador/{pedido.id}/rechazar?t={t}" class="f">
          <button class="no" type="submit">Rechazar pago</button></form>
        <p class="nota">Esto es una simulación de Mercado Pago: no se hace ningún
        cargo. Al elegir una opción, esta ventana se cierra sola y la app continúa.</p>""",
        """<script>
 // Envía la decisión sin recargar la página, para que la ventana pueda cerrarse sola.
 document.querySelectorAll('form.f').forEach(function(f){
   f.addEventListener('submit',function(e){
     e.preventDefault();
     document.querySelectorAll('button').forEach(function(b){b.disabled=true;});
     fetch(f.action,{method:'POST'}).then(function(r){return r.text();}).then(function(h){
       document.open();document.write(h);document.close();
     }).catch(function(){f.submit();});
   });
 });
</script>""",
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

    return _resultado(resultado == "aprobar")
