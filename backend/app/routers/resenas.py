"""
Reseñas y calificaciones — Sprint 5, historia #28.

  POST /resenas                     el cliente califica un pedido entregado
  GET  /resenas/mias                los pedidos que ya califiqué (para el botón "Calificar")
  GET  /resenas/restaurante/{id}    promedio y últimas reseñas de un restaurante
"""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import EstadoPedido, Pedido
from app.models.resena import Resena
from app.models.restaurante import Restaurante
from app.models.usuario import RolUsuario, Usuario
from app.routers.auth import requerir_rol
from app.schemas.resenas_schemas import (
    ResenaCrear,
    ResenaOut,
    ResenaPublica,
    ResenasRestaurante,
)

router = APIRouter(prefix="/resenas", tags=["Reseñas"])


def _a_out(r: Resena) -> dict:
    return {
        "pedido_id": r.pedido_id,
        "calificacion_restaurante": r.calificacion_restaurante,
        "calificacion_repartidor": r.calificacion_repartidor,
        "comentario": r.comentario,
    }


@router.post("", response_model=ResenaOut, status_code=status.HTTP_201_CREATED)
def crear_resena(
    datos: ResenaCrear,
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    pedido = db.query(Pedido).filter(Pedido.id == datos.pedido_id).first()
    if pedido is None or pedido.cliente_id != cliente.id:
        raise HTTPException(status_code=404, detail="Pedido no encontrado.")
    if pedido.estado != EstadoPedido.entregado:
        raise HTTPException(
            status_code=400, detail="Solo puedes calificar pedidos ya entregados."
        )
    if db.query(Resena).filter(Resena.pedido_id == pedido.id).first() is not None:
        raise HTTPException(status_code=409, detail="Ya calificaste este pedido.")

    resena = Resena(
        pedido_id=pedido.id,
        cliente_id=cliente.id,
        restaurante_id=pedido.restaurante_id,
        repartidor_id=pedido.repartidor_id,
        calificacion_restaurante=datos.calificacion_restaurante,
        # Sin repartidor asignado no hay a quién calificar.
        calificacion_repartidor=(
            datos.calificacion_repartidor if pedido.repartidor_id else None
        ),
        comentario=datos.comentario,
    )
    db.add(resena)
    db.commit()
    db.refresh(resena)
    return _a_out(resena)


@router.get("/mias", response_model=list[ResenaOut])
def mis_resenas(
    db: Session = Depends(get_db),
    cliente: Usuario = Depends(requerir_rol(RolUsuario.cliente)),
):
    filas = db.query(Resena).filter(Resena.cliente_id == cliente.id).all()
    return [_a_out(r) for r in filas]


@router.get("/restaurante/{restaurante_id}", response_model=ResenasRestaurante)
def resenas_de_restaurante(
    restaurante_id: int,
    limite: int = 20,
    db: Session = Depends(get_db),
):
    if db.query(Restaurante.id).filter(Restaurante.id == restaurante_id).first() is None:
        raise HTTPException(status_code=404, detail="Restaurante no encontrado.")

    promedio, total = (
        db.query(func.avg(Resena.calificacion_restaurante), func.count(Resena.id))
        .filter(Resena.restaurante_id == restaurante_id)
        .one()
    )
    filas = (
        db.query(Resena, Usuario.nombre)
        .join(Usuario, Usuario.id == Resena.cliente_id)
        .filter(Resena.restaurante_id == restaurante_id)
        .order_by(Resena.id.desc())
        .limit(max(1, min(limite, 50)))
        .all()
    )
    ahora = datetime.utcnow()
    return {
        "promedio": round(float(promedio), 1) if promedio is not None else None,
        "total": int(total or 0),
        "resenas": [
            ResenaPublica(
                # Privacidad: solo se muestra el primer nombre.
                autor=(nombre or "Cliente").split()[0],
                calificacion=r.calificacion_restaurante,
                comentario=r.comentario,
                hace_dias=max(0, (ahora - (r.fecha_creacion or ahora)).days),
            )
            for r, nombre in filas
        ],
    }


def promedios_por_restaurante(db: Session) -> dict:
    """{restaurante_id: (promedio, total)} para mostrarlo en las tarjetas."""
    filas = (
        db.query(
            Resena.restaurante_id,
            func.avg(Resena.calificacion_restaurante),
            func.count(Resena.id),
        )
        .group_by(Resena.restaurante_id)
        .all()
    )
    return {rid: (round(float(avg), 1), int(n)) for rid, avg, n in filas}


def promedio_de_repartidor(db: Session, repartidor_id: int):
    """(promedio, total) de las calificaciones que ha recibido un repartidor."""
    avg, n = (
        db.query(func.avg(Resena.calificacion_repartidor), func.count(Resena.calificacion_repartidor))
        .filter(Resena.repartidor_id == repartidor_id)
        .one()
    )
    return (round(float(avg), 1) if avg is not None else None), int(n or 0)
