import 'dart:convert';

import 'package:http/http.dart' as http;

import 'restaurant_model.dart';

class RestauranteService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<List<Restaurante>> obtenerRestaurantesCercanos({
    required double latitud,
    required double longitud,
    double radioKm = 10,
  }) async {
    final url = Uri.parse(
      '$baseUrl/restaurantes/cercanos'
      '?latitud=$latitud'
      '&longitud=$longitud'
      '&radio_km=$radioKm',
    );

    final respuesta = await http.get(url);

    if (respuesta.statusCode != 200) {
      throw Exception(
        'Error al obtener restaurantes: ${respuesta.statusCode}',
      );
    }

    final List<dynamic> datos = jsonDecode(respuesta.body);

    return datos
        .map((restaurante) => Restaurante.fromJson(restaurante))
        .toList();
  }
  static Future<List<Producto>> obtenerProductosRestaurante(
  int restauranteId,
) async {
  final url = Uri.parse(
    '$baseUrl/productos/restaurante/$restauranteId',
  );

  final respuesta = await http.get(url);

  if (respuesta.statusCode != 200) {
    throw Exception(
      'Error al obtener productos: ${respuesta.statusCode}',
    );
  }

  final List<dynamic> datos = jsonDecode(respuesta.body);

  return datos
      .map((producto) => Producto.fromJson(producto))
      .toList();
}
}