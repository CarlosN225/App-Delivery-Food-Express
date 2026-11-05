import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_client.dart';

/// Ruta por calles de un pedido, calculada por el backend con la Routes API
/// de Google. Si Google no responde, el backend manda una línea recta y
/// [fuente] vale 'linea_recta'.
class RutaMapa {
  final String fuente; // 'google' | 'linea_recta'
  final int distanciaM;
  final int duracionS;
  final List<LatLng> puntos;

  /// Un trazo por tramo: ir al restaurante y/o llevar al cliente.
  final List<TramoRuta> tramos;

  const RutaMapa({
    required this.fuente,
    required this.distanciaM,
    required this.duracionS,
    required this.puntos,
    this.tramos = const [],
  });

  bool get esGoogle => fuente == 'google';

  factory RutaMapa.fromJson(Map<String, dynamic> json) {
    return RutaMapa(
      fuente: json['fuente'] as String? ?? 'linea_recta',
      distanciaM: (json['distancia_m'] as num?)?.toInt() ?? 0,
      duracionS: (json['duracion_s'] as num?)?.toInt() ?? 0,
      puntos: _puntos(json['puntos']),
      tramos: ((json['tramos'] as List<dynamic>?) ?? const [])
          .map((t) => TramoRuta.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

List<LatLng> _puntos(dynamic crudos) {
  return ((crudos as List<dynamic>?) ?? const []).map((p) {
    final par = p as List<dynamic>;
    return LatLng((par[0] as num).toDouble(), (par[1] as num).toDouble());
  }).toList();
}

/// Un tramo de la ruta: 'hacia_restaurante' o 'hacia_cliente'.
class TramoRuta {
  final String tipo;
  final int distanciaM;
  final int duracionS;
  final List<LatLng> puntos;

  const TramoRuta({
    required this.tipo,
    required this.distanciaM,
    required this.duracionS,
    required this.puntos,
  });

  bool get haciaRestaurante => tipo == 'hacia_restaurante';

  factory TramoRuta.fromJson(Map<String, dynamic> json) {
    return TramoRuta(
      tipo: json['tipo'] as String? ?? 'hacia_cliente',
      distanciaM: (json['distancia_m'] as num?)?.toInt() ?? 0,
      duracionS: (json['duracion_s'] as num?)?.toInt() ?? 0,
      puntos: _puntos(json['puntos']),
    );
  }
}

/// Resultado de convertir una dirección escrita en coordenadas.
class DireccionGeocodificada {
  final double latitud;
  final double longitud;
  final String direccionFormateada;
  final String? precision; // ROOFTOP, RANGE_INTERPOLATED, GEOMETRIC_CENTER...
  final bool coincidenciaParcial;

  const DireccionGeocodificada({
    required this.latitud,
    required this.longitud,
    required this.direccionFormateada,
    this.precision,
    this.coincidenciaParcial = false,
  });

  factory DireccionGeocodificada.fromJson(Map<String, dynamic> json) {
    return DireccionGeocodificada(
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccionFormateada: json['direccion_formateada'] as String? ?? '',
      precision: json['precision'] as String?,
      coincidenciaParcial: json['coincidencia_parcial'] as bool? ?? false,
    );
  }
}

/// Llamadas al backend para los mapas (Sprint 5). La app nunca llama a
/// Google para esto: el backend usa la llave del servidor.
class MapasService {
  /// Dirección escrita -> coordenadas (Geocoding API).
  static Future<DireccionGeocodificada> geocodificar(
    String token,
    String direccion,
  ) async {
    final datos = await ApiClient.post(
      '/mapas/geocodificar',
      token: token,
      body: {'direccion': direccion},
    );
    return DireccionGeocodificada.fromJson(datos as Map<String, dynamic>);
  }

  /// Punto del mapa -> dirección (cuando el cliente mueve el pin).
  static Future<String> direccionDe(
    String token,
    double latitud,
    double longitud,
  ) async {
    final datos = await ApiClient.post(
      '/mapas/direccion',
      token: token,
      body: {'latitud': latitud, 'longitud': longitud},
    );
    return (datos as Map<String, dynamic>)['direccion_formateada'] as String? ??
        '';
  }

  /// Trazo por calles del pedido (Routes API). Si el repartidor manda su
  /// posición en vivo ([desde]), el trazo sale de donde está.
  static Future<RutaMapa> rutaDePedido(
    String token,
    int pedidoId, {
    LatLng? desde,
  }) async {
    final datos = await ApiClient.get(
      '/mapas/ruta/$pedidoId',
      token: token,
      query: desde == null
          ? null
          : {
              'lat': desde.latitude.toStringAsFixed(6),
              'lng': desde.longitude.toStringAsFixed(6),
            },
    );
    return RutaMapa.fromJson(datos as Map<String, dynamic>);
  }
}
