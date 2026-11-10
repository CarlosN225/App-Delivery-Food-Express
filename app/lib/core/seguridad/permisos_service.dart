import 'package:geolocator/geolocator.dart';

/// Estado de un permiso crítico.
enum EstadoPermiso { concedido, servicioApagado, denegado, denegadoParaSiempre }

/// Validación de permisos críticos (Actividad 3): se comprueba que la app
/// tenga acceso al GPS ANTES de ejecutar funciones sensibles (buscar
/// restaurantes cercanos, reportar la ubicación del repartidor, etc.).
///
/// La cámara solo se validaría si la app tuviera escaneo de QR; hoy no lo
/// tiene, así que no se pide ese permiso (se pide únicamente lo necesario).
class PermisosService {
  PermisosService._();

  /// Comprueba (y si hace falta, solicita) el permiso de ubicación.
  static Future<EstadoPermiso> ubicacion({bool solicitar = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return EstadoPermiso.servicioApagado;
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied && solicitar) {
      permiso = await Geolocator.requestPermission();
    }

    switch (permiso) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return EstadoPermiso.concedido;
      case LocationPermission.deniedForever:
        return EstadoPermiso.denegadoParaSiempre;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return EstadoPermiso.denegado;
    }
  }

  /// Mensaje listo para mostrar a la persona según el estado.
  static String mensaje(EstadoPermiso estado) {
    switch (estado) {
      case EstadoPermiso.concedido:
        return 'Permiso de ubicación concedido.';
      case EstadoPermiso.servicioApagado:
        return 'El GPS está apagado. Actívalo para continuar.';
      case EstadoPermiso.denegado:
        return 'Necesitamos el permiso de ubicación para continuar.';
      case EstadoPermiso.denegadoParaSiempre:
        return 'El permiso de ubicación está bloqueado. Actívalo en los ajustes del dispositivo.';
    }
  }
}
