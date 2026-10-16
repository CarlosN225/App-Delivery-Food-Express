double _numero(dynamic valor) =>
    valor == null ? 0.0 : (double.tryParse(valor.toString()) ?? 0.0);

double? _numeroOpcional(dynamic valor) =>
    valor == null ? null : double.tryParse(valor.toString());

/// Texto en español para cada estado del pedido.
String textoEstado(String estado) {
  switch (estado) {
    case 'pendiente':
      return 'Pendiente';
    case 'aceptado':
      return 'Aceptado';
    case 'recogido':
      return 'Recogido';
    case 'en_camino':
      return 'En camino';
    case 'entregado':
      return 'Entregado';
    case 'cancelado':
      return 'Cancelado';
    default:
      return estado;
  }
}

class ItemPedido {
  final int? productoId;
  final String nombre;
  final int cantidad;
  final double precioUnitario;
  final double importe;

  ItemPedido({
    this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.importe,
  });

  factory ItemPedido.fromJson(Map<String, dynamic> json) {
    return ItemPedido(
      productoId: json['producto_id'] as int?,
      nombre: json['nombre'] as String,
      cantidad: json['cantidad'] as int,
      precioUnitario: _numero(json['precio_unitario']),
      importe: _numero(json['importe']),
    );
  }
}

class Pedido {
  final int id;
  final int clienteId;
  final int? repartidorId;
  final int restauranteId;
  final String restaurante;
  final String? restauranteDireccion;
  final double? restauranteLatitud;
  final double? restauranteLongitud;
  final String estado;
  final String? estadoPago;
  final String? metodoPago;
  final double subtotal;
  final double costoEnvio;
  final double total;
  final String? direccionEntrega;
  final double? latitudEntrega;
  final double? longitudEntrega;
  final List<ItemPedido> items;
  final String? fechaCreacion;

  Pedido({
    required this.id,
    required this.clienteId,
    this.repartidorId,
    required this.restauranteId,
    required this.restaurante,
    this.restauranteDireccion,
    this.restauranteLatitud,
    this.restauranteLongitud,
    required this.estado,
    this.estadoPago,
    this.metodoPago,
    required this.subtotal,
    required this.costoEnvio,
    required this.total,
    this.direccionEntrega,
    this.latitudEntrega,
    this.longitudEntrega,
    this.items = const [],
    this.fechaCreacion,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .map((i) => ItemPedido.fromJson(i as Map<String, dynamic>))
        .toList();
    return Pedido(
      id: json['id'] as int,
      clienteId: json['cliente_id'] as int,
      repartidorId: json['repartidor_id'] as int?,
      restauranteId: json['restaurante_id'] as int,
      restaurante: json['restaurante'] as String,
      restauranteDireccion: json['restaurante_direccion'] as String?,
      restauranteLatitud: _numeroOpcional(json['restaurante_latitud']),
      restauranteLongitud: _numeroOpcional(json['restaurante_longitud']),
      estado: json['estado'] as String,
      estadoPago: json['estado_pago'] as String?,
      metodoPago: json['metodo_pago'] as String?,
      subtotal: _numero(json['subtotal']),
      costoEnvio: _numero(json['costo_envio']),
      total: _numero(json['total']),
      direccionEntrega: json['direccion_entrega'] as String?,
      latitudEntrega: _numeroOpcional(json['latitud_entrega']),
      longitudEntrega: _numeroOpcional(json['longitud_entrega']),
      items: items,
      fechaCreacion: json['fecha_creacion'] as String?,
    );
  }

  /// Mercado Pago sin pagar (o con pago rechazado) y aún sin repartidor.
  bool get pagoPendiente =>
      metodoPago == 'mercado_pago' &&
      (estadoPago == 'pendiente' || estadoPago == 'rechazado') &&
      estado == 'pendiente';

  /// El repartidor debe cobrar este monto en efectivo al entregar.
  bool get cobraEnEfectivo =>
      metodoPago == 'efectivo' && estadoPago == 'contra_entrega';

  bool get activo =>
      estado == 'aceptado' || estado == 'recogido' || estado == 'en_camino';

  String get metodoPagoTexto =>
      metodoPago == 'mercado_pago' ? 'Mercado Pago' : 'Efectivo';
}

/// Pedido que aún espera repartidor (panel del repartidor).
class PedidoDisponible {
  final int id;
  final int restauranteId;
  final String restaurante;
  final String? restauranteDireccion;
  final String? direccionEntrega;
  final String? metodoPago;
  final String? estadoPago;
  final double total;
  final double? distanciaKm; // repartidor -> restaurante
  final double? distanciaEntregaKm; // restaurante -> cliente
  final int? minutosEstimados;

  PedidoDisponible({
    required this.id,
    required this.restauranteId,
    required this.restaurante,
    this.restauranteDireccion,
    this.direccionEntrega,
    this.metodoPago,
    this.estadoPago,
    required this.total,
    this.distanciaKm,
    this.distanciaEntregaKm,
    this.minutosEstimados,
  });

  factory PedidoDisponible.fromJson(Map<String, dynamic> json) {
    return PedidoDisponible(
      id: json['id'] as int,
      restauranteId: json['restaurante_id'] as int,
      restaurante: json['restaurante'] as String,
      restauranteDireccion: json['restaurante_direccion'] as String?,
      direccionEntrega: json['direccion_entrega'] as String?,
      metodoPago: json['metodo_pago'] as String?,
      estadoPago: json['estado_pago'] as String?,
      total: _numero(json['total']),
      distanciaKm: _numeroOpcional(json['distancia_km']),
      distanciaEntregaKm: _numeroOpcional(json['distancia_entrega_km']),
      minutosEstimados: (json['minutos_estimados'] as num?)?.toInt(),
    );
  }

  bool get cobraEnEfectivo => metodoPago == 'efectivo';
}

/// Una parada de la ruta: recoger en un restaurante o entregar a un cliente.
class Tramo {
  final int pedidoId;
  final String tipo; // 'recoger' | 'entregar'
  final String destino;
  final double latitud;
  final double longitud;
  final double distanciaKm;
  final int minutos;

  Tramo({
    required this.pedidoId,
    required this.tipo,
    required this.destino,
    required this.latitud,
    required this.longitud,
    required this.distanciaKm,
    required this.minutos,
  });

  factory Tramo.fromJson(Map<String, dynamic> json) {
    return Tramo(
      pedidoId: json['pedido_id'] as int,
      tipo: json['tipo'] as String,
      destino: json['destino'] as String,
      latitud: _numero(json['latitud']),
      longitud: _numero(json['longitud']),
      distanciaKm: _numero(json['distancia_km']),
      minutos: (json['minutos'] as num).toInt(),
    );
  }
}

class RutaOptima {
  final List<Tramo> tramos;
  final double distanciaTotalKm;
  final int minutosTotal;

  RutaOptima({
    required this.tramos,
    required this.distanciaTotalKm,
    required this.minutosTotal,
  });

  factory RutaOptima.fromJson(Map<String, dynamic> json) {
    return RutaOptima(
      tramos: (json['tramos'] as List<dynamic>? ?? [])
          .map((t) => Tramo.fromJson(t as Map<String, dynamic>))
          .toList(),
      distanciaTotalKm: _numero(json['distancia_total_km']),
      minutosTotal: (json['minutos_total'] as num? ?? 0).toInt(),
    );
  }
}

/// Subtotal, envío y total calculados por el backend.
class Cotizacion {
  final double subtotal;
  final double costoEnvio;
  final double total;
  final double? distanciaKm;

  Cotizacion({
    required this.subtotal,
    required this.costoEnvio,
    required this.total,
    this.distanciaKm,
  });

  factory Cotizacion.fromJson(Map<String, dynamic> json) {
    return Cotizacion(
      subtotal: _numero(json['subtotal']),
      costoEnvio: _numero(json['costo_envio']),
      total: _numero(json['total']),
      distanciaKm: _numeroOpcional(json['distancia_km']),
    );
  }
}

/// Respuesta de crear el enlace de pago de Mercado Pago.
class PreferenciaPago {
  final String modo; // 'mercadopago' | 'demo'
  final String initPoint;

  PreferenciaPago({required this.modo, required this.initPoint});

  factory PreferenciaPago.fromJson(Map<String, dynamic> json) {
    return PreferenciaPago(
      modo: json['modo'] as String,
      initPoint: json['init_point'] as String,
    );
  }

  bool get esDemo => modo == 'demo';
}
