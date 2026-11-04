"""
Crea un administrador (o convierte en administrador a un usuario existente).

Uso, desde la carpeta backend y con el entorno virtual activo:

    python crear_admin.py correo@ejemplo.com "Nombre Apellido" contrasena

Si el correo ya existe, solo se le da el rol de administrador (y se reactiva);
el nombre y la contraseña que pongas se ignoran.
"""

import sys

from app import models  # noqa: F401  (registra las tablas)
from app.database import Base, SessionLocal, engine
from app.migraciones import aplicar_migraciones
from app.models.usuario import RolUsuario, Usuario
from app.services.security import hash_contrasena


def main() -> None:
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    correo, nombre, contrasena = sys.argv[1:4]
    if len(contrasena) < 6:
        print("La contraseña debe tener al menos 6 caracteres.")
        sys.exit(1)

    Base.metadata.create_all(bind=engine)
    aplicar_migraciones(engine)

    db = SessionLocal()
    try:
        usuario = db.query(Usuario).filter(Usuario.correo == correo).first()
        if usuario:
            usuario.rol = RolUsuario.administrador
            usuario.activo = True
            print(f"Listo: {correo} ahora es administrador.")
        else:
            db.add(
                Usuario(
                    nombre=nombre,
                    correo=correo,
                    contrasena_hash=hash_contrasena(contrasena),
                    rol=RolUsuario.administrador,
                )
            )
            print(f"Listo: administrador {correo} creado.")
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    main()