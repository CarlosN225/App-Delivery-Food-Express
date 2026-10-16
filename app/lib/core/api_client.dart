import 'dart:convert';

import 'package:http/http.dart' as http;

/// Configuración base para conectarse al backend de Food Express.
///
/// IMPORTANTE — la URL correcta depende de dónde estés corriendo la app:
///  - Flutter Web (chrome), la forma más rápida de probar:  http://127.0.0.1:8000
///  - Emulador de Android:                                  http://10.0.2.2:8000
///  - Simulador de iOS:                                     http://127.0.0.1:8000
///  - Dispositivo físico (celular real):                    http://<IP-de-tu-compu>:8000
///
/// Cambia el valor de abajo según en dónde vayas a probar.
class ApiConfig {
  static const String baseUrl = 'http://127.0.0.1:8000';
}

/// Error de la API o de conexión, con un mensaje listo para mostrar al usuario.
class ApiException implements Exception {
  final String mensaje;
  final int? codigo;

  ApiException(this.mensaje, {this.codigo});

  @override
  String toString() => mensaje;
}

/// Cliente HTTP mínimo: agrega el token, decodifica JSON en UTF-8 (para que
/// los acentos no se dañen) y convierte los errores en [ApiException].
class ApiClient {
  static Uri _uri(String ruta, Map<String, String>? query) {
    final base = Uri.parse('${ApiConfig.baseUrl}$ruta');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> get(
    String ruta, {
    String? token,
    Map<String, String>? query,
  }) =>
      _enviar(() => http.get(_uri(ruta, query), headers: _headers(token)));

  static Future<dynamic> post(String ruta, {String? token, Object? body}) =>
      _enviar(
        () => http.post(
          _uri(ruta, null),
          headers: _headers(token),
          body: body == null ? null : jsonEncode(body),
        ),
      );

  static Future<dynamic> put(String ruta, {String? token, Object? body}) =>
      _enviar(
        () => http.put(
          _uri(ruta, null),
          headers: _headers(token),
          body: body == null ? null : jsonEncode(body),
        ),
      );

  static Future<dynamic> _enviar(
    Future<http.Response> Function() peticion,
  ) async {
    try {
      final respuesta = await peticion().timeout(const Duration(seconds: 20));
      if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
        if (respuesta.bodyBytes.isEmpty) return null;
        return jsonDecode(utf8.decode(respuesta.bodyBytes));
      }
      throw ApiException(_detalle(respuesta), codigo: respuesta.statusCode);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }
  }

  static String _detalle(http.Response respuesta) {
    try {
      final json = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (json is Map && json['detail'] is String) {
        return json['detail'] as String;
      }
      if (respuesta.statusCode == 422) {
        return 'Revisa los datos e intenta de nuevo.';
      }
    } catch (_) {}
    if (respuesta.statusCode == 401) {
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    }
    return 'Ocurrió un error (${respuesta.statusCode}).';
  }
}
