import '../../core/api_client.dart';

/// Restaurante tal como lo ve el panel administrativo (Sprint 4, #16).
class RestauranteAdmin {
  final int id;
  final String nombre;
  final String? direccion;
  final String? categoria;
  final double? latitud;
  final double? longitud;
  final int totalProductos;

  RestauranteAdmin({
    required this.id,
    required this.nombre,
    this.direccion,
    this.categoria,
    this.latitud,
    this.longitud,
    this.totalProductos = 0,
  });

  factory RestauranteAdmin.fromJson(Map<String, dynamic> json) {
    return RestauranteAdmin(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      direccion: json['direccion'] as String?,
      categoria: json['categoria'] as String?,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      totalProductos: json['total_productos'] as int? ?? 0,
    );
  }
}

/// Usuario tal como lo ve el panel administrativo (Sprint 4, #17).
class UsuarioAdmin {
  final int id;
  final String nombre;
  final String correo;
  final String rol;
  final bool activo;

  UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.activo,
  });

  factory UsuarioAdmin.fromJson(Map<String, dynamic> json) {
    return UsuarioAdmin(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      correo: json['correo'] as String,
      rol: json['rol'] as String,
      activo: json['activo'] as bool? ?? true,
    );
  }
}

String nombreRol(String rol) => switch (rol) {
      'cliente' => 'Cliente',
      'repartidor' => 'Repartidor',
      'administrador' => 'Administrador',
      _ => rol,
    };

class AdminService {
  // ---------------------------------------------------- restaurantes (#16)

  static Map<String, dynamic> _cuerpo({
    required String nombre,
    String? direccion,
    String? categoria,
    double? latitud,
    double? longitud,
  }) =>
      {
        'nombre': nombre,
        'direccion': direccion,
        'categoria': categoria,
        'latitud': latitud,
        'longitud': longitud,
      };

  static Future<List<RestauranteAdmin>> restaurantes(String token) async {
    final datos = await ApiClient.get('/admin/restaurantes', token: token);
    return (datos as List<dynamic>)
        .map((r) => RestauranteAdmin.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<void> crearRestaurante(
    String token, {
    required String nombre,
    String? direccion,
    String? categoria,
    double? latitud,
    double? longitud,
  }) async {
    await ApiClient.post(
      '/admin/restaurantes',
      token: token,
      body: _cuerpo(
        nombre: nombre,
        direccion: direccion,
        categoria: categoria,
        latitud: latitud,
        longitud: longitud,
      ),
    );
  }

  static Future<void> editarRestaurante(
    String token,
    int id, {
    required String nombre,
    String? direccion,
    String? categoria,
    double? latitud,
    double? longitud,
  }) async {
    await ApiClient.put(
      '/admin/restaurantes/$id',
      token: token,
      body: _cuerpo(
        nombre: nombre,
        direccion: direccion,
        categoria: categoria,
        latitud: latitud,
        longitud: longitud,
      ),
    );
  }

  static Future<void> eliminarRestaurante(String token, int id) async {
    await ApiClient.delete('/admin/restaurantes/$id', token: token);
  }

  // ------------------------------------------- usuarios y repartidores (#17)

  static Future<List<UsuarioAdmin>> usuarios(
    String token, {
    String? rol,
    String? busqueda,
  }) async {
    final texto = busqueda?.trim() ?? '';
    final datos = await ApiClient.get(
      '/admin/usuarios',
      token: token,
      query: {
        if (rol != null) 'rol': rol,
        if (texto.isNotEmpty) 'q': texto,
      },
    );
    return (datos as List<dynamic>)
        .map((u) => UsuarioAdmin.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  static Future<UsuarioAdmin> cambiarActivo(
    String token,
    int id,
    bool activo,
  ) async {
    final datos = await ApiClient.put(
      '/admin/usuarios/$id/activo',
      token: token,
      body: {'activo': activo},
    );
    return UsuarioAdmin.fromJson(datos as Map<String, dynamic>);
  }

  static Future<UsuarioAdmin> cambiarRol(
    String token,
    int id,
    String rol,
  ) async {
    final datos = await ApiClient.put(
      '/admin/usuarios/$id/rol',
      token: token,
      body: {'rol': rol},
    );
    return UsuarioAdmin.fromJson(datos as Map<String, dynamic>);
  }
}