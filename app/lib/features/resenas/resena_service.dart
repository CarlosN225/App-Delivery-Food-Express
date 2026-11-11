import '../../core/api_client.dart';

/// Reseña tal como la ve el público en el menú de un restaurante.
class ResenaPublica {
  final String autor;
  final int calificacion;
  final String? comentario;
  final int haceDias;

  ResenaPublica({
    required this.autor,
    required this.calificacion,
    this.comentario,
    required this.haceDias,
  });

  factory ResenaPublica.fromJson(Map<String, dynamic> json) => ResenaPublica(
        autor: (json['autor'] ?? 'Cliente').toString(),
        calificacion: json['calificacion'] as int,
        comentario: json['comentario'] as String?,
        haceDias: (json['hace_dias'] as num?)?.toInt() ?? 0,
      );
}

/// Promedio, total y últimas reseñas de un restaurante.
class ResenasRestaurante {
  final double? promedio;
  final int total;
  final List<ResenaPublica> resenas;

  ResenasRestaurante({this.promedio, required this.total, required this.resenas});

  factory ResenasRestaurante.fromJson(Map<String, dynamic> json) =>
      ResenasRestaurante(
        promedio: (json['promedio'] as num?)?.toDouble(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        resenas: ((json['resenas'] as List?) ?? [])
            .map((r) => ResenaPublica.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

/// Una reseña que yo ya hice (para saber qué pedidos ya califiqué).
class MiResena {
  final int pedidoId;
  final int calificacionRestaurante;
  final int? calificacionRepartidor;

  MiResena({
    required this.pedidoId,
    required this.calificacionRestaurante,
    this.calificacionRepartidor,
  });

  factory MiResena.fromJson(Map<String, dynamic> json) => MiResena(
        pedidoId: json['pedido_id'] as int,
        calificacionRestaurante: json['calificacion_restaurante'] as int,
        calificacionRepartidor: json['calificacion_repartidor'] as int?,
      );
}

/// Llamadas al backend de reseñas (Sprint 5, historia #28).
class ResenaService {
  static Future<void> crear(
    String token, {
    required int pedidoId,
    required int calificacionRestaurante,
    int? calificacionRepartidor,
    String? comentario,
  }) async {
    await ApiClient.post(
      '/resenas',
      token: token,
      body: {
        'pedido_id': pedidoId,
        'calificacion_restaurante': calificacionRestaurante,
        if (calificacionRepartidor != null)
          'calificacion_repartidor': calificacionRepartidor,
        if (comentario != null && comentario.trim().isNotEmpty)
          'comentario': comentario.trim(),
      },
    );
  }

  static Future<List<MiResena>> mias(String token) async {
    final datos = await ApiClient.get('/resenas/mias', token: token);
    return (datos as List)
        .map((r) => MiResena.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<ResenasRestaurante> deRestaurante(int restauranteId) async {
    final datos = await ApiClient.get('/resenas/restaurante/$restauranteId');
    return ResenasRestaurante.fromJson(datos as Map<String, dynamic>);
  }
}
