import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/firebase_config.dart';

class FirebaseAuthException implements Exception {
  final String mensaje;
  FirebaseAuthException(this.mensaje);
}

/// Firebase Authentication (servicio en la nube) por su API REST.
///
/// Se usa para recuperar la contraseña: Firebase manda el correo con el enlace
/// y guarda la contraseña nueva. Las cuentas se reflejan en Firebase al
/// registrarse y al iniciar sesión; después de restablecer, el login entrega el
/// ID token al backend (`/auth/firebase/sincronizar`) para actualizar la
/// contraseña de la base de datos de la app.
class FirebaseAuthService {
  FirebaseAuthService._();

  static const String _base = 'https://identitytoolkit.googleapis.com/v1/accounts';

  static Future<Map<String, dynamic>> _llamar(
    String accion,
    Map<String, dynamic> cuerpo,
  ) async {
    final respuesta = await http
        .post(
          Uri.parse('$_base:$accion?key=${FirebaseConfig.apiKey}'),
          headers: {
            'Content-Type': 'application/json',
            'X-Firebase-Locale': 'es',
          },
          body: jsonEncode(cuerpo),
        )
        .timeout(const Duration(seconds: 10));

    final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
    if (respuesta.statusCode != 200) {
      final error = datos['error'];
      final codigo = error is Map ? (error['message'] as String? ?? '') : '';
      // Ejemplo: "WEAK_PASSWORD : Password should be at least 6 characters".
      throw FirebaseAuthException(codigo.split(' ').first);
    }
    return datos;
  }

  /// Crea la cuenta en Firebase. Si ya existe o falla, no pasa nada.
  static Future<void> crearCuenta(String correo, String contrasena) async {
    if (!FirebaseConfig.disponible) return;
    try {
      await _llamar('signUp', {
        'email': correo,
        'password': contrasena,
        'returnSecureToken': false,
      });
    } catch (e) {
      debugPrint('Firebase: la cuenta no se creó (puede que ya exista).');
    }
  }

  /// Inicia sesión en Firebase y devuelve el ID token, o null si no se pudo.
  static Future<String?> iniciarSesion(String correo, String contrasena) async {
    if (!FirebaseConfig.disponible) return null;
    try {
      final datos = await _llamar('signInWithPassword', {
        'email': correo,
        'password': contrasena,
        'returnSecureToken': true,
      });
      return datos['idToken'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Refleja la cuenta en Firebase (se llama tras registrarse o iniciar
  /// sesión en la app). Corre en segundo plano y nunca estorba el login.
  static Future<void> asegurarCuenta(String correo, String contrasena) async {
    if (!FirebaseConfig.disponible) return;
    final token = await iniciarSesion(correo, contrasena);
    if (token == null) await crearCuenta(correo, contrasena);
  }

  /// Manda el correo para restablecer la contraseña.
  ///
  /// Antes se asegura de que el correo exista en Firebase (cuentas que se
  /// registraron antes de conectar Firebase todavía no estaban). Si ya existe,
  /// `crearCuenta` no hace nada.
  static Future<void> enviarCorreoRecuperacion(String correo) async {
    if (!FirebaseConfig.disponible) {
      throw FirebaseAuthException(
        'La recuperación por correo no está configurada en esta instalación.',
      );
    }
    await crearCuenta(correo, _contrasenaAleatoria());
    try {
      await _llamar('sendOobCode', {
        'requestType': 'PASSWORD_RESET',
        'email': correo,
      });
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(_traducir(e.mensaje));
    } on TimeoutException {
      throw FirebaseAuthException('Firebase tardó demasiado. Intenta de nuevo.');
    } catch (_) {
      throw FirebaseAuthException(
        'No se pudo conectar con Firebase. Revisa tu conexión.',
      );
    }
  }

  static String _traducir(String codigo) {
    switch (codigo) {
      case 'EMAIL_NOT_FOUND':
        return 'No encontramos una cuenta con ese correo.';
      case 'INVALID_EMAIL':
        return 'El correo no es válido.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Demasiados intentos. Espera un momento y vuelve a intentar.';
      default:
        return 'No se pudo enviar el correo ($codigo).';
    }
  }

  /// Contraseña larga y al azar para cuentas que solo existen para poder
  /// mandar el correo de recuperación (la persona la cambia desde el enlace).
  static String _contrasenaAleatoria() {
    const letras = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final azar = Random.secure();
    return List.generate(24, (_) => letras[azar.nextInt(letras.length)]).join();
  }
}
