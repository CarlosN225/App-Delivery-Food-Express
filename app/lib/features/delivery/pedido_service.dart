import '../../core/api_client.dart';
import 'pedido_model.dart';

/// Llamadas al backend para pedidos, pagos y ruta (Sprint 3).
/// Todas requieren el token de la sesión.
class PedidoService {
  // ---------------------------------------------------------------- cliente

  static Future<Cotizacion> cotizar(
    String token, {
    required int restauranteId,
    required List<Map<String, int>> items,
    required double latitud,
    required double longitud,
  }) async {
    final datos = await ApiClient.post(
      '/pedidos/cotizar',
      token: token,
      body: {
        'restaurante_id': restauranteId,
        'items': items,
        'latitud_entrega': latitud,
        'longitud_entrega': longitud,
      },
    );
    return Cotizacion.fromJson(datos as Map<String, dynamic>);
  }

  static Future<Pedido> crearPedido(
    String token, {
    required int restauranteId,
    required List<Map<String, int>> items,
    required String direccion,
    required double latitud,
    required double longitud,
    required String metodoPago, // 'mercado_pago' | 'efectivo'
  }) async {
    final datos = await ApiClient.post(
      '/pedidos',
      token: token,
      body: {
        'restaurante_id': restauranteId,
        'items': items,
        'direccion_entrega': direccion,
        'latitud_entrega': latitud,
        'longitud_entrega': longitud,
        'metodo_pago': metodoPago,
      },
    );
    return Pedido.fromJson(datos as Map<String, dynamic>);
  }

  static Future<List<Pedido>> misPedidos(String token) async {
    final datos = await ApiClient.get('/pedidos/mis-pedidos', token: token);
    return (datos as List<dynamic>)
        .map((p) => Pedido.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  static Future<void> cancelarPedido(String token, int pedidoId) async {
    await ApiClient.post('/pedidos/$pedidoId/cancelar', token: token);
  }

  // ------------------------------------------------------------------ pagos

  static Future<PreferenciaPago> crearPreferenciaPago(
    String token,
    int pedidoId,
  ) async {
    final datos = await ApiClient.post(
      '/pagos/pedido/$pedidoId/preferencia',
      token: token,
    );
    return PreferenciaPago.fromJson(datos as Map<String, dynamic>);
  }

  /// Pide al backend confirmar el pago con Mercado Pago.
  /// Devuelve el estado del pago: pendiente | pagado | rechazado | contra_entrega.
  static Future<String?> verificarPago(String token, int pedidoId) async {
    final datos = await ApiClient.post(
      '/pagos/pedido/$pedidoId/verificar',
      token: token,
    );
    return (datos as Map<String, dynamic>)['estado_pago'] as String?;
  }

  // ------------------------------------------------------------- repartidor

  static Map<String, String>? _posicion(double? latitud, double? longitud) {
    if (latitud == null || longitud == null) return null;
    return {'latitud': '$latitud', 'longitud': '$longitud'};
  }

  static Future<List<PedidoDisponible>> pedidosDisponibles(
    String token, {
    double? latitud,
    double? longitud,
  }) async {
    final datos = await ApiClient.get(
      '/pedidos/disponibles',
      token: token,
      query: _posicion(latitud, longitud),
    );
    return (datos as List<dynamic>)
        .map((p) => PedidoDisponible.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Pedido>> pedidosActivos(String token) async {
    final datos = await ApiClient.get('/pedidos/activos', token: token);
    return (datos as List<dynamic>)
        .map((p) => Pedido.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  static Future<void> aceptarPedido(String token, int pedidoId) async {
    await ApiClient.put('/pedidos/$pedidoId/aceptar', token: token);
  }

  static Future<void> rechazarPedido(String token, int pedidoId) async {
    await ApiClient.put('/pedidos/$pedidoId/rechazar', token: token);
  }

  /// Avanza el pedido: recogido -> en_camino -> entregado.
  static Future<Pedido> cambiarEstado(
    String token,
    int pedidoId,
    String estado,
  ) async {
    final datos = await ApiClient.put(
      '/pedidos/$pedidoId/estado',
      token: token,
      body: {'estado': estado},
    );
    return Pedido.fromJson(datos as Map<String, dynamic>);
  }

  static Future<RutaOptima> rutaOptima(
    String token, {
    double? latitud,
    double? longitud,
  }) async {
    final datos = await ApiClient.get(
      '/pedidos/ruta-optima',
      token: token,
      query: _posicion(latitud, longitud),
    );
    return RutaOptima.fromJson(datos as Map<String, dynamic>);
  }
}
