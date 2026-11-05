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

from datetime import datetime, timedelta
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
    SeguimientoOut,
    UbicacionIn,
)
from app.services import google_maps, logistica, notificaciones

router = APIRouter(prefix="/pedidos", tags=["Pedidos"])

CENTAVO = Decimal("0.01")

# Estados en los que un pedido ya tiene repartidor y sigue en curso.
ESTADOS_ACTIVOS = (EstadoPedido.aceptado, EstadoPedido.recogido, EstadoPedido.en_camino)

# Un repartidor atiende un pedido a la vez: primero lo entrega y luego toma otro.
# (Subir este número permite llevar varios a la vez y usar la ruta óptima #11.)
MAX_PEDIDOS_EN_CURSO = 1

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

    # La entrega debe quedar dentro de la zona de servicio. Se valida aquí
    # (y no solo en la app) para no confiar en las coordenadas del cliente.
    lejos = logistica.haversine_km(
        datos.latitud_entrega, datos.longitud_entrega, *google_maps.CENTRO_ZONA
    )
    if lejos > google_maps.RADIO_ZONA_KM:
        raise HTTPException(
            status_code=422,
            detail="La dirección de entrega queda fuera de la zona de servicio (Nicolás Romero).",
        )

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
                "restaurante_latitud": rc[0] if rc else None,
                "restaurante_longitud": rc[1] if rc else None,
                "latitud_entrega": ec[0] if ec else None,
                "longitud_entrega": ec[1] if ec else None,
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

    en_curso = (
        db.query(Pedido)
        .filter(
            Pedido.repartidor_id == repartidor.id,
            Pedido.estado.in_(ESTADOS_ACTIVOS),
        )
        .count()
    )
    if en_curso >= MAX_PEDIDOS_EN_CURSO:
        raise HTTPException(
            status_code=409,
            detail="Ya tienes un pedido en curso. Entrégalo antes de aceptar otro.",
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
    notificaciones.notificar_estado(db, pedido)   # <-- NUEVA
    return {
        "mensaje": "Pedido aceptado correctamente.",
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
    notificaciones.notificar_estado(db, pedido)   # <-- NUEVA
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


def _km_entrega(p: Pedido) -> float:
    """Kilómetros en línea recta restaurante -> cliente (0 si faltan coordenadas)."""
    origen, destino = _coord_restaurante(p.restaurante), _coord_entrega(p)
    if origen is None or destino is None:
        return 0.0
    return logistica.haversine_km(origen[0], origen[1], destino[0], destino[1])


def _totales(pedidos: list) -> dict:
    """Cifras de un periodo: entregas, ganancias (envíos), km y cobros."""
    ganancias = sum((float(p.costo_envio or 0) for p in pedidos), 0.0)
    efectivo = sum(
        (float(p.total or 0) for p in pedidos if p.metodo_pago == MetodoPago.efectivo),
        0.0,
    )
    en_linea = sum(
        (float(p.total or 0) for p in pedidos if p.metodo_pago != MetodoPago.efectivo),
        0.0,
    )
    return {
        "entregas": len(pedidos),
        "ganancias": round(ganancias, 2),
        "km": round(sum(_km_entrega(p) for p in pedidos), 1),
        "efectivo": round(efectivo, 2),
        "mercado_pago": round(en_linea, 2),
    }


@router.get("/repartidor/resumen")
def resumen_repartidor(
    zona_min: int = Query(
        0, ge=-840, le=840,
        description="Diferencia en minutos entre la hora local y UTC (México: -360).",
    ),
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """
    Perfil del repartidor: resumen de hoy / semana / mes, ganancias de los
    últimos 7 días e historial de entregas. La ganancia es el costo de envío de
    cada pedido entregado. Las fechas se agrupan con la hora local del repartidor
    (`zona_min`), porque en la base se guardan en UTC.
    """
    pedidos = (
        db.query(Pedido)
        .filter(
            Pedido.repartidor_id == repartidor.id,
            Pedido.estado == EstadoPedido.entregado,
        )
        .order_by(Pedido.fecha_actualizacion.desc(), Pedido.id.desc())
        .all()
    )

    desfase = timedelta(minutes=zona_min)

    def local(p: Pedido) -> datetime:
        return (p.fecha_actualizacion or p.fecha_creacion or datetime.utcnow()) + desfase

    hoy = (datetime.utcnow() + desfase).date()
    inicio_semana = hoy - timedelta(days=hoy.weekday())  # lunes
    inicio_mes = hoy.replace(day=1)

    de_hoy = [p for p in pedidos if local(p).date() == hoy]
    de_semana = [p for p in pedidos if local(p).date() >= inicio_semana]
    de_mes = [p for p in pedidos if local(p).date() >= inicio_mes]

    dias = []
    for atras in range(6, -1, -1):
        dia = hoy - timedelta(days=atras)
        del_dia = [p for p in pedidos if local(p).date() == dia]
        dias.append({
            "fecha": dia.isoformat(),
            "entregas": len(del_dia),
            "ganancias": round(sum(float(p.costo_envio or 0) for p in del_dia), 2),
        })

    historial = [
        {
            "id": p.id,
            "restaurante": p.restaurante.nombre,
            "direccion_entrega": p.direccion_entrega,
            "fecha": local(p).isoformat(timespec="minutes"),
            "costo_envio": float(p.costo_envio or 0),
            "total": float(p.total or 0),
            "metodo_pago": p.metodo_pago,
            "km": round(_km_entrega(p), 1),
        }
        for p in pedidos[:100]
    ]

    ocupado = (
        db.query(Pedido)
        .filter(
            Pedido.repartidor_id == repartidor.id,
            Pedido.estado.in_(ESTADOS_ACTIVOS),
        )
        .count()
        > 0
    )

    return {
        "nombre": repartidor.nombre,
        "correo": repartidor.correo,
        "en_entrega": ocupado,
        "hoy": _totales(de_hoy),
        "semana": _totales(de_semana),
        "mes": _totales(de_mes),
        "dias": dias,
        "historial": historial,
    }


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



# --------------------------------------------------------------------------
# Seguimiento en tiempo real (#14)
# --------------------------------------------------------------------------

@router.put("/{pedido_id}/ubicacion")
def reportar_ubicacion(
    pedido_id: int,
    datos: UbicacionIn,
    db: Session = Depends(get_db),
    repartidor: Usuario = Depends(requerir_rol(RolUsuario.repartidor)),
):
    """El repartidor manda su posición GPS mientras lleva el pedido."""
    pedido = _pedido_del_repartidor(db, pedido_id, repartidor)
    if pedido.estado not in ESTADOS_ACTIVOS:
        raise HTTPException(
            status_code=400,
            detail="Solo puedes reportar tu ubicación en un pedido en curso.",
        )
    pedido.latitud_repartidor = datos.latitud
    pedido.longitud_repartidor = datos.longitud
    pedido.ubicacion_actualizada = datetime.utcnow()
    db.commit()
    return {"ok": True}


@router.get("/{pedido_id}/seguimiento", response_model=SeguimientoOut)
def seguimiento_pedido(
    pedido_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    """
    Estado, posiciones (restaurante, cliente y repartidor) y tiempo restante
    de un pedido. Solo lo ve el cliente dueño del pedido (o un administrador).
    """
    pedido = _obtener_pedido(db, pedido_id)
    es_dueno = pedido.cliente_id == usuario.id
    es_admin = usuario.rol == RolUsuario.administrador
    if not (es_dueno or es_admin):
        raise HTTPException(status_code=403, detail="No tienes acceso a este pedido.")

    rc = _coord_restaurante(pedido.restaurante)
    ec = _coord_entrega(pedido)
    rep = None
    if pedido.latitud_repartidor is not None and pedido.longitud_repartidor is not None:
        rep = (float(pedido.latitud_repartidor), float(pedido.longitud_repartidor))

    # Distancia que falta: repartidor -> (restaurante, si aún no recoge) -> cliente.
    distancia = minutos = None
    if pedido.estado in ESTADOS_ACTIVOS and ec is not None:
        paradas = [rc, ec] if pedido.estado == EstadoPedido.aceptado and rc else [ec]
        puntos = [rep or rc or ec] + paradas
        distancia = sum(
            logistica.haversine_km(*a, *b) for a, b in zip(puntos, puntos[1:])
        )
        minutos = logistica.minutos_estimados(distancia)

    segundos = None
    if pedido.ubicacion_actualizada is not None:
        segundos = max(
            0, int((datetime.utcnow() - pedido.ubicacion_actualizada).total_seconds())
        )

    return {
        "pedido_id": pedido.id,
        "estado": pedido.estado,
        "restaurante": pedido.restaurante.nombre,
        "repartidor_nombre": pedido.repartidor.nombre if pedido.repartidor else None,
        "restaurante_latitud": rc[0] if rc else None,
        "restaurante_longitud": rc[1] if rc else None,
        "cliente_latitud": ec[0] if ec else None,
        "cliente_longitud": ec[1] if ec else None,
        "repartidor_latitud": rep[0] if rep else None,
        "repartidor_longitud": rep[1] if rep else None,
        "segundos_desde_ubicacion": segundos,
        "distancia_restante_km": round(distancia, 2) if distancia is not None else None,
        "minutos_restantes": minutos,
    }