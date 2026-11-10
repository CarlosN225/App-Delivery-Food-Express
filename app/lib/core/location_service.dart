import 'package:geolocator/geolocator.dart';

import 'seguridad/permisos_service.dart';
import 'seguridad/registro.dart';

class LocationService {
  // Obtiene la ubicación actual del dispositivo. Antes de leer el GPS se
  // valida el permiso (Actividad 3: validación de permisos críticos).
  static Future<Position?> obtenerUbicacionActual() async {
    final estado = await PermisosService.ubicacion();

    if (estado != EstadoPermiso.concedido) {
      Registro.aviso(PermisosService.mensaje(estado));
      return null;
    }

    // Con el permiso concedido, se obtiene la ubicación actual.
    Position posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return posicion;
  }
}
