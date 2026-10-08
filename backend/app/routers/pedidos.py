from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import Pedido, EstadoPedido
from app.models.usuario import Usuario, RolUsuario


router = APIRouter(
    prefix="/pedidos",
    tags=["Pedidos"],
)


@router.get("/disponibles")
def obtener_pedidos_disponibles(
    db: Session = Depends(get_db),
):
    pedidos = (
        db.query(Pedido)
        .filter(Pedido.estado == EstadoPedido.pendiente)
        .all()
    )

    resultado = []

    for pedido in pedidos:
        resultado.append({
            "id": pedido.id,
            "cliente_id": pedido.cliente_id,
            "restaurante_id": pedido.restaurante_id,
            "restaurante": pedido.restaurante.nombre,
            "estado": pedido.estado.value,
            "total": float(pedido.total or 0),
            "fecha_creacion": pedido.fecha_creacion,
        })

    return resultado


@router.put("/{pedido_id}/aceptar")
def aceptar_pedido(
    pedido_id: int,
    repartidor_id: int,
    db: Session = Depends(get_db),
):
    repartidor = (
        db.query(Usuario)
        .filter(Usuario.id == repartidor_id)
        .first()
    )

    if repartidor is None:
        raise HTTPException(
            status_code=404,
            detail="Repartidor no encontrado.",
        )

    if repartidor.rol != RolUsuario.repartidor:
        raise HTTPException(
            status_code=403,
            detail="El usuario no tiene rol de repartidor.",
        )

    pedido = (
        db.query(Pedido)
        .filter(Pedido.id == pedido_id)
        .first()
    )

    if pedido is None:
        raise HTTPException(
            status_code=404,
            detail="Pedido no encontrado.",
        )

    if pedido.estado != EstadoPedido.pendiente:
        raise HTTPException(
            status_code=400,
            detail="Este pedido ya no está disponible.",
        )

    pedido.repartidor_id = repartidor_id
    pedido.estado = EstadoPedido.en_camino

    db.commit()
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
):
    pedido = (
        db.query(Pedido)
        .filter(Pedido.id == pedido_id)
        .first()
    )

    if pedido is None:
        raise HTTPException(
            status_code=404,
            detail="Pedido no encontrado.",
        )

    if pedido.estado != EstadoPedido.pendiente:
        raise HTTPException(
            status_code=400,
            detail="Este pedido ya no está disponible.",
        )

    pedido.estado = EstadoPedido.cancelado

    db.commit()
    db.refresh(pedido)

    return {
        "mensaje": "Pedido rechazado correctamente.",
        "pedido_id": pedido.id,
        "estado": pedido.estado.value,
    }