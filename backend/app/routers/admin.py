"""
Panel administrativo — Sprint 4, historias #16 y #17.
Todo este router es solo para usuarios con rol `administrador`.

Restaurantes (#16):
  GET    /admin/restaurantes                  lista completa
  POST   /admin/restaurantes                  crea uno
  PUT    /admin/restaurantes/{id}             edita
  DELETE /admin/restaurantes/{id}             elimina (si no tiene pedidos)

Usuarios y repartidores (#17):
  GET    /admin/usuarios?rol=&q=              lista, con filtro por rol y búsqueda
  PUT    /admin/usuarios/{id}/activo          activa o desactiva una cuenta
  PUT    /admin/usuarios/{id}/rol             cambia el rol
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.pedido import EstadoPedido, Pedido
from app.models.producto import Producto
from app.models.restaurante import Restaurante
from app.models.usuario import RolUsuario, Usuario
from app.routers.auth import requerir_rol
from app.schemas.admin import (
    ActivoIn,
    RestauranteAdminIn,
    RestauranteAdminOut,
    RolIn,
    UsuarioAdminOut,
)

router = APIRouter(prefix="/admin", tags=["Administración"])

_ADMIN = Depends(requerir_rol(RolUsuario.administrador))


# --------------------------------------------------------------------------
# Restaurantes (#16)
# --------------------------------------------------------------------------

def _a_float(valor) -> Optional[float]:
    try:
        return float(valor) if valor not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _restaurante_a_dict(restaurante: Restaurante, total_productos: int) -> dict:
    return {
        "id": restaurante.id,
        "nombre": restaurante.nombre,
        "direccion": restaurante.direccion,
        "categoria": restaurante.categoria,
        "latitud": _a_float(restaurante.latitud),
        "longitud": _a_float(restaurante.longitud),
        "total_productos": total_productos,
    }


def _restaurante_o_404(db: Session, restaurante_id: int) -> Restaurante:
    restaurante = (
        db.query(Restaurante).filter(Restaurante.id == restaurante_id).first()
    )
    if restaurante is None:
        raise HTTPException(status_code=404, detail="Restaurante no encontrado.")
    return restaurante


def _aplicar_datos(restaurante: Restaurante, datos: RestauranteAdminIn) -> None:
    restaurante.nombre = datos.nombre.strip()
    restaurante.direccion = (datos.direccion or "").strip() or None
    restaurante.categoria = (datos.categoria or "").strip() or None
    # En la base las coordenadas del restaurante se guardan como texto.
    restaurante.latitud = None if datos.latitud is None else str(datos.latitud)
    restaurante.longitud = None if datos.longitud is None else str(datos.longitud)


@router.get("/restaurantes", response_model=list[RestauranteAdminOut])
def listar_restaurantes(db: Session = Depends(get_db), admin: Usuario = _ADMIN):
    conteos = dict(
        db.query(Producto.restaurante_id, func.count(Producto.id))
        .group_by(Producto.restaurante_id)
        .all()
    )
    restaurantes = db.query(Restaurante).order_by(Restaurante.nombre).all()
    return [_restaurante_a_dict(r, conteos.get(r.id, 0)) for r in restaurantes]


@router.post(
    "/restaurantes",
    response_model=RestauranteAdminOut,
    status_code=status.HTTP_201_CREATED,
)
def crear_restaurante(
    datos: RestauranteAdminIn,
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    restaurante = Restaurante()
    _aplicar_datos(restaurante, datos)
    db.add(restaurante)
    db.commit()
    db.refresh(restaurante)
    return _restaurante_a_dict(restaurante, 0)


@router.put("/restaurantes/{restaurante_id}", response_model=RestauranteAdminOut)
def editar_restaurante(
    restaurante_id: int,
    datos: RestauranteAdminIn,
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    restaurante = _restaurante_o_404(db, restaurante_id)
    _aplicar_datos(restaurante, datos)
    db.commit()
    db.refresh(restaurante)
    total = (
        db.query(Producto).filter(Producto.restaurante_id == restaurante.id).count()
    )
    return _restaurante_a_dict(restaurante, total)


@router.delete("/restaurantes/{restaurante_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_restaurante(
    restaurante_id: int,
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    restaurante = _restaurante_o_404(db, restaurante_id)
    if db.query(Pedido).filter(Pedido.restaurante_id == restaurante.id).count() > 0:
        raise HTTPException(
            status_code=409,
            detail="Este restaurante ya tiene pedidos y no se puede eliminar.",
        )
    # Sin pedidos, nada más depende de sus productos: se borran junto con él.
    db.query(Producto).filter(Producto.restaurante_id == restaurante.id).delete(
        synchronize_session=False
    )
    db.delete(restaurante)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --------------------------------------------------------------------------
# Usuarios y repartidores (#17)
# --------------------------------------------------------------------------

def _usuario_o_404(db: Session, usuario_id: int) -> Usuario:
    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    return usuario


@router.get("/usuarios", response_model=list[UsuarioAdminOut])
def listar_usuarios(
    rol: Optional[RolUsuario] = None,
    q: Optional[str] = Query(None, max_length=100, description="Nombre o correo"),
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    consulta = db.query(Usuario)
    if rol is not None:
        consulta = consulta.filter(Usuario.rol == rol)
    if q and q.strip():
        patron = f"%{q.strip()}%"
        consulta = consulta.filter(
            or_(Usuario.nombre.ilike(patron), Usuario.correo.ilike(patron))
        )
    return consulta.order_by(Usuario.nombre).all()


@router.put("/usuarios/{usuario_id}/activo", response_model=UsuarioAdminOut)
def cambiar_activo(
    usuario_id: int,
    datos: ActivoIn,
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    usuario = _usuario_o_404(db, usuario_id)
    if usuario.id == admin.id:
        raise HTTPException(
            status_code=400, detail="No puedes desactivar tu propia cuenta."
        )
    usuario.activo = datos.activo
    db.commit()
    db.refresh(usuario)
    return usuario


@router.put("/usuarios/{usuario_id}/rol", response_model=UsuarioAdminOut)
def cambiar_rol(
    usuario_id: int,
    datos: RolIn,
    db: Session = Depends(get_db),
    admin: Usuario = _ADMIN,
):
    usuario = _usuario_o_404(db, usuario_id)
    if usuario.id == admin.id:
        raise HTTPException(status_code=400, detail="No puedes cambiar tu propio rol.")

    if usuario.rol == RolUsuario.repartidor and datos.rol != RolUsuario.repartidor:
        en_curso = (
            db.query(Pedido)
            .filter(
                Pedido.repartidor_id == usuario.id,
                Pedido.estado.in_(
                    [
                        EstadoPedido.aceptado,
                        EstadoPedido.recogido,
                        EstadoPedido.en_camino,
                    ]
                ),
            )
            .count()
        )
        if en_curso:
            raise HTTPException(
                status_code=409,
                detail="Este repartidor tiene pedidos en curso; espera a que termine.",
            )

    usuario.rol = datos.rol
    db.commit()
    db.refresh(usuario)
    return usuario