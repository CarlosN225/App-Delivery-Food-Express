"""
Firebase Authentication (servicio en la nube) — lado del backend.

La recuperación de contraseña la hace Firebase: manda el correo con el enlace
y guarda la contraseña nueva. Como los usuarios de Food Express viven en la base
de datos propia, después de restablecerla la app entrega a este backend el
ID token que Firebase le dio al iniciar sesión, y aquí se comprueba con la API
de Firebase (accounts:lookup) que el token es válido y que el correo ya está
verificado (restablecer por enlace verifica el correo). Solo entonces se
actualiza la contraseña local.

Solo usa la librería estándar (no agrega dependencias). La clave web de
Firebase va en backend/.env como FIREBASE_API_KEY (ese archivo no se sube).
"""

import json
import os
import urllib.error
import urllib.request
from typing import Optional

_URL_LOOKUP = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={clave}"


def _clave_api() -> str:
    return os.getenv("FIREBASE_API_KEY", "").strip()


def disponible() -> bool:
    return bool(_clave_api())


def consultar_cuenta(id_token: str) -> Optional[dict]:
    """
    Pregunta a Firebase por el dueño de un ID token.
    Devuelve {"correo": str, "verificado": bool} o None si el token no sirve,
    Firebase no está configurado o no hay red.
    """
    clave = _clave_api()
    if not clave or not id_token:
        return None

    peticion = urllib.request.Request(
        _URL_LOOKUP.format(clave=clave),
        data=json.dumps({"idToken": id_token}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(peticion, timeout=8) as respuesta:
            datos = json.load(respuesta)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None

    usuarios = datos.get("users") or []
    if not usuarios:
        return None
    cuenta = usuarios[0]
    correo = str(cuenta.get("email") or "").strip().lower()
    if not correo:
        return None
    return {"correo": correo, "verificado": bool(cuenta.get("emailVerified"))}
