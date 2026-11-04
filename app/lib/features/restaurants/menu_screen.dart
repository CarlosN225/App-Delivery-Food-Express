import 'package:flutter/material.dart';

import '../../core/format.dart';
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
  // =====================================================
  // COLORES Y MEDIDAS (los mismos del Inicio)
  // =====================================================

  static const Color verdeOscuro = Color(0xFF005457);
  static const Color turquesa = Color(0xFF00A99D);
  static const Color verdeClaro = Color(0xFF74E58B);
  static const Color grisTexto = Color(0xFF617784);
  static const Color grisBorde = Color(0xFFE5EEEE);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color ambar = Color(0xFFF2B134);
  static const Color menta = Color(0xFFE5F5F3);

  // Mismo prefijo que el Inicio: assets/images/<prefijo>-pizza.png
  static const String _prefijoFoto = 'fachada';

  // Ancho máximo del contenido en pantallas grandes.
  static const double _anchoMaximo = 1200;

  // =====================================================
  // ESTADO
  // =====================================================

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
      final resultado =
          await RestauranteService.obtenerProductosRestaurante(
        widget.restaurante.id,
      );

      if (!mounted) return;

      setState(() {
        productos = resultado;
        cargando = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = 'No se pudo cargar el menú.';
        cargando = false;
      });
    }
  }

  void _reintentar() {
    setState(() {
      cargando = true;
      error = null;
    });
    cargarMenu();
  }

  // =====================================================
  // CATEGORÍA Y FOTO DEL RESTAURANTE
  // =====================================================

  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String _categoriaRestaurante() {
    final texto = _normalizar(
      '${widget.restaurante.categoria ?? ''} '
      '${widget.restaurante.nombre}',
    );

    if (texto.contains('pizza')) return 'pizza';

    if (texto.contains('taco') ||
        texto.contains('mexicana') ||
        texto.contains('taqueria')) {
      return 'tacos';
    }

    if (texto.contains('hamburgues') || texto.contains('burger')) {
      return 'hamburguesas';
    }

    if (texto.contains('sushi') || texto.contains('japones')) {
      return 'sushi';
    }

    if (texto.contains('postre') ||
        texto.contains('pasteleria') ||
        texto.contains('reposteria')) {
      return 'postres';
    }

    if (texto.contains('cafe')) return 'cafe';

    return 'general';
  }

  String get _fotoRestaurante =>
      'assets/images/$_prefijoFoto-${_categoriaRestaurante()}.png';

  // =====================================================
  // ACCIONES
  // =====================================================

  Future<void> _agregar(Producto producto) async {
    if (!carrito.puedeAgregarDe(widget.restaurante)) {
      final otro = carrito.restaurante?.nombre ?? 'otro restaurante';

      final vaciar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(),
          icon: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFFDF1D6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: ambar,
              size: 30,
            ),
          ),
          title: const Text(
            '¿Empezar un pedido nuevo?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: verdeOscuro,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Tu carrito tiene productos de $otro. Solo puedes pedir '
            'a un restaurante a la vez. ¿Vaciar el carrito y pedir en '
            '${widget.restaurante.nombre}?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: grisTexto,
              fontSize: 15,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(
                foregroundColor: verdeOscuro,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: turquesa,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
              child: const Text(
                'Vaciar y continuar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
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

  // =====================================================
  // BARRA SUPERIOR
  // =====================================================

  Widget _barraSuperior(double margen) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: margen),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: grisBorde),
        ),
      ),
      child: Row(
        children: [
          // Botón de regreso cuadrado.
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: grisBorde),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: verdeOscuro,
              ),
            ),
          ),
          const Spacer(),
          _botonCarrito(),
          const SizedBox(width: 14),
          Container(width: 1, height: 32, color: grisBorde),
          const SizedBox(width: 14),
          Image.asset(
            'assets/images/logo-food-express.png',
            width: 110,
            height: 40,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  // Carrito con cuadrito verde (esquinas rectas).
  Widget _botonCarrito() {
    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) {
        final cantidad = carrito.totalPiezas;

        return IconButton(
          tooltip: 'Mi carrito',
          onPressed: _abrirCarrito,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                size: 29,
                color: verdeOscuro,
              ),
              if (cantidad > 0)
                Positioned(
                  top: -6,
                  right: -9,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 19),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    color: verdeClaro,
                    child: Text(
                      '$cantidad',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: verdeOscuro,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // PORTADA DEL RESTAURANTE
  // =====================================================

  Widget _chip({
    required String texto,
    required Color colorFondo,
    required Color colorTexto,
    IconData? icono,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 16, color: colorTexto),
            const SizedBox(width: 5),
          ],
          Text(
            texto,
            style: TextStyle(
              color: colorTexto,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _portada(double margen, bool compacto) {
    final restaurante = widget.restaurante;
    final categoria = (restaurante.categoria ?? '').trim();
    final direccion = (restaurante.direccion ?? '').trim();

    return SizedBox(
      width: double.infinity,
      height: compacto ? 230 : 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Foto de la categoría. Si no existe el archivo,
          // se ve el fondo verde oscuro.
          Image.asset(
            _fotoRestaurante,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: verdeOscuro),
          ),

          // Degradado verde oscuro para que el texto se lea.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xE6003A3C),
                  Color(0x99003A3C),
                  Color(0x00003A3C),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: margen),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurante.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compacto ? 32 : 46,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (categoria.isNotEmpty)
                        _chip(
                          texto: categoria,
                          colorFondo: verdeClaro,
                          colorTexto: verdeOscuro,
                          icono: Icons.restaurant_outlined,
                        ),
                      _chip(
                        texto:
                            '${restaurante.distanciaKm.toStringAsFixed(2)} km de ti',
                        colorFondo: Colors.white,
                        colorTexto: verdeOscuro,
                        icono: Icons.location_on_outlined,
                      ),
                      _chip(
                        texto: 'Envío desde \$30',
                        colorFondo: Colors.white,
                        colorTexto: verdeOscuro,
                        icono: Icons.delivery_dining_outlined,
                      ),
                    ],
                  ),
                  if (direccion.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            direccion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // PRODUCTOS
  // =====================================================

  // Agrupa por la categoría del producto ("Pizzas", "Bebidas"...).
  // Si no tiene, va en "Menú".
  Map<String, List<Producto>> get _grupos {
    final grupos = <String, List<Producto>>{};

    for (final producto in productos) {
      final categoria = (producto.categoria ?? '').trim();
      final clave = categoria.isEmpty ? 'Menú' : categoria;

      grupos.putIfAbsent(clave, () => []).add(producto);
    }

    return grupos;
  }

  // Foto del producto si trae una URL; si no, un recuadro menta.
  Widget _fotoProducto(Producto producto, double tamano) {
    final recuadro = Container(
      width: tamano,
      height: tamano,
      color: menta,
      child: Icon(
        Icons.fastfood_outlined,
        color: turquesa,
        size: tamano * 0.4,
      ),
    );

    final url = (producto.imagen ?? '').trim();

    if (!url.startsWith('http')) return recuadro;

    return SizedBox(
      width: tamano,
      height: tamano,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => recuadro,
      ),
    );
  }

  Widget _botonCuadrado({
    required IconData icono,
    required VoidCallback onTap,
    required String tooltip,
    bool relleno = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: relleno ? turquesa : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icono,
              color: relleno ? Colors.white : turquesa,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  // "+" que se convierte en "− 2 +" cuando ya está en el carrito.
  Widget _controlCantidad(Producto producto) {
    final cantidad = carrito.cantidadDe(producto.id);

    if (cantidad == 0) {
      return _botonCuadrado(
        icono: Icons.add,
        tooltip: 'Agregar al carrito',
        onTap: () => _agregar(producto),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: turquesa, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonCuadrado(
            icono: cantidad == 1 ? Icons.delete_outline : Icons.remove,
            tooltip: 'Quitar uno',
            relleno: false,
            onTap: () => carrito.quitarUno(producto.id),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$cantidad',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: verdeOscuro,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _botonCuadrado(
            icono: Icons.add,
            tooltip: 'Agregar otro',
            onTap: () => _agregar(producto),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProducto(Producto producto, bool compacto) {
    final descripcion = (producto.descripcion ?? '').trim();

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          producto.nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: verdeOscuro,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (descripcion.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            descripcion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: grisTexto,
              fontSize: 14,
            ),
          ),
        ],
        if (compacto) ...[
          const SizedBox(height: 8),
          Text(
            dinero(producto.precio),
            style: const TextStyle(
              color: verdeOscuro,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        children: [
          _fotoProducto(producto, compacto ? 84 : 110),
          SizedBox(width: compacto ? 14 : 20),
          Expanded(child: textos),
          const SizedBox(width: 16),
          if (!compacto) ...[
            Text(
              dinero(producto.precio),
              style: const TextStyle(
                color: verdeOscuro,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 28),
          ],
          _controlCantidad(producto),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String titulo, int cantidad) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                color: verdeOscuro,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Text(
            cantidad == 1 ? '1 producto' : '$cantidad productos',
            style: const TextStyle(
              color: grisTexto,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEsqueleto() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        children: [
          Container(width: 100, height: 100, color: grisBorde),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 180, height: 16, color: grisBorde),
                const SizedBox(height: 12),
                Container(width: 260, height: 12, color: grisBorde),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaProductos(bool compacto) {
    if (cargando) {
      return Column(
        children: [
          for (var i = 0; i < 3; i++) _tarjetaEsqueleto(),
          const SizedBox(height: 12),
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              color: turquesa,
              strokeWidth: 3,
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: verdeOscuro,
              ),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: verdeOscuro,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _reintentar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: turquesa,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 14,
                  ),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (productos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: menta,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.restaurant_menu,
                  size: 38,
                  color: turquesa,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Este restaurante todavía no tiene productos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: grisTexto,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grupos = _grupos;

    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entrada in grupos.entries) ...[
            _tituloSeccion(entrada.key, entrada.value.length),
            for (final producto in entrada.value)
              _tarjetaProducto(producto, compacto),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // BARRA FIJA DEL CARRITO
  // =====================================================

  Widget _barraCarrito() {
    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) {
        if (carrito.vacio) return const SizedBox.shrink();

        final nombre = carrito.restaurante?.nombre;

        return Material(
          color: turquesa,
          child: InkWell(
            onTap: _abrirCarrito,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      color: Colors.white24,
                      child: const Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ver carrito (${carrito.totalPiezas})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (nombre != null)
                            Text(
                              nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      dinero(carrito.subtotal),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // PANTALLA COMPLETA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final compacto = ancho < 700;

          // Márgenes laterales: el contenido no pasa de 1200 px.
          final margen = ancho > _anchoMaximo + 48
              ? (ancho - _anchoMaximo) / 2
              : (compacto ? 18.0 : 24.0);

          return Column(
            children: [
              _barraSuperior(margen),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _portada(margen, compacto),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          margen,
                          28,
                          margen,
                          40,
                        ),
                        child: _listaProductos(compacto),
                      ),
                    ],
                  ),
                ),
              ),
              _barraCarrito(),
            ],
          );
        },
      ),
    );
  }
}