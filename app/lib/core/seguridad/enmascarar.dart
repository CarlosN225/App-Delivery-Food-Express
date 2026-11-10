import 'dart:math';

/// Enmascarado de datos personales (PII) para que no aparezcan completos en
/// los logs de depuración (Actividad 2).
class Enmascarar {
  Enmascarar._();

  static final RegExp _telefono =
      RegExp(r'(?<!\d)(?:\+?52[\s-]?)?(?:\d[\s-]?){9}\d(?!\d)');
  static final RegExp _correo =
      RegExp(r'([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+\.[A-Za-z]{2,})');

  /// 5512345678 -> ******5678 (solo se ven los últimos 4 dígitos).
  static String telefono(String valor) {
    final digitos = valor.replaceAll(RegExp(r'\D'), '');
    if (digitos.length <= 4) return '*' * digitos.length;
    return '${'*' * (digitos.length - 4)}${digitos.substring(digitos.length - 4)}';
  }

  /// "Calle Hidalgo 100, Col. Centro" -> "Calle Hid***" (solo el inicio).
  static String direccion(String valor) {
    final limpio = valor.trim();
    if (limpio.length <= 6) return '***';
    return '${limpio.substring(0, min(9, limpio.length))}***';
  }

  /// Oculta teléfonos y correos dentro de cualquier mensaje de log.
  static String texto(String mensaje) {
    final sinTelefonos =
        mensaje.replaceAllMapped(_telefono, (m) => telefono(m.group(0)!));
    return sinTelefonos.replaceAllMapped(
      _correo,
      (m) => '${m.group(1)}***${m.group(2)}',
    );
  }
}
