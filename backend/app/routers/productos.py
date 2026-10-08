from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.producto import Producto
from app.schemas.producto import ProductoRespuesta


router = APIRouter(
    prefix="/productos",
    tags=["Productos"]
)


@router.get(
    "/restaurante/{restaurante_id}",
    response_model=List[ProductoRespuesta]
)
def obtener_productos_restaurante(
    restaurante_id: int,
    db: Session = Depends(get_db),
):
    productos = (
        db.query(Producto)
        .filter(
            Producto.restaurante_id == restaurante_id
        )
        .all()
    )

    return productos