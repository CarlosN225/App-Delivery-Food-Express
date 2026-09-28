import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';

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

    if (respuestaLogin.statusCode != 200) {
      throw AuthException(
        _detalleError(respuestaLogin.body) ?? 'Correo o contraseña incorrectos.',
      );
    }

    final token = jsonDecode(respuestaLogin.body)['access_token'] as String;

    final respuestaMe = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (respuestaMe.statusCode != 200) {
      throw AuthException('No se pudo obtener la información del usuario.');
    }

    final datos = jsonDecode(respuestaMe.body) as Map<String, dynamic>;
    return UsuarioAutenticado(
      id: datos['id'] as int,
      nombre: datos['nombre'] as String,
      correo: datos['correo'] as String,
      rol: datos['rol'] as String,
      token: token,
    );
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
