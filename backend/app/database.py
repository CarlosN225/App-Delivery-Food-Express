"""
Configuración de la base de datos.

En producción, DATABASE_URL apunta a MySQL, por ejemplo:
    mysql+pymysql://usuario:contraseña@localhost:3306/food_express

Para pruebas locales rápidas (sin tener MySQL instalado), se puede
usar SQLite cambiando esa misma variable a:
    sqlite:///./food_express.db
"""

import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./food_express.db")

# connect_args solo es necesario para SQLite (no aplica a MySQL)
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """Dependencia de FastAPI: entrega una sesión de base de datos por request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
