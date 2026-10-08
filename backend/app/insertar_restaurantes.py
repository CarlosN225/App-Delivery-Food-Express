from app.database import SessionLocal
from app.models.restaurante import Restaurante


db = SessionLocal()

restaurantes = [
    Restaurante(
        nombre="Pizza Express",
        direccion="Av. Insurgentes Sur 100",
        categoria="Pizza",
        latitud="19.4326",
        longitud="-99.1332",
    ),
    Restaurante(
        nombre="Hamburguesas El Buen Sabor",
        direccion="Av. Reforma 250",
        categoria="Hamburguesas",
        latitud="19.4350",
        longitud="-99.1400",
    ),
    Restaurante(
        nombre="Tacos Don Juan",
        direccion="Calle Juárez 50",
        categoria="Mexicana",
        latitud="19.4250",
        longitud="-99.1250",
    ),
    Restaurante(
        nombre="Sushi House",
        direccion="Av. Chapultepec 300",
        categoria="Sushi",
        latitud="19.4280",
        longitud="-99.1450",
    ),
]


for restaurante in restaurantes:
    db.add(restaurante)

db.commit()

print("Restaurantes insertados correctamente.")

db.close()