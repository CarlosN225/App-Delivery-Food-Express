"""
Pedidos — Sprint 3.

  #9  Carrito de compras y generación del pedido: POST /pedidos (+ /cotizar).
  #11 Cálculo de ruta óptima básica para el repartidor: /pedidos/ruta-optima
      y /pedidos/{id}/ruta (lógica en services/logistica.py).
  #12 Actualización de estado de entrega: PUT /pedidos/{id}/estado
      (aceptado -> recogido -> en_camino -> entregado).

Los precios y el total los calcula siempre el backend a partir de la base de
datos; la app solo manda qué productos y cuántos.
"""

from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import (
    EstadoPago,
    EstadoPedido,
    ItemPedido,
    MetodoPago,
    Pedido,
    PedidoRechazado,
)
from app.models.producto import Producto
from app.models.restaurante import Restaurante
from app.models.usuario import RolUsuario, Usuario
from app.routers.auth import obtener_usuario_actual, requerir_rol
from app.schemas.pedido import (
    CambioEstado,
    CotizacionIn,
    CotizacionOut,
    PedidoCrear,
    PedidoDisponibleOut,
    PedidoOut,
)
from app.services import logistica

router = APIRouter(prefix="/pedidos", tags=["Pedidos"])

CENTAVO = Decimal("0.01")

# Estados en los que un pedido ya tiene repartidor y sigue en curso.
ESTADOS_ACTIVOS = (EstadoPedido.aceptado, EstadoPedido.recogido, EstadoPedido.en_camino)

# Transiciones permitidas para el repartidor (historia #12).
TRANSICIONES = {
    EstadoPedido.aceptado: EstadoPedido.recogido,
    EstadoPedido.recogido: EstadoPedido.en_camino,
    EstadoPedido.en_camino: EstadoPedido.entregado,
}

# Un pedido solo aparece para los repartidores cuando está listo para cobrarse:
# efectivo (se cobra al entregar) o Mercado Pago ya pagado.
PAGOS_LISTOS = (EstadoPago.pagado, EstadoPago.contra_entrega)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

def _dinero(valor) -> Decimal:
    return Decimal(str(valor)).quantize(CENTAVO, rounding=ROUND_HALF_UP)


def _coord_restaurante(r: Restaurante) -> Optional[logistica.Coordenada]:
    lat, lon = logistica.a_float(r.latitud), logistica.a_float(r.longitud)
    if lat is None or lon is None:
        return None
    return (lat, lon)


def _coord_entrega(p: Pedido) -> Optional[logistica.Coordenada]:
    if p.latitud_entrega is None or p.longitud_entrega is None:
        return None
    return (float(p.latitud_entrega), float(p.longitud_entrega))


def _pedido_a_dict(p: Pedido) -> dict:
    r = p.restaurante
    rc = _coord_restaurante(r)
    return {
        "id": p.id,
        "cliente_id": p.cliente_id,
        "repartidor_id": p.repartidor_id,
        "restaurante_id": p.restaurante_id,
        "restaurante": r.nombre,
        "restaurante_direccion": r.direccion,
        "restaurante_latitud": rc[0] if rc else None,
        "restaurante_longitud": rc[1] if rc else None,
        "estado": p.estado,
        "estado_pago": p.estado_pago,
        "metodo_pago": p.metodo_pago,
        "subtotal": float(p.subtotal or 0),
        "costo_envio": float(p.costo_envio or 0),
        "total": float(p.total or 0),
        "direccion_entrega": p.direccion_entrega,
        "latitud_entrega": p.latitud_entrega,
        "longitud_entrega": p.longitud_entrega,
        "items": [
            {
                "producto_id": i.producto_id,
                "nombre": i.nombre,
                "cantidad": i.cantidad,
                "precio_unitario": float(i.precio_unitario),
                "importe": float(i.importe),
            }
            for i in p.items
        ],
        "fecha_creacion": p.fecha_creacion,
    }


def _cotizar(db: Session, datos: CotizacionIn):
    """
    Valida el carrito contra la base de datos y calcula los montos.
    Devuelve (restaurante, [(producto, cantidad)], subtotal, envio, distancia_km).
    """
    restaurante = (
        db.query(Restaurante).filter(Restaurante.id == datos.restaurante_id).first()
    )
    if restaurante is None:
        raise HTTPException(status_code=404, detail="Restaurante no encontrado.")

    # Si la app manda el mismo producto en dos líneas, se suman.
    cantidades: dict[int, int] = {}
    for item in datos.items:
        cantidades[item.producto_id] = cantidades.get(item.producto_id, 0) + item.cantidad
    if any(c > 50 for c in cantidades.values()):
        raise HTTPException(
            status_code=400, detail="Máximo 50 piezas por producto en un pedido."
        )

    productos = (
        db.query(Producto)
        .filter(
            Producto.id.in_(list(cantidades)),
            Producto.restaurante_id == restaurante.id,
        )
        .all()
    )
    if len(productos) != len(cantidades):
        raise HTTPException(
            status_code=400,
            detail="Alguno de los productos no existe o no pertenece a este restaurante.",
        )

    lineas = [(p, cantidades[p.id]) for p in productos]
    subtotal = sum((_dinero(p.precio) * c for p, c in lineas), Decimal("0.00"))

    rc = _coord_restaurante(restaurante)
    distancia = (
        logistica.haversine_km(
            rc[0], rc[1], datos.latitud_entrega, datos.longitud_entrega
        )
        if rc
        else None
    )
    envio = _dinero(logistica.calcular_envio(distancia))
    return restaurante, lineas, _dinero(subtotal), envio, distancia


def _obtener_pedido(db: Session, pedido_id: int) -> Pedido:
    pedido = db.query(Pedido).filter(Pedido.id == pedido_id).first()
    if pedido is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")
    return pedido


def _pedido_del_repartidor(db: Session, pedido_id: int, repartidor: Usuario) -> Pedido:
    pedido = _obtener_pedido(db, pedido_id)
    if pedido.repartidor_id != repartidor.id:
        raise HTTPException(
            status_code=403, detail="Este pedido no está asignado a ti."
        )
    return pedido


# --------------------------------------------------------------------------
# Cliente: carrito y pedido (#9)
# --------------------------------------------------------------------------

@router.post("/cotizar", response_model=CotizacionOut)
def cotizar_pedido(
    datos: CotizacionIn,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    """Subtotal, costo de envío y total del carrito, sin crear el pedido."""
    _, _, subtotal, envio, distancia = _cotizar(db, datos)
    return {
        "subtotal": float(subtotal),
        "costo_envio": float(envio),
        "total": float(subtotal + envio),
        "distancia_km": round(distancia, 2) if distancia is not None else None,
    }


@router.post("", response_model=PedidoOut, status_code=201)
def crear_pedido(
    datos: PedidoCrear,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    """
    Genera el pedido a partir del carrito. En efectivo queda listo para los
    repartidores; con Mercado Pago queda pendiente hasta que se confirme el pago
    (ver /pagos).
    """
    restaurante, lineas, subtotal, envio, _ = _cotizar(db, datos)

    efectivo = datos.metodo_pago == MetodoPago.efectivo
    pedido = Pedido(
        cliente_id=cliente.id,
        restaurante_id=restaurante.id,
        estado=EstadoPedido.pendiente,
        subtotal=subtotal,
        costo_envio=envio,
        total=subtotal + envio,
        direccion_entrega=datos.direccion_entrega.strip(),
        latitud_entrega=datos.latitud_entrega,
        longitud_entrega=datos.longitud_entrega,
        metodo_pago=datos.metodo_pago,
        estado_pago=EstadoPago.contra_entrega if efectivo else EstadoPago.pendiente,
    )
    pedido.items = [
        ItemPedido(
            producto_id=p.id,
            nombre=p.nombre,
            cantidad=c,
            precio_unitario=_dinero(p.precio),
        )
        for p, c in lineas
    ]
    db.add(pedido)
    db.commit()
    db.refresh(pedido)
    return _pedido_a_dict(pedido)


@router.get("/mis-pedidos", response_model=list[PedidoOut])
def mis_pedidos(
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    pedidos = (
        db.query(Pedido)
        .filter(Pedido.cliente_id == cliente.id)
        .order_by(Pedido.id.desc())
        .all()
    )
    return [_pedido_a_dict(p) for p in pedidos]


@router.post("/{pedido_id}/cancelar", response_model=PedidoOut)
def cancelar_pedido(
    pedido_id: int,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    pedido = _obtener_pedido(db, pedido_id)
    if pedido.cliente_id != cliente.id:
        raise HTTPException(status_code=403, detail="No tienes acceso a este pedido.")
    if pedido.estado != EstadoPedido.pendiente:
        raise HTTPException(
            status_code=400,
            detail="El pedido ya fue tomado por un repartidor y no se puede cancelar.",
        )
    if pedido.estado_pago == EstadoPago.pagado:
        raise HTTPException(
            status_code=400,
            detail="El pedido ya está pagado; no se puede cancelar desde la app.",
        )
    pedido.estado = EstadoPedido.cancelado
    db.commit()
    db.refresh(pedido)
    return _pedido_a_dict(pedido)


# --------------------------------------------------------------------------
# Repartidor: pedidos disponibles, aceptar/rechazar
# --------------------------------------------------------------------------

@router.get("/disponibles", response_model=list[PedidoDisponibleOut])
def pedidos_disponibles(
    latitud: Optional[float] = Query(None, ge=-90, le=90),
    longitud: Optional[float] = Query(None, ge=-180, le=180),
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """
    Pedidos que esperan repartidor (ya pagados o en efectivo), sin los que este
    repartidor rechazó. Si manda su ubicación, se calcula la distancia al restaurante.
    """
    rechazados = select(PedidoRechazado.pedido_id).where(
        PedidoRechazado.repartidor_id == repartidor.id
    )
    pedidos = (
        db.query(Pedido)
        .filter(
            Pedido.estado == EstadoPedido.pendiente,
            Pedido.repartidor_id.is_(None),
            # estado_pago NULL = pedidos creados antes del Sprint 3.
            or_(Pedido.estado_pago.in_(PAGOS_LISTOS), Pedido.estado_pago.is_(None)),
            ~Pedido.id.in_(rechazados),
        )
        .order_by(Pedido.fecha_creacion, Pedido.id)
        .all()
    )

    posicion = (latitud, longitud) if latitud is not None and longitud is not None else None
    resultado = []
    for p in pedidos:
        rc = _coord_restaurante(p.restaurante)
        ec = _coord_entrega(p)
        dist_rest = (
            round(logistica.haversine_km(*posicion, *rc), 2) if posicion and rc else None
        )
        dist_entrega = round(logistica.haversine_km(*rc, *ec), 2) if rc and ec else None
        minutos = None
        if dist_rest is not None or dist_entrega is not None:
            minutos = logistica.minutos_estimados(
                (dist_rest or 0.0) + (dist_entrega or 0.0)
            )
        resultado.append(
            {
                "id": p.id,
                "restaurante_id": p.restaurante_id,
                "restaurante": p.restaurante.nombre,
                "restaurante_direccion": p.restaurante.direccion,
                "direccion_entrega": p.direccion_entrega,
                "metodo_pago": p.metodo_pago,
                "estado_pago": p.estado_pago,
                "total": float(p.total or 0),
                "distancia_km": dist_rest,
                "distancia_entrega_km": dist_entrega,
                "minutos_estimados": minutos,
                "fecha_creacion": p.fecha_creacion,
            }
        )
    return resultado


@router.get("/activos", response_model=list[PedidoOut])
def pedidos_activos(
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """Pedidos que el repartidor ya aceptó y todavía no entrega."""
    pedidos = (
        db.query(Pedido)
        .filter(
            Pedido.repartidor_id == repartidor.id,
            Pedido.estado.in_(ESTADOS_ACTIVOS),
        )
        .order_by(Pedido.id)
        .all()
    )
    return [_pedido_a_dict(p) for p in pedidos]


@router.put("/{pedido_id}/aceptar")
def aceptar_pedido(
    pedido_id: int,
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    pedido = _obtener_pedido(db, pedido_id)

    if pedido.estado != EstadoPedido.pendiente or pedido.repartidor_id is not None:
        raise HTTPException(status_code=400, detail="Este pedido ya no está disponible.")
    if pedido.estado_pago not in PAGOS_LISTOS and pedido.estado_pago is not None:
        raise HTTPException(
            status_code=400, detail="Este pedido todavía no está pagado."
        )

    # UPDATE condicionado: si dos repartidores aceptan a la vez, solo uno gana.
    filas = (
        db.query(Pedido)
        .filter(
            Pedido.id == pedido_id,
            Pedido.estado == EstadoPedido.pendiente,
            Pedido.repartidor_id.is_(None),
        )
        .update(
            {Pedido.estado: EstadoPedido.aceptado, Pedido.repartidor_id: repartidor.id},
            synchronize_session=False,
        )
    )
    db.commit()
    if filas == 0:
        raise HTTPException(status_code=400, detail="Este pedido ya no está disponible.")

    db.refresh(pedido)
    return {
        "mensaje": "Pedido aceptado correctamente.",
        "pedido_id": pedido.id,
        "estado": pedido.estado.value,
        "repartidor_id": pedido.repartidor_id,
    }


@router.put("/{pedido_id}/rechazar")
def rechazar_pedido(
    pedido_id: int,
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """El pedido deja de mostrarse a este repartidor; sigue disponible para los demás."""
    pedido = _obtener_pedido(db, pedido_id)
    if pedido.estado != EstadoPedido.pendiente:
        raise HTTPException(status_code=400, detail="Este pedido ya no está disponible.")

    db.add(PedidoRechazado(pedido_id=pedido.id, repartidor_id=repartidor.id))
    try:
        db.commit()
    except IntegrityError:  # ya lo había rechazado antes
        db.rollback()

    return {
        "mensaje": "Pedido rechazado correctamente.",
        "pedido_id": pedido.id,
        "estado": pedido.estado.value,
    }


# --------------------------------------------------------------------------
# Repartidor: estado de entrega (#12)
# --------------------------------------------------------------------------

@router.put("/{pedido_id}/estado", response_model=PedidoOut)
def actualizar_estado(
    pedido_id: int,
    datos: CambioEstado,
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """
    Avanza el pedido un paso: aceptado -> recogido -> en_camino -> entregado.
    Al entregar un pedido en efectivo, el pago queda registrado como cobrado.
    """
    pedido = _pedido_del_repartidor(db, pedido_id, repartidor)

    siguiente = TRANSICIONES.get(pedido.estado)
    if siguiente is None:
        raise HTTPException(
            status_code=400,
            detail=f"El pedido está «{pedido.estado.value}» y ya no admite cambios.",
        )
    if datos.estado != siguiente:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Desde «{pedido.estado.value}» el siguiente paso es "
                f"«{siguiente.value}»."
            ),
        )

    pedido.estado = siguiente
    if (
        siguiente == EstadoPedido.entregado
        and pedido.metodo_pago == MetodoPago.efectivo
        and pedido.estado_pago == EstadoPago.contra_entrega
    ):
        pedido.estado_pago = EstadoPago.pagado

    db.commit()
    db.refresh(pedido)
    return _pedido_a_dict(pedido)


# --------------------------------------------------------------------------
# Repartidor: ruta óptima básica (#11)
# --------------------------------------------------------------------------

def _pedido_ruta(p: Pedido) -> Optional[logistica.PedidoRuta]:
    """Datos para calcular rutas; None si faltan coordenadas necesarias."""
    ec = _coord_entrega(p)
    rc = _coord_restaurante(p.restaurante)
    recogido = p.estado in (EstadoPedido.recogido, EstadoPedido.en_camino)
    if ec is None or (rc is None and not recogido):
        return None
    return logistica.PedidoRuta(
        id=p.id,
        restaurante=p.restaurante.nombre,
        rest_coord=rc or ec,
        cliente_direccion=p.direccion_entrega or "Cliente",
        cliente_coord=ec,
        recogido=recogido,
    )


@router.get("/ruta-optima")
def ruta_optima(
    latitud: Optional[float] = Query(None, ge=-90, le=90),
    longitud: Optional[float] = Query(None, ge=-180, le=180),
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """
    Orden sugerido de paradas para todos los pedidos activos del repartidor
    (vecino más cercano; siempre recoge antes de entregar).
    """
    pedidos = (
        db.query(Pedido)
        .filter(
            Pedido.repartidor_id == repartidor.id,
            Pedido.estado.in_(ESTADOS_ACTIVOS),
        )
        .order_by(Pedido.id)
        .all()
    )

    datos, sin_coordenadas = [], []
    for p in pedidos:
        pr = _pedido_ruta(p)
        (datos if pr else sin_coordenadas).append(pr or p.id)

    posicion = (latitud, longitud) if latitud is not None and longitud is not None else None
    if not datos:
        ruta = {"tramos": [], "distancia_total_km": 0.0, "minutos_total": 0}
    else:
        primero = datos[0]
        inicio = posicion or (
            primero.cliente_coord if primero.recogido else primero.rest_coord
        )
        paradas = logistica.ordenar_paradas(inicio, datos)
        ruta = logistica.construir_tramos(posicion, paradas)

    ruta["sin_coordenadas"] = sin_coordenadas
    return ruta


@router.get("/{pedido_id}", response_model=PedidoOut)
def detalle_pedido(
    pedido_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    pedido = _obtener_pedido(db, pedido_id)
    es_dueno = pedido.cliente_id == usuario.id
    es_repartidor = pedido.repartidor_id == usuario.id
    es_admin = usuario.rol == RolUsuario.administrador
    if not (es_dueno or es_repartidor or es_admin):
        raise HTTPException(status_code=403, detail="No tienes acceso a este pedido.")
    return _pedido_a_dict(pedido)


@router.get("/{pedido_id}/ruta")
def ruta_de_un_pedido(
    pedido_id: int,
    latitud: Optional[float] = Query(None, ge=-90, le=90),
    longitud: Optional[float] = Query(None, ge=-180, le=180),
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """Ruta restante de un pedido: repartidor -> restaurante -> cliente (según su estado)."""
    pedido = _pedido_del_repartidor(db, pedido_id, repartidor)
    pr = _pedido_ruta(pedido)
    if pr is None:
        raise HTTPException(
            status_code=400, detail="Faltan coordenadas para calcular la ruta."
        )
    posicion = (latitud, longitud) if latitud is not None and longitud is not None else None
    ruta = logistica.ruta_de_pedido(pedido.estado.value, posicion, pr)
    ruta["pedido_id"] = pedido.id
    ruta["estado"] = pedido.estado.value
    return ruta
