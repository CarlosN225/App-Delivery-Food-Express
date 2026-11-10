"""
Codificación segura (Actividad 2): sanitización de entradas y enmascarado de
datos personales (PII) en los logs.

Defensa en capas:
  * La defensa real contra la inyección SQL es que SQLAlchemy envía los
    valores como parámetros (nunca se arma SQL concatenando texto del usuario).
  * Esta sanitización con Regex es una capa extra: quita etiquetas HTML y
    caracteres peligrosos antes de guardar o buscar (previene XSS almacenado y
    patrones típicos de inyección).
  * Los logs nunca deben mostrar teléfonos, correos ni direcciones completas.
"""

import logging
import re
from typing import Optional

MAX_BUSQUEDA = 60

# ------------------------------------------------------------------ Regex ---
_ETIQUETAS_HTML = re.compile(r"<[^>]*>")
_SQL_COMENTARIOS = re.compile(r"(--|/\*|\*/|;)")
# Para búsquedas: solo letras (con acentos y ñ), números, espacio, guion, punto y &.
_NO_PERMITIDO_BUSQUEDA = re.compile(r"[^\w\s\-.&]|_", re.UNICODE)
# Para texto libre (nombre, dirección): se quitan solo los caracteres de marcado.
_NO_PERMITIDO_TEXTO = re.compile(r"[<>`\\{}$]")
_ESPACIOS = re.compile(r"\s+")

_TELEFONO = re.compile(r"(?<!\d)(?:\+?52[\s-]?)?(?:\d[\s-]?){9}\d(?!\d)")
_CORREO = re.compile(r"([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+\.[A-Za-z]{2,})")


# ----------------------------------------------------------- Sanitización ---
def sanitizar_busqueda(texto: Optional[str]) -> str:
    """Texto seguro para una búsqueda: sin etiquetas, comentarios SQL ni símbolos."""
    if not texto:
        return ""
    limpio = _ETIQUETAS_HTML.sub(" ", texto)
    limpio = _SQL_COMENTARIOS.sub(" ", limpio)
    limpio = _NO_PERMITIDO_BUSQUEDA.sub("", limpio)
    limpio = _ESPACIOS.sub(" ", limpio).strip()
    return limpio[:MAX_BUSQUEDA]


def sanitizar_texto(texto: Optional[str]) -> Optional[str]:
    """Texto libre seguro (nombre, dirección de entrega): quita HTML y símbolos de marcado."""
    if texto is None:
        return None
    limpio = _ETIQUETAS_HTML.sub("", texto)
    limpio = _NO_PERMITIDO_TEXTO.sub("", limpio)
    return _ESPACIOS.sub(" ", limpio).strip()


# ------------------------------------------------------------ Enmascarado ---
def enmascarar_telefono(telefono: str) -> str:
    """5512345678 -> ******5678 (solo se ven los últimos 4 dígitos)."""
    digitos = re.sub(r"\D", "", telefono)
    if len(digitos) <= 4:
        return "*" * len(digitos)
    return "*" * (len(digitos) - 4) + digitos[-4:]


def enmascarar_direccion(direccion: str) -> str:
    """'Calle Hidalgo 100, Col. Centro' -> 'Calle Hid***' (solo el inicio)."""
    direccion = direccion.strip()
    if len(direccion) <= 6:
        return "***"
    return direccion[:9] + "***"


def enmascarar_texto(texto: str) -> str:
    """Oculta teléfonos y correos que aparezcan dentro de cualquier mensaje."""
    texto = _TELEFONO.sub(lambda m: enmascarar_telefono(m.group(0)), texto)
    return _CORREO.sub(lambda m: f"{m.group(1)}***{m.group(2)}", texto)


class FiltroPII(logging.Filter):
    """Filtro de logging: enmascara datos personales antes de escribir el log."""

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            mensaje = record.getMessage()
        except Exception:
            return True
        record.msg = enmascarar_texto(mensaje)
        record.args = None
        return True


def instalar_filtro_pii() -> None:
    """Agrega el filtro a los loggers de la app y de uvicorn (se llama al arrancar)."""
    for nombre in ("", "uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(nombre)
        # El filtro va en el logger y en sus handlers (los handlers también
        # reciben los mensajes de los loggers hijos).
        for destino in [logger, *logger.handlers]:
            if not any(isinstance(f, FiltroPII) for f in destino.filters):
                destino.addFilter(FiltroPII())
