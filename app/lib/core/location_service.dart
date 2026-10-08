import 'package:geolocator/geolocator.dart';

class LocationService {
  // Obtiene la ubicación actual del dispositivo
  static Future<Position?> obtenerUbicacionActual() async {
    // 1. Comprobar si el GPS/servicio de ubicación está activo
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      print('El servicio de ubicación está desactivado.');
      return null;
    }

    // 2. Comprobar el permiso de ubicación
    LocationPermission permiso = await Geolocator.checkPermission();

    // 3. Si no hay permiso, solicitarlo
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();

      if (permiso == LocationPermission.denied) {
        print('El usuario rechazó el permiso de ubicación.');
        return null;
      }
    }

    // 4. Si el permiso fue rechazado permanentemente
    if (permiso == LocationPermission.deniedForever) {
      print('El permiso de ubicación fue rechazado permanentemente.');
      return null;
    }

    // 5. Obtener la ubicación actual
    Position posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return posicion;
  }
}