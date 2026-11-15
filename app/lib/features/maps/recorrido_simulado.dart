import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Camino a lo largo de una línea (la ruta por calles de Google): dado cuántos
/// metros se han recorrido, devuelve el punto exacto donde va el repartidor.
/// Lo usa la demostración para mover la moto sobre las líneas del mapa.
class RecorridoSimulado {
  final List<LatLng> puntos;
  final List<double> _acumulado = [0];

  RecorridoSimulado(List<LatLng> puntos) : puntos = List.unmodifiable(puntos) {
    for (var i = 1; i < this.puntos.length; i++) {
      _acumulado.add(_acumulado.last + metrosEntre(this.puntos[i - 1], this.puntos[i]));
    }
  }

  double get longitudM => _acumulado.isEmpty ? 0 : _acumulado.last;

  /// Punto a [metros] del inicio (se queda en los extremos si se pasa).
  LatLng posicionEn(double metros) {
    if (puntos.isEmpty) return const LatLng(0, 0);
    if (puntos.length == 1 || metros <= 0) return puntos.first;
    if (metros >= longitudM) return puntos.last;

    var i = 1;
    while (i < _acumulado.length - 1 && _acumulado[i] < metros) {
      i++;
    }
    final tramo = _acumulado[i] - _acumulado[i - 1];
    final t = tramo <= 0 ? 0.0 : (metros - _acumulado[i - 1]) / tramo;
    final a = puntos[i - 1];
    final b = puntos[i];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Distancia entre dos coordenadas, en metros (fórmula de haversine).
  static double metrosEntre(LatLng a, LatLng b) {
    const radioTierra = 6371000.0;
    double rad(double grados) => grados * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * radioTierra * math.asin(math.sqrt(h.toDouble()));
  }
}
