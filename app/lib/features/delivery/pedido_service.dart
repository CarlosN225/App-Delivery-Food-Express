import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pedido_model.dart';


class PedidoService {
  static const String baseUrl = 'http://127.0.0.1:8000';


  static Future<List<Pedido>> obtenerPedidosDisponibles() async {
    final respuesta = await http.get(
      Uri.parse('$baseUrl/pedidos/disponibles'),
    );

    if (respuesta.statusCode != 200) {
      throw Exception(
        'Error al obtener pedidos: ${respuesta.statusCode}',
      );
    }

    final List<dynamic> datos = jsonDecode(respuesta.body);

    return datos
        .map((pedido) => Pedido.fromJson(pedido))
        .toList();
  }


  static Future<void> aceptarPedido({
    required int pedidoId,
    required int repartidorId,
  }) async {
    final url = Uri.parse(
      '$baseUrl/pedidos/$pedidoId/aceptar'
      '?repartidor_id=$repartidorId',
    );

    final respuesta = await http.put(url);

    if (respuesta.statusCode != 200) {
      throw Exception(
        'No se pudo aceptar el pedido.',
      );
    }
  }


  static Future<void> rechazarPedido(
    int pedidoId,
  ) async {
    final url = Uri.parse(
      '$baseUrl/pedidos/$pedidoId/rechazar',
    );

    final respuesta = await http.put(url);

    if (respuesta.statusCode != 200) {
      throw Exception(
        'No se pudo rechazar el pedido.',
      );
    }
  }
}