# Food Express — Backend

API construida con FastAPI.

| Sprint | Historias |
|---|---|
| 1 | #1 Arquitectura y modelo de datos · #2 Registro y autenticación (JWT) |
| 2 | Restaurantes cercanos, menú de productos, panel del repartidor |
| 3 | **#9** Carrito y pedido · **#10** Pasarela de pagos · **#11** Ruta óptima básica · **#12** Estado de entrega |

## Cómo correrlo

```bash
python3 -m venv venv
venv/bin/pip install -r requirements.txt
cp .env.example .env
venv/bin/python -m uvicorn app.main:app --reload
```

Documentación interactiva (Swagger): **http://127.0.0.1:8000/docs**

Para probar sin MySQL, en el `.env` usa `DATABASE_URL=sqlite:///./food_express.db`. Las tablas se crean solas al arrancar y, si ya tenías una base de datos de Sprints anteriores, se le agregan sola las columnas nuevas de `pedidos` (`app/migraciones.py`); tus pedidos viejos se tratan como «efectivo, pago contra entrega».

Datos de ejemplo: `python -m app.insertar_restaurantes`, `python -m app.insertar_productos` y, para tener un pedido que el repartidor pueda tomar sin usar la app del cliente, `python -m app.insertar_pedido_prueba`.

## Pruebas automáticas

```bash
venv/bin/pip install -r requirements-dev.txt
venv/bin/pytest
```

Cubren el flujo completo: cotizar → crear pedido → pago (modo demo) → disponibles → aceptar/rechazar → Recogido/En camino/Entregado → ruta óptima, además de permisos y validaciones.

## Flujo del Sprint 3

```
Cliente                         Backend                          Repartidor
  │ POST /pedidos/cotizar  ───►  subtotal + envío + total
  │ POST /pedidos          ───►  crea pedido (pendiente)
  │   efectivo: listo  ·  Mercado Pago: POST /pagos/pedido/{id}/preferencia
  │   → paga en Mercado Pago → POST /pagos/pedido/{id}/verificar (estado_pago = pagado)
  │                                                        GET /pedidos/disponibles ◄─
  │                                                        PUT /pedidos/{id}/aceptar ◄─  (aceptado)
  │                                                        PUT /pedidos/{id}/estado  ◄─  recogido → en_camino → entregado
  │ GET /pedidos/mis-pedidos ◄── ve el estado en vivo      GET /pedidos/ruta-optima  ◄─
```

Un pedido con Mercado Pago **no aparece para los repartidores hasta que está pagado**. Los precios y el total siempre los calcula el backend (la app solo manda producto y cantidad). Un pedido en efectivo queda como cobrado cuando el repartidor lo marca como entregado.

## Endpoints

Todos (salvo `/auth/registro`, `/auth/login`, restaurantes y productos) requieren `Authorization: Bearer <token>`.

| Método | Ruta | Rol | Descripción |
|---|---|---|---|
| POST | `/auth/registro`, `/auth/login` | — | Alta y login (JWT) |
| GET | `/auth/me` | cualquiera | Usuario del token |
| GET | `/restaurantes/cercanos` | — | Restaurantes por distancia |
| GET | `/productos/restaurante/{id}` | — | Menú |
| POST | `/pedidos/cotizar` | cliente | Subtotal, envío y total del carrito |
| POST | `/pedidos` | cliente | Genera el pedido (`metodo_pago`: `efectivo` o `mercado_pago`) |
| GET | `/pedidos/mis-pedidos` | cliente | Pedidos del cliente con su estado |
| POST | `/pedidos/{id}/cancelar` | cliente | Solo si sigue pendiente y sin pagar |
| GET | `/pedidos/{id}` | dueño / repartidor asignado / admin | Detalle |
| POST | `/pagos/pedido/{id}/preferencia` | cliente | Enlace de pago de Mercado Pago (`init_point`) |
| POST | `/pagos/pedido/{id}/verificar` | cliente | Confirma el pago consultando a Mercado Pago |
| POST | `/pagos/webhook` | Mercado Pago | Notificación de pago (se valida contra la API de MP) |
| GET | `/pedidos/disponibles` | repartidor | Pedidos pagados/efectivo sin repartidor (`?latitud=&longitud=` para distancias) |
| PUT | `/pedidos/{id}/aceptar` | repartidor | Toma el pedido (si dos aceptan a la vez, solo uno gana) |
| PUT | `/pedidos/{id}/rechazar` | repartidor | Lo oculta solo para ese repartidor |
| GET | `/pedidos/activos` | repartidor | Pedidos aceptados sin entregar |
| PUT | `/pedidos/{id}/estado` | repartidor | Avanza: `recogido` → `en_camino` → `entregado` |
| GET | `/pedidos/ruta-optima` | repartidor | Orden sugerido de todas sus paradas, con km y minutos |
| GET | `/pedidos/{id}/ruta` | repartidor | Ruta restante de un pedido según su estado |

## Pagos con Mercado Pago

- **Modo demo (por defecto):** si `MERCADO_PAGO_ACCESS_TOKEN` está vacío, `init_point` abre una página del propio backend con «Aprobar pago» / «Rechazar pago». Sirve para toda la demo del Sprint Review sin cuenta de Mercado Pago.
- **Modo real:** pon el Access Token de prueba o producción en el `.env`. El backend crea la preferencia (Checkout Pro) y confirma cada pago consultando la API de Mercado Pago, comprobando que corresponda al pedido y al monto. Para webhook y regreso automático necesita una URL pública `https` en `PUBLIC_BASE_URL` (por ejemplo ngrok).
- Desde un celular real, el enlace de pago usa la misma dirección con la que la app llama al backend, así que `ApiConfig.baseUrl` debe ser la IP de tu computadora, no `127.0.0.1`.

## Ruta óptima básica (#11)

`app/services/logistica.py` (Python puro, con pruebas propias): distancias Haversine, costo de envío (`$20 + $4/km`, mínimo `$30`), tiempo estimado (25 km/h) y orden de paradas por *vecino más cercano*, respetando que un pedido se recoge antes de entregarse. En el Sprint 5 se puede sustituir por Google Directions sin cambiar la interfaz.

## Estructura

```
app/
├── main.py              # arranque, tablas y migraciones
├── migraciones.py       # columnas nuevas para bases de datos viejas
├── models/              # Usuario, Restaurante, Producto, Pedido, ItemPedido, PedidoRechazado
├── schemas/             # validación (Pydantic)
├── routers/             # auth, restaurantes, productos, pedidos, pagos
└── services/            # security (JWT), logistica (rutas/envío), mercadopago
tests/                   # pytest
```
