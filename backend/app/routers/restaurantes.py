from math import radians, sin, cos, sqrt, atan2

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.restaurante import Restaurante
from app.schemas.restaurante import RestauranteCercano


router = APIRouter(
    prefix="/restaurantes",
    tags=["Restaurantes"],
)


def calcular_distancia(
    latitud_usuario: float,
    longitud_usuario: float,
    latitud_restaurante: float,
    longitud_restaurante: float,
) -> float:
    """
    Calcula la distancia aproximada entre dos coordenadas
    utilizando la fórmula de Haversine.

    El resultado se devuelve en kilómetros.
    """

    radio_tierra = 6371.0

    lat1 = radians(latitud_usuario)
    lon1 = radians(longitud_usuario)

    lat2 = radians(latitud_restaurante)
    lon2 = radians(longitud_restaurante)

    diferencia_latitud = lat2 - lat1
    diferencia_longitud = lon2 - lon1

    a = (
        sin(diferencia_latitud / 2) ** 2
        + cos(lat1)
        * cos(lat2)
        * sin(diferencia_longitud / 2) ** 2
    )

    c = 2 * atan2(sqrt(a), sqrt(1 - a))

    distancia = radio_tierra * c

    return distancia


@router.get(
    "/cercanos",
    response_model=list[RestauranteCercano],
)
def obtener_restaurantes_cercanos(
    latitud: float = Query(..., description="Latitud del usuario"),
    longitud: float = Query(..., description="Longitud del usuario"),
    radio_km: float = Query(
        10.0,
        description="Radio máximo de búsqueda en kilómetros",
    ),
    db: Session = Depends(get_db),
):
    """
    Devuelve los restaurantes que se encuentran dentro
    del radio indicado, ordenados del más cercano al más lejano.
    """

    restaurantes = db.query(Restaurante).all()

    restaurantes_cercanos = []

    for restaurante in restaurantes:

        # Si el restaurante no tiene coordenadas, no podemos
        # calcular su distancia.
        if restaurante.latitud is None or restaurante.longitud is None:
            continue

        try:
            latitud_restaurante = float(restaurante.latitud)
            longitud_restaurante = float(restaurante.longitud)
        except (ValueError, TypeError):
            continue

        distancia = calcular_distancia(
            latitud,
            longitud,
            latitud_restaurante,
            longitud_restaurante,
        )

        if distancia <= radio_km:
            restaurantes_cercanos.append(
                RestauranteCercano(
                    id=restaurante.id,
                    nombre=restaurante.nombre,
                    direccion=restaurante.direccion,
                    categoria=restaurante.categoria,
                    latitud=restaurante.latitud,
                    longitud=restaurante.longitud,
                    distancia_km=round(distancia, 2),
                )
            )

    # Ordenar del restaurante más cercano al más lejano
    restaurantes_cercanos.sort(
        key=lambda restaurante: restaurante.distancia_km
    )

    return restaurantes_cercanos