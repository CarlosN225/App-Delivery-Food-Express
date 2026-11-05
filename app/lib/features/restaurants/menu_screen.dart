import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/imagenes.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../cart/carrito_screen.dart';
import '../cart/carrito_service.dart';
import 'restaurant_model.dart';
import 'restaurant_service.dart';

/// Menú de un restaurante.
///
/// Mismo diseño que el Inicio y el panel del repartidor: esquinas rectas,
/// líneas finas, Poppins y rótulos pequeños en mayúsculas. En pantalla ancha
/// el pedido se arma en un panel lateral; en celular, en una barra inferior.
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
  // COLORES Y MEDIDAS
  // =====================================================

  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color verdeClaro = AppColors.mint;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color ambar = Color(0xFFF2B134);
  static const Color menta = Color(0xFFE5F5F3);

  // Mismo prefijo que el Inicio: assets/images/<prefijo>-pizza.png
  static const String _prefijoFoto = 'fachada';

  // Ancho máximo del contenido en pantallas grandes.
  static const double _anchoMaximo = 1080;

  // Desde este ancho el pedido va en un panel a la derecha.
  static const double _anchoConPanel = 1060;
  static const double _anchoPanel = 360;

  // Velocidad que usa el backend para estimar el traslado.
  static const double _kmPorHora = 25;

  // =====================================================
  // ESTADO
  // =====================================================

  final CarritoService carrito = CarritoService.instance;
  final TextEditingController _buscador = TextEditingController();

  List<Producto> productos = [];
  bool cargando = true;
  String? error;

  String _busqueda = '';
  String? _categoriaSel; // null = todas

  @override
  void initState() {
    super.initState();
    cargarMenu();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
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
  // TEXTOS DE APOYO
  // =====================================================

  TextStyle _rotulo({Color color = grisTexto, double size = 10}) {
    return AppTypography.body(
      color: color,
      weight: FontWeight.w700,
      size: size,
    ).copyWith(letterSpacing: 1.5);
  }

  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }

  // =====================================================
  // CATEGORÍA Y FOTO DEL RESTAURANTE
  // =====================================================

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

  // Fotos del banner, de la más específica a la más general:
  //   assets/images/restaurantes/<nombre-del-restaurante>.jpg|png|webp
  //   assets/images/fachada-<categoria>.png
  // Si no hay ninguna, se ve el fondo verde con el ícono de la categoría.
  List<String> get _fotosRestaurante {
    final slug = Imagenes.slug(widget.restaurante.nombre);
    return [
      'assets/images/restaurantes/$slug.jpg',
      'assets/images/restaurantes/$slug.png',
      'assets/images/restaurantes/$slug.webp',
      'assets/images/$_prefijoFoto-${_categoriaRestaurante()}.png',
    ];
  }

  IconData _iconoCategoria() {
    switch (_categoriaRestaurante()) {
      case 'pizza':
        return Icons.local_pizza_outlined;
      case 'tacos':
        return Icons.restaurant_outlined;
      case 'hamburguesas':
        return Icons.lunch_dining_outlined;
      case 'sushi':
        return Icons.set_meal_outlined;
      case 'postres':
        return Icons.cake_outlined;
      case 'cafe':
        return Icons.local_cafe_outlined;
      default:
        return Icons.storefront_outlined;
    }
  }

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
          title: Text(
            '¿Empezar un pedido nuevo?',
            textAlign: TextAlign.center,
            style: AppTypography.title(size: 20),
          ),
          content: Text(
            'Tu carrito tiene productos de $otro. Solo puedes pedir '
            'a un restaurante a la vez. ¿Vaciar el carrito y pedir en '
            '${widget.restaurante.nombre}?',
            textAlign: TextAlign.center,
            style: AppTypography.body(color: grisTexto, size: 14.5),
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
              child: Text(
                'Cancelar',
                style: AppTypography.body(weight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: verdeOscuro,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
              child: Text(
                'Vaciar y continuar',
                style: AppTypography.body(
                  color: Colors.white,
                  weight: FontWeight.w700,
                ),
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
        border: Border(bottom: BorderSide(color: grisBorde)),
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
              child: const Icon(Icons.arrow_back, color: verdeOscuro),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.restaurante.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title(size: 18),
            ),
          ),
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
                      style: AppTypography.body(
                        weight: FontWeight.w800,
                        size: 11,
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
  // PORTADA
  // =====================================================

  Widget _portada(double margen, bool compacto) {
    final restaurante = widget.restaurante;
    final categoria = (restaurante.categoria ?? '').trim();
    final direccion = (restaurante.direccion ?? '').trim();

    return SizedBox(
      width: double.infinity,
      height: compacto ? 240 : 270,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Foto del restaurante o de su categoría. Si no hay ninguna, un
          // fondo verde con el ícono grande de la categoría.
          Imagenes.primeraImagen(
            _fotosRestaurante,
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF043F40), Color(0xFF0A7F78)],
                ),
              ),
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: margen + 10),
              child: Icon(
                _iconoCategoria(),
                size: compacto ? 120 : 190,
                color: const Color(0x1FFFFFFF),
              ),
            ),
          ),

          // Atenúa la foto (capa verde oscuro pareja) y, encima, un degradado
          // más fuerte a la izquierda para que las letras resalten.
          const ColoredBox(color: Color(0x8A00292B)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xF2003033),
                  Color(0xB3003033),
                  Color(0x33003033),
                ],
                stops: [0.0, 0.6, 1.0],
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
                    categoria.isEmpty
                        ? 'RESTAURANTE'
                        : 'RESTAURANTE · ${categoria.toUpperCase()}',
                    style: _rotulo(color: verdeClaro, size: 10.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    restaurante.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title(size: compacto ? 32 : 46).copyWith(
                      color: Colors.white,
                      letterSpacing: -1,
                      shadows: const [
                        Shadow(color: Color(0x80000000), blurRadius: 10),
                      ],
                    ),
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
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            direccion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body(
                              color: Colors.white,
                              size: 14.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Pide desde aquí y sigue a tu repartidor en el mapa, '
                    'en tiempo real.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      color: const Color(0xE6FFFFFF),
                      weight: FontWeight.w400,
                      size: 13.5,
                    ).copyWith(
                      shadows: const [
                        Shadow(color: Color(0x80000000), blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FRANJA DE DATOS (distancia, traslado, envío, pago)
  // =====================================================

  Widget _celdaDato(IconData icono, String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            color: menta,
            child: Icon(icono, color: turquesa, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rotulo, style: _rotulo(size: 9.5)),
                const SizedBox(height: 2),
                Text(
                  valor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    weight: FontWeight.w700,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _franjaDatos(bool compacto) {
    final km = widget.restaurante.distanciaKm;
    final minutos = km <= 0 ? 1 : (km / _kmPorHora * 60).ceil().clamp(1, 999);

    final celdas = [
      _celdaDato(
        Icons.location_on_outlined,
        'DISTANCIA',
        '${km.toStringAsFixed(2)} km de ti',
      ),
      _celdaDato(
        Icons.timer_outlined,
        'TRASLADO',
        '≈ $minutos min',
      ),
      _celdaDato(
        Icons.delivery_dining_outlined,
        'ENVÍO',
        'Desde \$30',
      ),
      _celdaDato(
        Icons.payments_outlined,
        'PAGO',
        'Efectivo o Mercado Pago',
      ),
    ];

    const linea = BorderSide(color: grisBorde);

    Widget fila(List<Widget> hijos, {bool conLineaArriba = false}) {
      return Container(
        decoration: BoxDecoration(
          border: Border(top: conLineaArriba ? linea : BorderSide.none),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < hijos.length; i++) ...[
                if (i > 0) Container(width: 1, color: grisBorde),
                Expanded(child: hijos[i]),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: compacto
          ? Column(
              children: [
                fila([celdas[0], celdas[1]]),
                fila([celdas[2], celdas[3]], conLineaArriba: true),
              ],
            )
          : fila(celdas),
    );
  }

  // =====================================================
  // BUSCADOR Y CATEGORÍAS
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

  // Grupos que pasan el filtro de categoría y de búsqueda.
  Map<String, List<Producto>> get _gruposVisibles {
    final q = _normalizar(_busqueda.trim());
    final salida = <String, List<Producto>>{};

    _grupos.forEach((categoria, lista) {
      if (_categoriaSel != null && categoria != _categoriaSel) return;

      final filtrados = q.isEmpty
          ? lista
          : lista
              .where(
                (p) => _normalizar('${p.nombre} ${p.descripcion ?? ''}')
                    .contains(q),
              )
              .toList();

      if (filtrados.isNotEmpty) salida[categoria] = filtrados;
    });

    return salida;
  }

  Widget _campoBusqueda() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search, color: grisTexto, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _buscador,
              onChanged: (v) => setState(() => _busqueda = v),
              style: AppTypography.body(size: 14.5),
              cursorColor: turquesa,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Busca un platillo o una bebida',
                hintStyle: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14.5,
                ),
              ),
            ),
          ),
          if (_busqueda.isNotEmpty)
            IconButton(
              tooltip: 'Borrar búsqueda',
              onPressed: () {
                _buscador.clear();
                setState(() => _busqueda = '');
              },
              icon: const Icon(Icons.close, size: 20, color: grisTexto),
            ),
        ],
      ),
    );
  }

  Widget _chipCategoria(String texto, bool activo, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: activo ? verdeOscuro : Colors.white,
          border: Border.all(color: activo ? verdeOscuro : grisBorde),
        ),
        child: Text(
          texto,
          style: AppTypography.body(
            color: activo ? Colors.white : verdeOscuro,
            weight: FontWeight.w600,
            size: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _barraHerramientas() {
    final categorias = _grupos.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campoBusqueda(),
        if (categorias.length > 1) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipCategoria(
                'Todo',
                _categoriaSel == null,
                () => setState(() => _categoriaSel = null),
              ),
              for (final c in categorias)
                _chipCategoria(
                  c,
                  _categoriaSel == c,
                  () => setState(() => _categoriaSel = c),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // =====================================================
  // PRODUCTOS
  // =====================================================

  Widget _botonCuadrado({
    required IconData icono,
    required VoidCallback onTap,
    required String tooltip,
    bool relleno = true,
    double lado = 42,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: relleno ? verdeOscuro : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: lado,
            height: lado,
            child: Icon(
              icono,
              color: relleno ? Colors.white : verdeOscuro,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  // "AGREGAR +" que se convierte en "− 2 +" cuando ya está en el carrito.
  Widget _controlCantidad(Producto producto, {required bool conTexto}) {
    final cantidad = carrito.cantidadDe(producto.id);

    if (cantidad == 0) {
      return Tooltip(
        message: 'Agregar al carrito',
        child: Material(
          color: verdeOscuro,
          child: InkWell(
            onTap: () => _agregar(producto),
            child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: conTexto ? 16 : 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conTexto) ...[
                    Text(
                      'AGREGAR',
                      style: AppTypography.body(
                        color: Colors.white,
                        weight: FontWeight.w700,
                        size: 12,
                      ).copyWith(letterSpacing: 1.2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.add, color: Colors.white, size: 21),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: verdeOscuro, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonCuadrado(
            icono: cantidad == 1 ? Icons.delete_outline : Icons.remove,
            tooltip: 'Quitar uno',
            relleno: false,
            lado: 39,
            onTap: () => carrito.quitarUno(producto.id),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$cantidad',
              textAlign: TextAlign.center,
              style: AppTypography.body(weight: FontWeight.w700, size: 16),
            ),
          ),
          _botonCuadrado(
            icono: Icons.add,
            tooltip: 'Agregar otro',
            lado: 39,
            onTap: () => _agregar(producto),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProducto(Producto producto, bool compacto) {
    final descripcion = (producto.descripcion ?? '').trim();
    final cantidad = carrito.cantidadDe(producto.id);
    final enCarrito = cantidad > 0;
    final anchoFoto = compacto ? 118.0 : 180.0;

    // La foto es un rectángulo vertical que ocupa todo el alto de la tarjeta.
    final foto = SizedBox(
      width: anchoFoto,
      child: Stack(
        children: [
          Positioned.fill(
            child: Imagenes.primeraImagen(
              Imagenes.fotosDeProducto(producto),
              Container(
                color: menta,
                alignment: Alignment.center,
                child: Icon(
                  Imagenes.iconoDeProducto(producto),
                  color: turquesa,
                  size: anchoFoto * 0.42,
                ),
              ),
            ),
          ),
          if (enCarrito)
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                color: verdeClaro,
                child: Text(
                  cantidad == 1 ? 'EN TU PEDIDO' : '$cantidad EN TU PEDIDO',
                  style: _rotulo(color: verdeOscuro, size: 9),
                ),
              ),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: enCarrito ? const Color(0xFFF6FCFB) : Colors.white,
        border: Border.all(
          color: enCarrito ? turquesa : grisBorde,
          width: enCarrito ? 1.6 : 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compacto ? 168 : 236),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              foto,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(compacto ? 14 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            producto.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body(
                              weight: FontWeight.w700,
                              size: compacto ? 15.5 : 17.5,
                            ),
                          ),
                          if (descripcion.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              descripcion,
                              maxLines: compacto ? 3 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(
                                color: grisTexto,
                                weight: FontWeight.w400,
                                size: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dinero(producto.precio),
                              style: AppTypography.title(
                                size: compacto ? 18 : 22,
                              ),
                            ),
                          ),
                          _controlCantidad(producto, conTexto: !compacto),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tituloSeccion(String titulo, int cantidad) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CATEGORÍA', style: _rotulo(size: 9.5)),
                const SizedBox(height: 4),
                Text(titulo, style: AppTypography.title(size: 26)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: menta,
            child: Text(
              cantidad == 1 ? '1 producto' : '$cantidad productos',
              style: AppTypography.body(
                weight: FontWeight.w600,
                size: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Una o dos columnas de tarjetas, según el ancho disponible.
  Widget _rejilla(List<Producto> lista, double ancho, bool compacto) {
    final dosColumnas = ancho >= 760;

    if (!dosColumnas) {
      return Column(
        children: [
          for (final p in lista)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _tarjetaProducto(p, compacto),
            ),
        ],
      );
    }

    final filas = <Widget>[];
    for (var i = 0; i < lista.length; i += 2) {
      filas.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _tarjetaProducto(lista[i], false)),
                const SizedBox(width: 14),
                Expanded(
                  child: i + 1 < lista.length
                      ? _tarjetaProducto(lista[i + 1], false)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: filas);
  }

  Widget _tarjetaEsqueleto() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        children: [
          Container(width: 130, color: menta),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 180, height: 16, color: grisBorde),
                const SizedBox(height: 12),
                Container(width: 240, height: 12, color: menta),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensajeVacio({
    required IconData icono,
    required String titulo,
    required String texto,
    Widget? accion,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            color: menta,
            child: Icon(icono, size: 32, color: turquesa),
          ),
          const SizedBox(height: 16),
          Text(titulo, textAlign: TextAlign.center, style: AppTypography.title(size: 19)),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: grisTexto,
              weight: FontWeight.w400,
              size: 14,
            ),
          ),
          if (accion != null) ...[
            const SizedBox(height: 18),
            accion,
          ],
        ],
      ),
    );
  }

  Widget _botonSolido(String texto, VoidCallback onTap) {
    return Material(
      color: verdeOscuro,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Text(
            texto.toUpperCase(),
            style: AppTypography.body(
              color: Colors.white,
              weight: FontWeight.w700,
              size: 12.5,
            ).copyWith(letterSpacing: 1.3),
          ),
        ),
      ),
    );
  }

  Widget _listaProductos(double ancho, bool compacto) {
    if (cargando) {
      return Column(
        children: [
          for (var i = 0; i < 3; i++) _tarjetaEsqueleto(),
          const SizedBox(height: 12),
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(color: turquesa, strokeWidth: 3),
          ),
        ],
      );
    }

    if (error != null) {
      return _mensajeVacio(
        icono: Icons.cloud_off_outlined,
        titulo: error!,
        texto: 'Revisa tu conexión e inténtalo otra vez.',
        accion: _botonSolido('Reintentar', _reintentar),
      );
    }

    if (productos.isEmpty) {
      return _mensajeVacio(
        icono: Icons.restaurant_menu,
        titulo: 'Este restaurante todavía no tiene productos',
        texto: 'Estamos preparando su menú. Vuelve en un rato o prueba con '
            'otro restaurante.',
        accion: _botonSolido('Ver otros restaurantes', () => Navigator.pop(context)),
      );
    }

    final grupos = _gruposVisibles;

    if (grupos.isEmpty) {
      return _mensajeVacio(
        icono: Icons.search_off,
        titulo: 'No encontramos lo que buscas',
        texto: 'Prueba con otra palabra o quita el filtro de categoría.',
        accion: _botonSolido('Limpiar filtros', () {
          _buscador.clear();
          setState(() {
            _busqueda = '';
            _categoriaSel = null;
          });
        }),
      );
    }

    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entrada in grupos.entries) ...[
            _tituloSeccion(entrada.key, entrada.value.length),
            _rejilla(entrada.value, ancho, compacto),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // CÓMO FUNCIONA
  // =====================================================

  Widget _pasoInfo(String numero, IconData icono, String titulo, String texto) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            color: verdeOscuro,
            child: Icon(icono, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PASO $numero', style: _rotulo(size: 9.5)),
                const SizedBox(height: 3),
                Text(
                  titulo,
                  style: AppTypography.body(weight: FontWeight.w700, size: 15.5),
                ),
                const SizedBox(height: 4),
                Text(
                  texto,
                  style: AppTypography.body(
                    color: grisTexto,
                    weight: FontWeight.w400,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comoFunciona(double ancho) {
    final pasos = [
      _pasoInfo(
        '01',
        Icons.shopping_basket_outlined,
        'Arma tu pedido',
        'Agrega lo que se te antoje. Se pide a un solo restaurante a la vez.',
      ),
      _pasoInfo(
        '02',
        Icons.place_outlined,
        'Marca tu puerta',
        'Escribe tu dirección y arrastra el pin hasta tu puerta. Puedes dejar '
            'una referencia para el repartidor.',
      ),
      _pasoInfo(
        '03',
        Icons.route_outlined,
        'Síguelo en vivo',
        'Ves la ruta por calles de tu repartidor en el mapa, hasta que llega.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ASÍ DE FÁCIL', style: _rotulo(size: 9.5)),
        const SizedBox(height: 4),
        Text('¿Cómo funciona tu pedido?', style: AppTypography.title(size: 24)),
        const SizedBox(height: 14),
        if (ancho >= 760)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < pasos.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: pasos[i]),
                ],
              ],
            ),
          )
        else
          Column(
            children: [
              for (final p in pasos)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: p),
            ],
          ),
      ],
    );
  }

  // =====================================================
  // PANEL DE PEDIDO (pantalla ancha)
  // =====================================================

  Widget _stepperChico(LineaCarrito l) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: grisBorde)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonCuadrado(
            icono: l.cantidad == 1 ? Icons.delete_outline : Icons.remove,
            tooltip: 'Quitar uno',
            relleno: false,
            lado: 30,
            onTap: () => carrito.quitarUno(l.producto.id),
          ),
          SizedBox(
            width: 26,
            child: Text(
              '${l.cantidad}',
              textAlign: TextAlign.center,
              style: AppTypography.body(weight: FontWeight.w700, size: 13.5),
            ),
          ),
          _botonCuadrado(
            icono: Icons.add,
            tooltip: 'Agregar otro',
            relleno: false,
            lado: 30,
            onTap: () {
              final r = carrito.restaurante ?? widget.restaurante;
              carrito.agregar(r, l.producto);
            },
          ),
        ],
      ),
    );
  }

  Widget _notaInfo(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 17, color: turquesa),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              texto,
              style: AppTypography.body(
                color: grisTexto,
                weight: FontWeight.w400,
                size: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelPedido() {
    return Container(
      width: _anchoPanel,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: grisBorde)),
      ),
      child: ListenableBuilder(
        listenable: carrito,
        builder: (context, _) {
          final vacio = carrito.vacio;
          final otroRestaurante = !vacio &&
              carrito.restaurante != null &&
              carrito.restaurante!.id != widget.restaurante.id;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TU PEDIDO', style: _rotulo(size: 10)),
                    const SizedBox(height: 4),
                    Text(
                      vacio
                          ? 'Todavía vacío'
                          : (carrito.restaurante?.nombre ??
                              widget.restaurante.nombre),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title(size: 22),
                    ),
                    if (!vacio)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          carrito.totalPiezas == 1
                              ? '1 pieza'
                              : '${carrito.totalPiezas} piezas',
                          style: AppTypography.body(
                            color: grisTexto,
                            weight: FontWeight.w400,
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: grisBorde),
              Expanded(
                child: vacio
                    ? _panelVacio()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                        children: [
                          if (otroRestaurante)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              color: const Color(0xFFFDF1D6),
                              child: Text(
                                'Estos productos son de '
                                '${carrito.restaurante!.nombre}. Si agregas '
                                'algo de aquí, empezarás un pedido nuevo.',
                                style: AppTypography.body(
                                  weight: FontWeight.w500,
                                  size: 12.5,
                                ),
                              ),
                            ),
                          for (final l in carrito.lineas)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.producto.nombre,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.body(
                                            weight: FontWeight.w600,
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${dinero(l.producto.precio)} c/u',
                                          style: AppTypography.body(
                                            color: grisTexto,
                                            weight: FontWeight.w400,
                                            size: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _stepperChico(l),
                                      const SizedBox(height: 6),
                                      Text(
                                        dinero(l.importe),
                                        style: AppTypography.body(
                                          weight: FontWeight.w700,
                                          size: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (!vacio)
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: grisBorde)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('SUBTOTAL', style: _rotulo(size: 10.5)),
                          Text(
                            dinero(carrito.subtotal),
                            style: AppTypography.title(size: 26),
                          ),
                        ],
                      ),
                      _notaInfo(
                        Icons.local_shipping_outlined,
                        'El envío se calcula al confirmar tu dirección '
                        '(desde \$30).',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: verdeOscuro,
                          child: InkWell(
                            onTap: _abrirCarrito,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'VER CARRITO Y PAGAR',
                                    style: AppTypography.body(
                                      color: Colors.white,
                                      weight: FontWeight.w700,
                                      size: 13,
                                    ).copyWith(letterSpacing: 1.3),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.arrow_forward,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _panelVacio() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
          decoration: BoxDecoration(
            color: fondo,
            border: Border.all(color: grisBorde),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                color: menta,
                child: const Icon(
                  Icons.shopping_basket_outlined,
                  color: turquesa,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Agrega algo del menú',
                textAlign: TextAlign.center,
                style: AppTypography.body(weight: FontWeight.w700, size: 15.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Aquí verás tu resumen y el total mientras eliges.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _notaInfo(
          Icons.payments_outlined,
          'Paga en efectivo al recibir o en línea con Mercado Pago.',
        ),
        _notaInfo(
          Icons.storefront_outlined,
          'Puedes pedir a un solo restaurante a la vez.',
        ),
        _notaInfo(
          Icons.route_outlined,
          'Sigue a tu repartidor en el mapa, en tiempo real.',
        ),
      ],
    );
  }

  // =====================================================
  // BARRA FIJA DEL CARRITO (celular y pantallas medianas)
  // =====================================================

  Widget _barraCarrito() {
    return ListenableBuilder(
      listenable: carrito,
      builder: (context, _) {
        if (carrito.vacio) return const SizedBox.shrink();

        final nombre = carrito.restaurante?.nombre;

        return Material(
          color: verdeOscuro,
          child: InkWell(
            onTap: _abrirCarrito,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      color: const Color(0x2EFFFFFF),
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
                            'VER CARRITO · ${carrito.totalPiezas}',
                            style: AppTypography.body(
                              color: Colors.white,
                              weight: FontWeight.w700,
                              size: 13,
                            ).copyWith(letterSpacing: 1.2),
                          ),
                          if (nombre != null)
                            Text(
                              '$nombre · el envío se calcula al pagar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(
                                color: const Color(0xCCFFFFFF),
                                weight: FontWeight.w400,
                                size: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      dinero(carrito.subtotal),
                      style: AppTypography.title(size: 20)
                          .copyWith(color: Colors.white),
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
  // CONTENIDO (portada + menú)
  // =====================================================

  Widget _contenido() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final compacto = ancho < 700;

        // Márgenes laterales: el contenido no pasa de _anchoMaximo.
        final margen = ancho > _anchoMaximo + 48
            ? (ancho - _anchoMaximo) / 2
            : (compacto ? 18.0 : 28.0);
        final util = ancho - margen * 2;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _portada(margen, compacto),
              Padding(
                padding: EdgeInsets.fromLTRB(margen, 22, margen, 0),
                child: _franjaDatos(compacto),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(margen, 30, margen, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ARMA TU PEDIDO', style: _rotulo(size: 10)),
                    const SizedBox(height: 4),
                    Text(
                      '¿Qué se te antoja hoy?',
                      style: AppTypography.title(size: compacto ? 26 : 32),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toca AGREGAR en lo que quieras; tu total se va sumando solo.',
                      style: AppTypography.body(
                        color: grisTexto,
                        weight: FontWeight.w400,
                        size: 14,
                      ),
                    ),
                    if (!cargando && error == null && productos.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _barraHerramientas(),
                    ],
                    const SizedBox(height: 10),
                    _listaProductos(util, compacto),
                    const SizedBox(height: 34),
                    _comoFunciona(util),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
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
          final conPanel = ancho >= _anchoConPanel;
          final margenBarra = ancho > 1248 + _anchoPanel
              ? 32.0
              : (ancho < 700 ? 18.0 : 24.0);

          return Column(
            children: [
              _barraSuperior(margenBarra),
              Expanded(
                child: conPanel
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _contenido()),
                          _panelPedido(),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _contenido()),
                          _barraCarrito(),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
