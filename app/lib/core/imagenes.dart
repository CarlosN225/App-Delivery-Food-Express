import 'package:flutter/material.dart';

import '../features/restaurants/restaurant_model.dart';

/// Fotos y íconos de productos, compartidos por el menú y el carrito.
///
/// La foto de un producto se busca, en orden, en:
///   1. la URL (http...) que venga en el campo `imagen` del producto;
///   2. el archivo que venga en `imagen`, dentro de assets/images/productos/;
///   3. assets/images/productos/<nombre-del-producto>.jpg | .png | .webp
/// Si no hay ninguna, se muestra un recuadro menta con un ícono.
class Imagenes {
  Imagenes._();

  static const Color _turquesa = Color(0xFF0AA89A);
  static const Color _menta = Color(0xFFE5F5F3);

  static String sinAcentos(String texto) {
    return texto
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  /// "Burger pollo crujiente" -> "burger-pollo-crujiente"
  static String slug(String texto) {
    return sinAcentos(texto)
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static List<String> fotosDeProducto(Producto p) {
    final nombre = slug(p.nombre);
    final campo = (p.imagen ?? '').trim();
    return [
      if (campo.startsWith('http')) campo,
      if (campo.isNotEmpty && !campo.startsWith('http'))
        'assets/images/productos/$campo',
      'assets/images/productos/$nombre.jpg',
      'assets/images/productos/$nombre.png',
      'assets/images/productos/$nombre.webp',
    ];
  }

  /// Prueba cada imagen en orden; si ninguna existe, muestra [respaldo].
  static Widget primeraImagen(
    List<String> rutas,
    Widget respaldo, {
    BoxFit ajuste = BoxFit.cover,
  }) {
    if (rutas.isEmpty) return respaldo;
    final ruta = rutas.first;
    final resto = rutas.sublist(1);
    Widget siguiente(BuildContext _, Object __, StackTrace? ___) =>
        primeraImagen(resto, respaldo, ajuste: ajuste);

    return ruta.startsWith('http')
        ? Image.network(ruta, fit: ajuste, errorBuilder: siguiente)
        : Image.asset(ruta, fit: ajuste, errorBuilder: siguiente);
  }

  /// Ícono del producto según su nombre o categoría (cuando no hay foto).
  static IconData iconoDeProducto(Producto p) {
    final t = sinAcentos('${p.nombre} ${p.categoria ?? ''}');

    bool tiene(List<String> palabras) => palabras.any(t.contains);

    if (tiene(['hamburg', 'burger'])) return Icons.lunch_dining_outlined;
    if (tiene(['pizza'])) return Icons.local_pizza_outlined;
    if (tiene(['sushi', 'roll', 'nigiri'])) return Icons.set_meal_outlined;
    if (tiene(['ramen', 'sopa', 'caldo'])) return Icons.ramen_dining_outlined;
    if (tiene(['helado', 'nieve'])) return Icons.icecream_outlined;
    if (tiene(['pastel', 'brownie', 'postre', 'pay', 'flan', 'cheesecake'])) {
      return Icons.cake_outlined;
    }
    if (tiene(['pan ', 'dona', 'galleta', 'croissant'])) {
      return Icons.bakery_dining_outlined;
    }
    if (tiene(['cafe', 'capuchino', 'latte', 'te '])) {
      return Icons.local_cafe_outlined;
    }
    if (tiene(['bebida', 'agua', 'refresco', 'jugo', 'limonada', 'jamaica'])) {
      return Icons.local_drink_outlined;
    }
    if (tiene(['ensalada', 'vegetal'])) return Icons.eco_outlined;
    if (tiene(['alitas', 'pollo', 'filete', 'brocheta'])) {
      return Icons.kebab_dining_outlined;
    }
    if (tiene(['taco', 'quesadilla', 'chilaquiles', 'torta'])) {
      return Icons.restaurant_outlined;
    }
    return Icons.fastfood_outlined;
  }

  /// Foto del producto que llena todo su espacio (la tarjeta le da el tamaño).
  static Widget fotoDeProducto(Producto p, {double tamanoIcono = 48}) {
    return primeraImagen(
      fotosDeProducto(p),
      Container(
        color: _menta,
        alignment: Alignment.center,
        child: Icon(iconoDeProducto(p), color: _turquesa, size: tamanoIcono),
      ),
    );
  }
}
