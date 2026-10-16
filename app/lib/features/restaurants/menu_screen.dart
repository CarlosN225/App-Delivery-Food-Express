import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../cart/carrito_screen.dart';
import '../cart/carrito_service.dart';
import 'restaurant_model.dart';
import 'restaurant_service.dart';

class MenuScreen extends StatefulWidget {
  final Restaurante restaurante;
  final UsuarioAutenticado usuario;

  const MenuScreen({
    super.key,
    required this.restaurante,
    required this.usuario,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final CarritoService carrito = CarritoService.instance;

  List<Producto> productos = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargarMenu();
  }

  Future<void> cargarMenu() async {
    try {
      final resultado = await RestauranteService.obtenerProductosRestaurante(
        widget.restaurante.id,
      );

      if (!mounted) return;
      setState(() {
        productos = resultado;
        cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo cargar el menú.';
        cargando = false;
      });
    }
  }

  Future<void> _agregar(Producto producto) async {
    if (!carrito.puedeAgregarDe(widget.restaurante)) {
      final otro = carrito.restaurante?.nombre ?? 'otro restaurante';
      final vaciar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Empezar un pedido nuevo?'),
          content: Text(
            'Tu carrito tiene productos de $otro. Solo puedes pedir a un '
            'restaurante a la vez. ¿Vaciar el carrito y pedir en '
            '${widget.restaurante.nombre}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Vaciar y continuar'),
            ),
          ],
        ),
      );
      if (vaciar != true) return;
    }
    carrito.agregar(widget.restaurante, producto);
  }

  void _abrirCarrito() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarritoScreen(usuario: widget.usuario),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(
        widget.restaurante.nombre,
        actions: [
          ListenableBuilder(
            listenable: carrito,
            builder: (context, _) => IconButton(
              tooltip: 'Mi carrito',
              onPressed: _abrirCarrito,
              icon: Badge(
                isLabelVisible: !carrito.vacio,
                label: Text('${carrito.totalPiezas}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ),
        ],
      ),
      body: _contenido(),
      bottomNavigationBar: ListenableBuilder(
        listenable: carrito,
        builder: (context, _) {
          if (carrito.vacio) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: PrimaryButton(
                label:
                    'Ver carrito (${carrito.totalPiezas}) · ${dinero(carrito.subtotal)}',
                onPressed: _abrirCarrito,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _contenido() {
    if (cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text(error!));
    }

    if (productos.isEmpty) {
      return const Center(
        child: Text('Este restaurante todavía no tiene productos.'),
      );
    }

    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: productos.length,
        itemBuilder: (context, index) {
          final producto = productos[index];
          final cantidad = carrito.cantidadDe(producto.id);

          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        producto.nombre,
                        style: AppTypography.body(weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        producto.descripcion ?? 'Sin descripción',
                        style: AppTypography.body(
                          color: AppColors.hint,
                          size: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dinero(producto.precio),
                        style: AppTypography.body(
                          weight: FontWeight.w700,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ControlCantidad(
                  cantidad: cantidad,
                  onAgregar: () => _agregar(producto),
                  onQuitar: () => carrito.quitarUno(producto.id),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Botón "+" que se convierte en "− 2 +" cuando el producto ya está en el carrito.
class _ControlCantidad extends StatelessWidget {
  final int cantidad;
  final VoidCallback onAgregar;
  final VoidCallback onQuitar;

  const _ControlCantidad({
    required this.cantidad,
    required this.onAgregar,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    if (cantidad == 0) {
      return IconButton.filled(
        tooltip: 'Agregar al carrito',
        onPressed: onAgregar,
        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
        icon: const Icon(Icons.add, color: Colors.white),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Quitar uno',
          onPressed: onQuitar,
          icon: Icon(
            cantidad == 1 ? Icons.delete_outline : Icons.remove,
            color: AppColors.primary,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$cantidad',
            textAlign: TextAlign.center,
            style: AppTypography.body(weight: FontWeight.w700, size: 16),
          ),
        ),
        IconButton.filled(
          tooltip: 'Agregar otro',
          onPressed: onAgregar,
          style: IconButton.styleFrom(backgroundColor: AppColors.primary),
          icon: const Icon(Icons.add, color: Colors.white),
        ),
      ],
    );
  }
}
