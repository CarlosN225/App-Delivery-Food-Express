import 'package:shared_preferences/shared_preferences.dart';

import '../../core/seguridad/cifrado_service.dart';
import '../../core/seguridad/registro.dart';

/// Guarda el token de la sesión en el navegador / dispositivo para que el
/// usuario no tenga que volver a iniciar sesión en cada recarga.
/// Solo se guarda el token: los datos del usuario se piden de nuevo al
/// servidor al abrir la app (así el rol siempre está al día).
///
/// El token se guarda CIFRADO con AES-256-GCM (ver [CifradoService]); así no
/// queda legible si alguien abre el almacenamiento local.
class SesionService {
  static const _clave = 'food_express_token';

  static Future<void> guardar(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, await CifradoService.cifrar(token));
    } catch (e) {
      Registro.aviso('No se pudo guardar la sesión: $e');
      // Sin almacenamiento: la sesión simplemente no se recuerda.
    }
  }

  static Future<String?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getString(_clave);
      if (guardado == null) return null;

      // Sesiones guardadas antes del cifrado: se leen una vez y se migran.
      if (!CifradoService.estaCifrado(guardado)) {
        await guardar(guardado);
        return guardado;
      }

      final token = await CifradoService.descifrar(guardado);
      if (token == null) await borrar(); // dato alterado o llave perdida
      return token;
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
