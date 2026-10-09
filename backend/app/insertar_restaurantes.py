from app.database import SessionLocal
from app.models.restaurante import Restaurante


db = SessionLocal()

# Datos de prueba ubicados en Nicolás Romero, Edo. Méx. (direcciones ficticias)
restaurantes = [
    {
        "nombre": "Pizza Express",
        "direccion": "Calle Hidalgo 100, Nicolás Romero",
        "categoria": "Pizza",
        "latitud": "19.6010",
        "longitud": "-99.3085",
    },
    {
        "nombre": "Hamburguesas El Buen Sabor",
        "direccion": "Av. Independencia 250, Nicolás Romero",
        "categoria": "Hamburguesas",
        "latitud": "19.6045",
        "longitud": "-99.3150",
    },
    {
        "nombre": "Tacos Don Juan",
        "direccion": "Calle Juárez 50, Nicolás Romero",
        "categoria": "Mexicana",
        "latitud": "19.5950",
        "longitud": "-99.3200",
    },
    {
        "nombre": "Sushi House",
        "direccion": "Av. Morelos 300, Nicolás Romero",
        "categoria": "Sushi",
        "latitud": "19.6100",
        "longitud": "-99.3050",
    },
]


for datos in restaurantes:
    existente = (
        db.query(Restaurante)
        .filter(Restaurante.nombre == datos["nombre"])
        .first()
    )
    if existente:
        existente.direccion = datos["direccion"]
        existente.categoria = datos["categoria"]
        existente.latitud = datos["latitud"]
        existente.longitud = datos["longitud"]
    else:
        db.add(Restaurante(**datos))

db.commit()

print("Restaurantes insertados correctamente.")

db.close()