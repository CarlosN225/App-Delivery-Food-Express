import 'package:shared_preferences/shared_preferences.dart';

/// Guarda el token de la sesión en el navegador / dispositivo para que el
/// usuario no tenga que volver a iniciar sesión en cada recarga.
/// Solo se guarda el token: los datos del usuario se piden de nuevo al
/// servidor al abrir la app (así el rol siempre está al día).
class SesionService {
  static const _clave = 'food_express_token';

  static Future<void> guardar(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, token);
    } catch (_) {
      // Sin almacenamiento: la sesión simplemente no se recuerda.
    }
  }

  static Future<String?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_clave);
    } catch (_) {
      return null;
    }
  }

  /// Se llama al cerrar sesión (o cuando el token ya no sirve).
  static Future<void> borrar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_clave);
    } catch (_) {
      // Nada que borrar.
    }
  }
}
