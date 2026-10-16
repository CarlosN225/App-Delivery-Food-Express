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

- `backend/`: API en FastAPI (autenticación, restaurantes y menú, pedidos, pagos y rutas).
- `app/`: aplicación móvil en Flutter (cliente: menú, carrito, pago y seguimiento; repartidor: pedidos, ruta y estados).
- `docs/`: diagrama de arquitectura, wireframes y capturas de evidencia.

## Estado: Sprint 3 (6 al 20 de octubre de 2026)

- Sprint 1: arquitectura backend, modelo de datos, registro y autenticación con JWT.
- Sprint 2: restaurantes cercanos, menú y panel del repartidor.
- Sprint 3 (historias #9 a #12):
  - **#9 Carrito y pedido:** el cliente arma su carrito (un restaurante a la vez), ve subtotal, envío y total, elige método de pago y genera el pedido. El backend recalcula todos los montos.
  - **#10 Pasarela de pagos:** Mercado Pago (Checkout Pro) o efectivo. Sin credenciales funciona en modo demo con un pago simulado.
  - **#11 Ruta óptima básica:** orden sugerido de paradas del repartidor (vecino más cercano, recoge antes de entregar) con km y minutos.
  - **#12 Estado de entrega:** el repartidor marca Recogido → En camino → Entregado y el cliente lo ve en «Mis pedidos».

Detalle de endpoints, cómo probar el flujo completo y pruebas automáticas: ver `backend/README.md`.

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

Pruebas del backend (opcional): `pip install -r requirements-dev.txt` y luego `pytest`.

App (con el backend corriendo):

```
cd app
flutter pub get
flutter run -d chrome
```

Pruebas de la app: `flutter test`. Si corres en emulador o celular, cambia `ApiConfig.baseUrl` en `app/lib/core/api_client.dart`.
