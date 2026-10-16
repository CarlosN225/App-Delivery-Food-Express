import 'package:flutter/foundation.dart';

import '../restaurants/restaurant_model.dart';

/// Una línea del carrito: un producto y cuántas piezas.
class LineaCarrito {
  final Producto producto;
  int cantidad;

  LineaCarrito(this.producto, this.cantidad);

  double get importe => producto.precio * cantidad;
}

/// Carrito de compras (historia #9). Vive en memoria mientras la app está
/// abierta y solo admite productos de un restaurante a la vez.
class CarritoService extends ChangeNotifier {
  /// Carrito compartido por toda la app.
  static final CarritoService instance = CarritoService();

  static const int maxPorProducto = 50; // mismo límite que el backend

  Restaurante? _restaurante;
  final Map<int, LineaCarrito> _lineas = {};

  Restaurante? get restaurante => _restaurante;

  List<LineaCarrito> get lineas => _lineas.values.toList();

  bool get vacio => _lineas.isEmpty;

  int get totalPiezas =>
      _lineas.values.fold(0, (suma, linea) => suma + linea.cantidad);

  double get subtotal =>
      _lineas.values.fold(0.0, (suma, linea) => suma + linea.importe);

  int cantidadDe(int productoId) => _lineas[productoId]?.cantidad ?? 0;

  /// true si se puede agregar de [r] sin vaciar el carrito.
  bool puedeAgregarDe(Restaurante r) => vacio || _restaurante?.id == r.id;

  /// Agrega una pieza. Si el carrito era de otro restaurante, se vacía primero
  /// (la pantalla debe confirmarlo con el usuario antes).
  void agregar(Restaurante r, Producto p) {
    if (!puedeAgregarDe(r)) {
      _lineas.clear();
    }
    _restaurante = r;
    final linea = _lineas[p.id];
    if (linea == null) {
      _lineas[p.id] = LineaCarrito(p, 1);
    } else if (linea.cantidad < maxPorProducto) {
      linea.cantidad++;
    }
    notifyListeners();
  }

  void quitarUno(int productoId) {
    final linea = _lineas[productoId];
    if (linea == null) return;
    if (linea.cantidad <= 1) {
      _lineas.remove(productoId);
    } else {
      linea.cantidad--;
    }
    if (_lineas.isEmpty) _restaurante = null;
    notifyListeners();
  }

  void eliminar(int productoId) {
    if (_lineas.remove(productoId) == null) return;
    if (_lineas.isEmpty) _restaurante = null;
    notifyListeners();
  }

  void vaciar() {
    if (_lineas.isEmpty && _restaurante == null) return;
    _lineas.clear();
    _restaurante = null;
    notifyListeners();
  }

  /// Formato que espera el backend: [{producto_id, cantidad}, ...].
  List<Map<String, int>> get itemsParaApi => _lineas.values
      .map((l) => {'producto_id': l.producto.id, 'cantidad': l.cantidad})
      .toList();
}
