# Food Express — Backend (Sprint 1)

API construida con FastAPI. Cubre las historias del Sprint 1:

- **#1 Arquitectura backend y modelo de datos** — modelos de `Usuario`, `Restaurante` y `Pedido` con sus relaciones, listos para MySQL.
- **#2 Registro y autenticación de clientes y repartidores** — registro, login con JWT y una ruta protegida de prueba.

Ya probado de punta a punta (registro, login, token, ruta protegida, y validación de errores).

## Cómo correrlo

1. Crear el entorno virtual e instalar dependencias:

```bash
python3 -m venv venv
venv/bin/pip install -r requirements.txt
```

2. Copiar `.env.example` a `.env` y llenar tus datos reales de MySQL:

```bash
cp .env.example .env
```

3. Levantar el servidor:

```bash
venv/bin/python -m uvicorn app.main:app --reload
```

4. Abrir en el navegador: **http://127.0.0.1:8000/docs**

Ahí aparece la documentación interactiva (Swagger). Se puede probar `/auth/registro` y `/auth/login` directo desde ahí, sin necesidad de Postman — útil para la demo del Sprint Review.

## Probar rápido sin MySQL instalado

Si todavía no tienes MySQL a la mano, cambia en tu `.env`:

```
DATABASE_URL=sqlite:///./food_express.db
```

Y todo funciona igual (las tablas se crean solas al arrancar el servidor). Cuando tengan MySQL listo, solo se cambia esa línea — el resto del código no cambia.

## Endpoints disponibles

| Método | Ruta            | Descripción                                      |
|--------|-----------------|---------------------------------------------------|
| POST   | `/auth/registro`| Crea un usuario (cliente, repartidor o admin)     |
| POST   | `/auth/login`   | Devuelve un token JWT (usar como `username`/`password`) |
| GET    | `/auth/me`      | Ruta protegida: devuelve el usuario del token      |
| GET    | `/`             | Estado del servicio                               |

## Estructura

```
app/
├── main.py            # arranque de la app y creación de tablas
├── database.py         # conexión a MySQL/SQLite vía SQLAlchemy
├── models/              # Usuario, Restaurante, Pedido
├── schemas/            # validación de datos (Pydantic)
├── routers/auth.py      # registro, login, ruta protegida
└── services/security.py # hash de contraseñas y manejo de JWT
```

## Siguientes Sprints (ya contemplado en la arquitectura)

- Sprint 2: endpoints de restaurantes y menú (tabla `Restaurante` ya existe).
- Sprint 3: carrito/pedido y pagos con Mercado Pago (tabla `Pedido` ya existe).
- Sprint 5: integración de Google Maps para rutas.
