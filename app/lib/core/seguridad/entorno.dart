import 'package:flutter/foundation.dart';

/// Modo de compilación (el equivalente a BuildConfig.DEBUG / RELEASE).
/// Flutter lo decide solo según cómo se compile:
///   flutter run                 -> DEBUG
///   flutter build apk --release -> RELEASE
enum ModoCompilacion { debug, release }

/// Canal por el que se entrega la app. Se elige al compilar:
///   flutter build apk --dart-define=CANAL=interno
///   flutter build apk --dart-define=CANAL=privado
///   flutter build apk --dart-define=CANAL=publico
enum CanalDistribucion { interno, privadoEnterprise, publico }

class Entorno {
  Entorno._();

  /// DEBUG mientras se desarrolla, RELEASE en la versión que se entrega.
  static ModoCompilacion get modo =>
      kReleaseMode ? ModoCompilacion.release : ModoCompilacion.debug;

  static bool get esDebug => modo == ModoCompilacion.debug;

  /// Canal activo (por defecto, interno).
  static CanalDistribucion get canal =>
      canalDesdeTexto(const String.fromEnvironment('CANAL', defaultValue: 'interno'));

  static CanalDistribucion canalDesdeTexto(String texto) {
    switch (texto.trim().toLowerCase()) {
      case 'privado':
      case 'enterprise':
      case 'privado_enterprise':
        return CanalDistribucion.privadoEnterprise;
      case 'publico':
      case 'público':
      case 'tienda':
        return CanalDistribucion.publico;
      default:
        return CanalDistribucion.interno;
    }
  }

  /// Ruta de despliegue según el canal (el `when` de Kotlin es `switch` en Dart).
  static String rutaDeDespliegue(CanalDistribucion canal) {
    switch (canal) {
      case CanalDistribucion.interno:
        return 'APK firmado con llave de depuración, compartido por enlace al equipo (pruebas internas).';
      case CanalDistribucion.privadoEnterprise:
        return 'APK/AAB firmado con llave propia, distribuido por MDM o enlace privado a la organización.';
      case CanalDistribucion.publico:
        return 'AAB firmado y publicado en Google Play (producción), sin datos de demostración.';
    }
  }

  /// Solo el canal público debe ocultar los datos y herramientas de demostración.
  static bool permiteHerramientasDemo(CanalDistribucion canal) {
    switch (canal) {
      case CanalDistribucion.interno:
      case CanalDistribucion.privadoEnterprise:
        return true;
      case CanalDistribucion.publico:
        return false;
    }
  }

  static String get resumen =>
      'modo ${modo.name.toUpperCase()} · canal ${canal.name} · ${rutaDeDespliegue(canal)}';
}
