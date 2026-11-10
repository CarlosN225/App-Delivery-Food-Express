import 'package:flutter/foundation.dart';

import 'enmascarar.dart';
import 'entorno.dart';

/// Registro de eventos según el entorno (Actividad 3) y sin datos personales
/// (Actividad 2):
///  - DEBUG: se escribe en consola, con teléfonos y correos enmascarados.
///  - RELEASE: no se escribe nada (así no se filtra información en producción).
class Registro {
  Registro._();

  static void info(String mensaje) => _escribir('INFO', mensaje);
  static void aviso(String mensaje) => _escribir('AVISO', mensaje);
  static void error(String mensaje) => _escribir('ERROR', mensaje);

  static void _escribir(String nivel, String mensaje) {
    if (!Entorno.esDebug) return;
    debugPrint('[$nivel] ${Enmascarar.texto(mensaje)}');
  }

  /// Hace que TODOS los `debugPrint` que ya existen en la app pasen por el
  /// mismo filtro (solo en DEBUG y con datos enmascarados). Se llama una vez
  /// en `main()`; no hay que editar cada pantalla.
  static void instalar() {
    debugPrint = (String? mensaje, {int? wrapWidth}) {
      if (!Entorno.esDebug || mensaje == null) return;
      debugPrintThrottled(Enmascarar.texto(mensaje), wrapWidth: wrapWidth);
    };
  }
}
