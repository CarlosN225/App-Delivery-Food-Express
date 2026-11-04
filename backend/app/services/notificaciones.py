"""
Notificaciones del estado del pedido — Sprint 4, historia #15.

Cada vez que el pedido cambia de estado (aceptado, recogido, en camino,
entregado) se guarda una notificación para el cliente y se intenta mandar un
push al celular.

Dos modos, igual que los pagos del Sprint 3:
  - MODO DEMO (por defecto): sin `FIREBASE_CREDENTIALS` solo se guarda la
    notificación y se escribe una línea en la consola del servidor. La app la
    recoge consultando /notificaciones.
  - MODO REAL: con `FIREBASE_CREDENTIALS` (ruta al JSON de la cuenta de servicio
    de Firebase) y `pip install firebase-admin`, además se manda el push por FCM
    a los dispositivos registrados con POST /notificaciones/token.

Un fallo al notificar NUNCA rompe el cambio de estado del pedido.
"""

import logging
import os
from typing import Optional

from sqlalchemy.orm import Session

from app.models.notificacion import Notificacion, TokenDispositivo
from app.models.pedido import EstadoPedido, Pedido

# Se usa el logger de uvicorn para que los mensajes salgan en su consola.
logger = logging.getLogger("uvicorn.error")


def _texto(pedido: Pedido) -> Optional[tuple[str, str]]:
    """Título y mensaje para el estado actual del pedido (None si no aplica)."""
    n = pedido.id
    repartidor = pedido.repartidor.nombre if pedido.repartidor else "Tu repartidor"
    textos = {
        EstadoPedido.aceptado: (
            "Pedido aceptado",
            f"{repartidor} aceptó tu pedido #{n} y va al restaurante.",
        ),
        EstadoPedido.recogido: (
            "Pedido recogido",
            f"{repartidor} ya recogió tu pedido #{n} en {pedido.restaurante.nombre}.",
        ),
        EstadoPedido.en_camino: (
            "¡Tu pedido va en camino!",
            f"Tu pedido #{n} ya viene hacia ti.",
        ),
        EstadoPedido.entregado: (
            "Pedido entregado",
            f"Tu pedido #{n} fue entregado. ¡Buen provecho!",
        ),
        EstadoPedido.cancelado: (
            "Pedido cancelado",
            f"Tu pedido #{n} fue cancelado.",
        ),
    }
    return textos.get(pedido.estado)


def _firebase_messaging():
    """Módulo `messaging` de Firebase, o None si no hay credenciales (modo demo)."""
    ruta = os.getenv("FIREBASE_CREDENTIALS", "").strip()
    if not ruta:
        return None
    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials, messaging  # type: ignore
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app(credentials.Certificate(ruta))
        return messaging
    except Exception:
        logger.exception("Firebase no está bien configurado; se usa el modo demo.")
        return None


def enviar_push(
    db: Session,
    usuario_id: int,
    titulo: str,
    mensaje: str,
    datos: Optional[dict] = None,
) -> int:
    """Manda el push a los dispositivos del usuario. Devuelve cuántos se enviaron."""
    messaging = _firebase_messaging()
    if messaging is None:
        logger.info("[push demo] usuario %s: %s — %s", usuario_id, titulo, mensaje)
        return 0

    tokens = (
        db.query(TokenDispositivo)
        .filter(TokenDispositivo.usuario_id == usuario_id)
        .all()
    )
    enviados = 0
    for t in tokens:
        try:
            messaging.send(
                messaging.Message(
                    token=t.token,
                    notification=messaging.Notification(title=titulo, body=mensaje),
                    data=datos or {},
                )
            )
            enviados += 1
        except messaging.UnregisteredError:
            # El celular ya no usa ese token (desinstaló la app): se borra.
            db.delete(t)
            db.commit()
        except Exception:
            logger.exception("No se pudo mandar el push al token %s", t.id)
    return enviados


def notificar_estado(db: Session, pedido: Pedido) -> None:
    """Guarda la notificación del cliente y manda el push. Nunca lanza errores."""
    pedido_id = pedido.id
    try:
        texto = _texto(pedido)
        if texto is None:
            return
        titulo, mensaje = texto
        cliente_id = pedido.cliente_id
        estado = pedido.estado.value
        db.add(
            Notificacion(
                usuario_id=cliente_id,
                pedido_id=pedido_id,
                titulo=titulo,
                mensaje=mensaje,
            )
        )
        db.commit()
        enviar_push(
            db,
            cliente_id,
            titulo,
            mensaje,
            {"pedido_id": str(pedido_id), "estado": estado},
        )
    except Exception:
        db.rollback()
        logger.exception("No se pudo notificar el pedido %s", pedido_id)