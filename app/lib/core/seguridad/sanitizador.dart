import 'package:flutter/services.dart';

/// Sanitización de entradas con Regex (Actividad 2): filtra los caracteres
/// peligrosos que se usan en inyección SQL y XSS antes de usar el texto de
/// una búsqueda. (La defensa real contra SQL está en el backend, que usa
/// consultas parametrizadas; esto es una capa extra.)
class Sanitizador {
  Sanitizador._();

  static const int maxBusqueda = 60;

  static final RegExp _etiquetas = RegExp(r'<[^>]*>');
  static final RegExp _comentariosSql = RegExp(r'(--|/\*|\*/|;)');
  // Solo letras (con acentos y ñ), números, espacio, guion, punto y &.
  static final RegExp _noPermitido =
      RegExp(r'[^\p{L}\p{N}\s\-.&]', unicode: true);
  static final RegExp _espacios = RegExp(r'\s+');

  /// Texto seguro para filtrar restaurantes.
  static String busqueda(String entrada) {
    var texto = entrada.replaceAll(_etiquetas, ' ');
    texto = texto.replaceAll(_comentariosSql, ' ');
    texto = texto.replaceAll(_noPermitido, '');
    texto = texto.replaceAll(_espacios, ' ').trimLeft();
    if (texto.length > maxBusqueda) texto = texto.substring(0, maxBusqueda);
    return texto;
  }

  /// Bloquea los caracteres peligrosos mientras la persona escribe.
  static final List<TextInputFormatter> formateadoresBusqueda = [
    FilteringTextInputFormatter.allow(
      RegExp(r'[\p{L}\p{N}\s\-.&]', unicode: true),
    ),
    LengthLimitingTextInputFormatter(maxBusqueda),
  ];
}
