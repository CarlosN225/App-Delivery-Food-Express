class Restaurante {
  final int id;
  final String nombre;
  final String? direccion;
  final String? categoria;
  final String? latitud;
  final String? longitud;
  final double distanciaKm;

  Restaurante({
    required this.id,
    required this.nombre,
    this.direccion,
    this.categoria,
    this.latitud,
    this.longitud,
    required this.distanciaKm,
  });

  factory Restaurante.fromJson(Map<String, dynamic> json) {
    return Restaurante(
      id: json['id'],
      nombre: json['nombre'],
      direccion: json['direccion'],
      categoria: json['categoria'],
      latitud: json['latitud'],
      longitud: json['longitud'],
      distanciaKm: (json['distancia_km'] as num).toDouble(),
    );
  }
}
class Producto {
  final int id;
  final int restauranteId;
  final String nombre;
  final String? descripcion;
  final double precio;
  final String? categoria;
  final String? imagen;

  Producto({
    required this.id,
    required this.restauranteId,
    required this.nombre,
    this.descripcion,
    required this.precio,
    this.categoria,
    this.imagen,
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'],
      restauranteId: json['restaurante_id'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      precio: (json['precio'] as num).toDouble(),
      categoria: json['categoria'],
      imagen: json['imagen'],
    );
  }
}