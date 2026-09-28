# Food Express

Plataforma móvil de delivery de comida desarrollada con metodología Scrum: app para clientes, panel para repartidores, pagos e integración GPS. Proyecto de la materia Desarrollo Móvil Integral (UTFV).

## Equipo

- Jonathan Patricio Navarro de la Cruz: Product Owner
- Alfredo Vilchis Espinoza: Scrum Master
- Héctor Antonio Bermúdez Tapia, Uriel González Hernández, Carlos Núñez Durán y Christian Sánchez Romero: Equipo de Desarrollo

## Gestión del proyecto

Tablero público en Taiga: https://tree.taiga.io/project/carlosnd-app-delivery-food-express/

## Stack

Flutter (app), FastAPI (backend), MySQL con SQLAlchemy (pruebas locales con SQLite), Google Maps Platform y Mercado Pago.

## Estructura del repositorio

- `backend/`: API en FastAPI (modelo de datos, registro y autenticación).
- `app/`: aplicación móvil en Flutter (login y registro).
- `docs/`: diagrama de arquitectura, wireframes y capturas de evidencia.

## Estado: Sprint 1 (8 al 22 de septiembre de 2026)

- Arquitectura backend y modelo de datos: tablas usuarios, restaurantes y pedidos.
- Registro y autenticación con token JWT, con pantallas de login y registro en Flutter.

## Cómo correrlo

Backend:

```
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
uvicorn app.main:app --reload
```

En el `.env`, usa `DATABASE_URL=sqlite:///./food_express.db` para probar sin MySQL. La documentación de la API queda en http://127.0.0.1:8000/docs

App (con el backend corriendo):

```
cd app
flutter pub get
flutter run -d chrome
```
