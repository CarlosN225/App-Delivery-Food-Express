# Sprint 4 — Validación del incremento (#18)

Cierre del sprint: 3 de noviembre de 2026.

## Resumen del incremento

| Historia | Qué se entrega |
|---|---|
| #14 Rastreo del pedido en tiempo real | El repartidor reporta su GPS cada 10 s; el cliente ve el mapa con restaurante, «Tú» y repartidor, los pasos del pedido y «Llega aprox. HH:MM». Se actualiza cada 5 s. |
| #15 Notificaciones del estado del pedido | Cada cambio de estado (aceptado, recogido, en camino, entregado) genera una notificación para el cliente: campanita con contador, lista y aviso emergente. |
| #16 Panel administrativo: restaurantes | El administrador da de alta, edita y elimina restaurantes (con coordenadas). |
| #17 Panel administrativo: usuarios y repartidores | El administrador busca y filtra usuarios, activa o desactiva cuentas y cambia roles. |

## Criterios de aceptación

### #14 Rastreo en tiempo real
- [ ] El repartidor con un pedido en curso manda su posición (`PUT /pedidos/{id}/ubicacion`).
- [ ] El cliente ve al repartidor en el mapa y la posición se actualiza sola.
- [ ] Se muestra el paso actual (Aceptado, Recogido, En camino, Entregado) y la hora estimada de llegada.
- [ ] Solo el dueño del pedido (o un administrador) puede ver el seguimiento; otro cliente recibe 403.
- [ ] Un repartidor ajeno, o un pedido terminado, no permite reportar ubicación.

### #15 Notificaciones
- [ ] Cada cambio de estado crea una notificación para el cliente.
- [ ] La campanita muestra cuántas no se han leído y baja al leerlas.
- [ ] Aparece un aviso emergente en menos de 10 s, incluso estando en otra pantalla.
- [ ] Al tocar una notificación se marca como leída y abre el rastreo del pedido.
- [ ] Un fallo al notificar nunca rompe el cambio de estado del pedido.

### #16 Restaurantes (administrador)
- [ ] Crear un restaurante con nombre, dirección, categoría y coordenadas; aparece en «Restaurantes cercanos».
- [ ] Editar sus datos.
- [ ] Eliminar uno sin pedidos; uno con pedidos se rechaza con un mensaje claro.
- [ ] Un cliente o repartidor recibe 403 en cualquier ruta `/admin`.
- [ ] El registro público ya no permite crear cuentas de administrador.

### #17 Usuarios y repartidores (administrador)
- [ ] Listar usuarios, buscar por nombre o correo y filtrar por rol.
- [ ] Desactivar una cuenta: no puede iniciar sesión y su sesión abierta deja de funcionar. Reactivarla la devuelve.
- [ ] Cambiar el rol de un usuario (con confirmación para administrador).
- [ ] El administrador no puede desactivarse ni cambiarse el rol a sí mismo.
- [ ] No se cambia el rol de un repartidor con pedidos en curso.

## Pruebas automáticas

Backend (desde `backend`): `python -m pytest`
- `tests/test_seguimiento_sprint4.py` (#14), `tests/test_notificaciones_sprint4.py` (#15), `tests/test_admin_sprint4.py` (#16 y #17), más las pruebas de sprints anteriores.
- Resultado: ___ pruebas pasadas, ___ fallidas.

App (desde `app`): `flutter test` y `flutter analyze`
- `test/sprint4_test.dart` cubre los modelos y utilidades nuevos.
- Resultado de `flutter test`: ___ pruebas pasadas.
- Resultado de `flutter analyze`: ___ (sin errores).

## Prueba manual (guion de la demo)

1. Iniciar el backend (`python -m uvicorn app.main:app --reload`) y la app (`flutter run -d chrome`).
2. Entrar como cliente y hacer un pedido en efectivo.
3. En `/docs`, como repartidor: aceptar el pedido y mandar una ubicación.
4. En la app: aparece el aviso «Pedido aceptado», la campanita sube a 1 y «Rastrear pedido» abre el mapa.
5. Mover al repartidor en `/docs` acercándolo al cliente y ver cómo baja el tiempo estimado.
6. Cambiar el estado a recogido, en camino y entregado: cada cambio da su aviso y avanzan los pasos.
7. Entrar como administrador: crear, editar y eliminar un restaurante.
8. En «Usuarios y repartidores»: buscar, desactivar a un cliente, comprobar que no puede entrar y reactivarlo.

## Capturas de evidencia (carpeta `docs/capturas/`)

- [ ] `s4-01-rastreo-mapa.png`: pantalla «Rastreo de tu pedido».
- [ ] `s4-02-aviso-notificacion.png`: aviso emergente con la campanita.
- [ ] `s4-03-lista-notificaciones.png`: lista de notificaciones.
- [ ] `s4-04-admin-restaurantes.png`: pestaña Restaurantes.
- [ ] `s4-05-admin-formulario.png`: crear o editar restaurante.
- [ ] `s4-06-admin-usuarios.png`: pestaña Usuarios y repartidores.
- [ ] `s4-07-pruebas-backend.png`: salida de `pytest`.
- [ ] `s4-08-pruebas-app.png`: salida de `flutter test`.

## Decisiones y limitaciones conocidas

- **Notificaciones:** en Chrome funcionan dentro de la app, consultando al backend cada 10 s. El backend ya trae el envío por Firebase (FCM), activable con `FIREBASE_CREDENTIALS` y `pip install firebase-admin`, pero esa vía no se probó de punta a punta porque requiere un proyecto de Firebase y un dispositivo Android.
- **Rastreo:** la línea del mapa es recta entre puntos (no sigue las calles) y el GPS del repartidor se manda solo mientras su panel está abierto. El mapa usa OpenStreetMap, sin API key.
- **Restaurantes:** un restaurante con pedidos no se puede eliminar, para conservar el historial.
- **Notificaciones solo para clientes:** el repartidor no recibe avisos en este sprint.

## Cambios de seguridad

- El registro público ya no crea administradores (responde 403). El primero se crea con `python crear_admin.py correo "Nombre" contraseña` desde `backend`.
- Las cuentas desactivadas no pueden iniciar sesión y sus sesiones abiertas dejan de ser válidas.
- El seguimiento de un pedido solo lo ve su dueño o un administrador.

## Para el Sprint 5

- Rutas por calles y mapa con Google Maps Platform.
- Push real con Firebase en Android.
- Aviso al repartidor cuando hay pedidos nuevos disponibles.