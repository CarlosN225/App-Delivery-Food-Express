import '../../core/api_client.dart';

/// Aviso para el usuario (Sprint 4, historia #15).
class Notificacion {
  final int id;
  final int? pedidoId;
  final String titulo;
  final String mensaje;
  final bool leida;
  final int haceSegundos;

  Notificacion({
    required this.id,
    this.pedidoId,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    required this.haceSegundos,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'] as int,
      pedidoId: json['pedido_id'] as int?,
      titulo: json['titulo'] as String,
      mensaje: json['mensaje'] as String,
      leida: json['leida'] as bool? ?? false,
      haceSegundos: json['hace_segundos'] as int? ?? 0,
    );
  }

  Notificacion copiaLeida() => Notificacion(
        id: id,
        pedidoId: pedidoId,
        titulo: titulo,
        mensaje: mensaje,
        leida: true,
        haceSegundos: haceSegundos,
      );
}

/// «Hace un momento», «Hace 5 min», «Hace 2 h»…
String tiempoRelativo(int segundos) {
  if (segundos < 60) return 'Hace un momento';
  final minutos = segundos ~/ 60;
  if (minutos < 60) return 'Hace $minutos min';
  final horas = minutos ~/ 60;
  if (horas < 24) return 'Hace $horas h';
  return 'Hace ${horas ~/ 24} d';
}

class NotificacionService {
  /// Más nuevas primero. Con [desdeId] solo trae las posteriores a ese id.
  static Future<List<Notificacion>> listar(
    String token, {
    int desdeId = 0,
    int limite = 50,
  }) async {
    final datos = await ApiClient.get(
      '/notificaciones',
      token: token,
      query: {'desde_id': '$desdeId', 'limite': '$limite'},
    );
    return (datos as List<dynamic>)
        .map((n) => Notificacion.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  static Future<int> noLeidas(String token) async {
    final datos = await ApiClient.get('/notificaciones/no-leidas', token: token);
    return (datos as Map<String, dynamic>)['no_leidas'] as int;
  }

  static Future<void> marcarLeida(String token, int id) async {
    await ApiClient.put('/notificaciones/$id/leida', token: token);
  }

  static Future<void> marcarTodasLeidas(String token) async {
    await ApiClient.put('/notificaciones/leidas', token: token);
  }
}