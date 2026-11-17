import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/firebase_config.dart';
import 'firebase_auth_service.dart';
import 'sesion_service.dart';

/// Datos del usuario ya autenticado, junto con su token de sesión.
class UsuarioAutenticado {
  final int id;
  final String nombre;
  final String correo;
  final String rol;
  final String token;

  UsuarioAutenticado({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.token,
  });
}

class AuthException implements Exception {
  final String mensaje;
  AuthException(this.mensaje);
}

class AuthService {
  Future<void> registrar({
    required String nombre,
    required String correo,
    required String contrasena,
    required String rol,
  }) async {
    final respuesta = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/registro'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nombre': nombre,
        'correo': correo,
        'contrasena': contrasena,
        'rol': rol,
      }),
    );

    if (respuesta.statusCode != 201) {
      throw AuthException(
        _detalleError(respuesta.body) ?? 'No se pudo completar el registro.',
      );
    }

    // Firebase (nube): se refleja la cuenta para poder recuperar la contraseña.
    unawaited(FirebaseAuthService.asegurarCuenta(correo, contrasena));
  }

  Future<UsuarioAutenticado> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final respuestaLogin = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': correo, 'password': contrasena},
    );

    String token;
    if (respuestaLogin.statusCode == 200) {
      token = jsonDecode(respuestaLogin.body)['access_token'] as String;
      // Firebase (nube): se refleja la cuenta (también las que ya existían).
      unawaited(FirebaseAuthService.asegurarCuenta(correo, contrasena));
    } else {
      // Puede que la contraseña se haya restablecido con Firebase: si Firebase
      // la acepta, el backend actualiza la suya y abre la sesión.
      final sincronizado = respuestaLogin.statusCode == 401
          ? await _sincronizarConFirebase(correo, contrasena)
          : null;
      if (sincronizado == null) {
        throw AuthException(
          _detalleError(respuestaLogin.body) ??
              'Correo o contraseña incorrectos.',
        );
      }
      token = sincronizado;
    }

    final respuestaMe = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (respuestaMe.statusCode != 200) {
      throw AuthException('No se pudo obtener la información del usuario.');
    }

    final datos = jsonDecode(respuestaMe.body) as Map<String, dynamic>;
    await SesionService.guardar(token);
    return UsuarioAutenticado(
      id: datos['id'] as int,
      nombre: datos['nombre'] as String,
      correo: datos['correo'] as String,
      rol: datos['rol'] as String,
      token: token,
    );
  }

  /// Recuperación con Firebase: si Firebase reconoce el correo y la contraseña
  /// (porque se restablecieron desde el enlace), el backend verifica el ID token
  /// y actualiza la contraseña de la app. Devuelve el token de sesión o null.
  Future<String?> _sincronizarConFirebase(
    String correo,
    String contrasena,
  ) async {
    if (!FirebaseConfig.disponible) return null;
    try {
      final idToken = await FirebaseAuthService.iniciarSesion(correo, contrasena);
      if (idToken == null) return null;

      final respuesta = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/firebase/sincronizar'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken, 'contrasena': contrasena}),
      );
      if (respuesta.statusCode != 200) return null;
      return jsonDecode(respuesta.body)['access_token'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Si quedó una sesión guardada, la valida con el servidor y devuelve al
  /// usuario. Devuelve null si no hay sesión, si ya expiró o si no hay red
  /// (en ese caso el token se conserva para el siguiente intento).
  Future<UsuarioAutenticado?> restaurarSesion() async {
    final token = await SesionService.leer();
    if (token == null || token.isEmpty) return null;

    try {
      final respuesta = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (respuesta.statusCode == 200) {
        final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
        return UsuarioAutenticado(
          id: datos['id'] as int,
          nombre: datos['nombre'] as String,
          correo: datos['correo'] as String,
          rol: datos['rol'] as String,
          token: token,
        );
      }

      // Token vencido, usuario desactivado o borrado: ya no sirve.
      if (respuesta.statusCode == 401 ||
          respuesta.statusCode == 403 ||
          respuesta.statusCode == 404) {
        await SesionService.borrar();
      }
    } catch (_) {
      // Sin conexión con el servidor: se queda el token y se pide el login.
    }
    return null;
  }

  String? _detalleError(String cuerpo) {
    try {
      final json = jsonDecode(cuerpo) as Map<String, dynamic>;
      return json['detail'] as String?;
    } catch (_) {
      return null;
    }
  }
}
