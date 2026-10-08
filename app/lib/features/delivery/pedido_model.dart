class Pedido {
  final int id;
  final int clienteId;
  final int restauranteId;
  final String restaurante;
  final String estado;
  final double total;
  final String fechaCreacion;

  Pedido({
    required this.id,
    required this.clienteId,
    required this.restauranteId,
    required this.restaurante,
    required this.estado,
    required this.total,
    required this.fechaCreacion,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    return Pedido(
      id: json['id'],
      clienteId: json['cliente_id'],
      restauranteId: json['restaurante_id'],
      restaurante: json['restaurante'],
      estado: json['estado'],
      total: (json['total'] as num).toDouble(),
      fechaCreacion: json['fecha_creacion'],
    );
  }
}