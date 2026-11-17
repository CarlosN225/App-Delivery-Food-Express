Product Backlog — Food Express
Product Owner: Jonathan Patricio Navarro de la Cruz

Fecha: 16 de noviembre de 2026

1. Visión del producto
Food Express es una aplicación móvil de entrega de comida a domicilio diseñada para conectar al cliente, al repartidor y al administrador dentro de un mismo flujo operativo: pedir, pagar, entregar y calificar.

2. Avance del proyecto por Sprint
El desarrollo se planificó en seis sprints de dos semanas, completando un total de 27 historias de usuario y 115 puntos de historia estimados mediante la escala de Fibonacci.

Sprint 1 (8 – 22 de septiembre): 16 puntos. Completado. Se estructuró la arquitectura del backend, el sistema de registro y login, y la primera priorización del backlog.

Sprint 2 (22 de septiembre – 6 de octubre): 15 puntos. Completado. Se implementó la visualización de restaurantes cercanos, el catálogo de menús y el panel de control para el repartidor.

Sprint 3 (6 – 20 de octubre): 22 puntos. Completado. Quedó operativo el carrito de compras, el flujo de pagos (efectivo y modo demostración), el cálculo de ruta óptima y la gestión de estados de entrega.

Sprint 4 (20 de octubre – 3 de noviembre): 20 puntos. Completado, con la salvedad de que las notificaciones actuales operan de manera interna en la aplicación mediante avisos emergentes y una campanita, sin integrar todavía notificaciones push nativas.

Sprint 5 (3 – 17 de noviembre): 25 puntos. Completado, a excepción del modo offline. Se desarrollaron las rutas inteligentes, el historial de pedidos y el sistema de reseñas.

Sprint 6 (17 de noviembre – 1 de diciembre): 17 puntos. En curso (fase de revisión final). Enfocado en pruebas integrales, corrección de errores y pulido general de la interfaz.

3. Backlog pendiente y mejoras futuras
Los elementos pendientes se encuentran organizados según su nivel de prioridad para el lanzamiento:

Prioridad Alta
Modo offline (8 puntos): No implementado. Representaba un diferenciador clave para mitigar los problemas de conectividad intermitente en diversas zonas del país.

Pago real con Mercado Pago: Preparado a nivel de código, pero sin activar. Requiere la configuración de credenciales de prueba y un servidor público accesible mediante HTTPS.

Despliegue del backend en la nube con HTTPS: Pendiente. Actualmente el servidor opera en un entorno local respaldado por un túnel temporal, por lo que se requiere una infraestructura estable en producción.

Prioridad Media
Notificaciones push (Firebase Cloud Messaging): El envío ya se encuentra preparado en el backend, pero falta realizar pruebas para garantizar que lleguen con la aplicación cerrada o en segundo plano.

Incorporación de restaurantes reales: Pendiente. Actualmente el sistema opera con 20 restaurantes de demostración precargados de manera controlada en la base de datos.

Imágenes de productos en los menús: Completado. Los 86 productos de los 20 restaurantes de demostración cuentan con su imagen, optimizada en formato WebP (de 269.2 MB a 11.2 MB).

Prioridad Baja
Detección explícita de desvío de ruta del repartidor: Pendiente. Hoy en día el sistema recalcula la ruta de forma automática cuando el repartidor se desplaza más de 200 metros respecto al punto donde se solicitó la última ruta.

Cambio del identificador de la aplicación: Pendiente. El APK de release ya se firma con una llave propia; falta reemplazar el identificador temporal (com.example) por uno definitivo, requisito para publicar en Google Play.

4. Criterio de priorización
La estrategia para ordenar los requerimientos sigue una jerarquía operativa clara: primero se resuelven los bloqueos críticos para la puesta en producción (como el servidor en la nube y la pasarela de pagos reales); en segundo lugar se abordan las mejoras que enriquecen directamente la experiencia del usuario (notificaciones y recursos visuales); y finalmente se atienden los ajustes técnicos o refinamientos de funcionalidades existentes.

5. Datos de demostración
Durante las fases de prueba en la zona de Nicolás Romero, Estado de México, se identificó que la mayoría de los negocios locales no se encuentran registrados en Google Maps. Para superar esta limitación y poder validar de punta a punta todo el flujo operativo con datos controlados, se cargaron manualmente 20 restaurantes ficticios junto con sus respectivos menús en la base de datos.
