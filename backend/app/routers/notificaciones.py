"""
Notificaciones — Sprint 4, historia #15.

  GET  /notificaciones                  mis notificaciones (más nuevas primero;
                                        ?desde_id=N trae solo las posteriores a N)
  GET  /notificaciones/no-leidas        cuántas no he leído (para el globito)
  PUT  /notificaciones/leidas           marca todas como leídas
  PUT  /notificaciones/{id}/leida       marca una como leída
  POST /notificaciones/token            registra el token de Firebase del celular
"""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.notificacion import Notificacion, TokenDispositivo
from app.models.usuario import Usuario
from app.routers.auth import obtener_usuario_actual
from app.schemas.notificacion import ConteoOut, NotificacionOut, TokenIn

router = APIRouter(prefix="/notificaciones", tags=["Notificaciones"])


def _a_dict(n: Notificacion) -> dict:
    creada = n.fecha_creacion or datetime.utcnow()
    return {
        "id": n.id,
        "pedido_id": n.pedido_id,
        "titulo": n.titulo,
        "mensaje": n.mensaje,
        "leida": bool(n.leida),
        "hace_segundos": max(0, int((datetime.utcnow() - creada).total_seconds())),
    }


@router.get("", response_model=list[NotificacionOut])
def listar_notificaciones(
    desde_id: int = Query(0, ge=0, description="Solo las que tengan id mayor a este"),
    limite: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    filas = (
        db.query(Notificacion)
        .filter(Notificacion.usuario_id == usuario.id, Notificacion.id > desde_id)
        .order_by(Notificacion.id.desc())
        .limit(limite)
        .all()
    )
    return [_a_dict(n) for n in filas]


@router.get("/no-leidas", response_model=ConteoOut)
def contar_no_leidas(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    total = (
        db.query(Notificacion)
        .filter(Notificacion.usuario_id == usuario.id, Notificacion.leida.is_(False))
        .count()
    )
    return {"no_leidas": total}


@router.put("/leidas")
def marcar_todas_leidas(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    db.query(Notificacion).filter(
        Notificacion.usuario_id == usuario.id, Notificacion.leida.is_(False)
    ).update({Notificacion.leida: True}, synchronize_session=False)
    db.commit()
    return {"ok": True}


@router.put("/{notificacion_id}/leida")
def marcar_leida(
    notificacion_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    notificacion = (
        db.query(Notificacion)
        .filter(
            Notificacion.id == notificacion_id, Notificacion.usuario_id == usuario.id
        )
        .first()
    )
    if notificacion is None:
        raise HTTPException(status_code=404, detail="Notificación no encontrada.")
    notificacion.leida = True
    db.commit()
    return {"ok": True}


@router.post("/token")
def registrar_token(
    datos: TokenIn,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(obtener_usuario_actual),
):
    """Guarda el token del celular. Si ya existía, pasa a ser de este usuario."""
    existente = (
        db.query(TokenDispositivo).filter(TokenDispositivo.token == datos.token).first()
    )
    if existente:
        existente.usuario_id = usuario.id
        existente.plataforma = datos.plataforma
    else:
        db.add(
            TokenDispositivo(
                usuario_id=usuario.id, token=datos.token, plataforma=datos.plataforma
            )
        )
    db.commit()
    return {"ok": True}