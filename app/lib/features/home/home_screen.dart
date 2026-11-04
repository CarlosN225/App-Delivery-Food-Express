import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/location_service.dart';
import '../admin/admin_screen.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../cart/carrito_screen.dart';
import '../cart/carrito_service.dart';
import '../cart/mis_pedidos_screen.dart';
import '../cart/rastreo_screen.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import '../delivery/repartidor_screen.dart';
import '../notificaciones/notificacion_service.dart';
import '../notificaciones/notificaciones_screen.dart';
import '../restaurants/menu_screen.dart';
import '../restaurants/restaurant_model.dart';
import '../restaurants/restaurant_service.dart';

class HomeScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const HomeScreen({
    super.key,
    required this.usuario,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // =====================================================
  // COLORES Y MEDIDAS
  // =====================================================

  static const Color verdeOscuro = Color(0xFF005457);
  static const Color turquesa = Color(0xFF00A99D);
  static const Color verdeClaro = Color(0xFF74E58B);
  static const Color grisTexto = Color(0xFF617784);
  static const Color grisBorde = Color(0xFFE5EEEE);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color ambar = Color(0xFFF2B134);

  // Proporción de la imagen de cada tarjeta (ancho / alto)
  // y alto que ocupa el texto debajo de la imagen.
  static const double _proporcionImagen = 2.0;
  static const double _altoTextoTarjeta = 116;

  // Prefijo de las fotos por categoría:
  // assets/images/<prefijo>-pizza.png, -tacos.png, etc.
  // Para usar fotos de platillos en vez de fachadas, cambia
  // 'fachada' por 'plato' (y renombra los archivos).
  static const String _prefijoFoto = 'fachada';

  // Orden en que aparecen las categorías en la barra.
  static const List<String> _ordenCategorias = [
    'Pizza',
    'Tacos',
    'Hamburguesas',
    'Sushi',
    'Postres',
    'Café',
    'Otros',
  ];

  // Estados del pedido, en orden, para la barra de progreso.
  static const List<String> _pasos = [
    'pendiente',
    'aceptado',
    'recogido',
    'en_camino',
    'entregado',
  ];

  // Radios disponibles (km). La API ya limita a 10 km.
  static const List<double> _opcionesRadio = [2, 5, 10];

  // =====================================================
  // ESTADO
  // =====================================================

  List<Restaurante> restaurantes = [];
  List<Pedido> _pedidos = [];

  bool cargando = true;
  String? mensajeError;

  String categoriaSeleccionada = 'Todo';
  String filtroSeleccionado = 'Más cercanos';
  double radioKm = 10;
  String busqueda = '';

  Timer? _temporizador;

  // Notificaciones (Sprint 4, historia #15)
  Timer? _temporizadorNotificaciones;
  int noLeidas = 0;
  int _ultimoNotificacionId = 0;
  bool _primeraSincronizacion = true;

  final TextEditingController _busquedaController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _claveLista = GlobalKey();

  bool get _esCliente => widget.usuario.rol == 'cliente';
  bool get _esAdmin => widget.usuario.rol == 'administrador';

  @override
  void initState() {
    super.initState();
    buscarRestaurantes();

    if (_esCliente) {
      _cargarPedidos();
      // Mismo ritmo que "Mis pedidos": cada 15 segundos.
      _temporizador = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _cargarPedidos(),
      );

      // Historia #15: el cliente revisa sus notificaciones cada 10 s.
      _sincronizarNotificaciones();
      _temporizadorNotificaciones = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sincronizarNotificaciones(),
      );
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _temporizadorNotificaciones?.cancel();
    _busquedaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =====================================================
  // UBICACIÓN Y RESTAURANTES REALES
  // =====================================================

  Future<void> buscarRestaurantes() async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      final posicion =
          await LocationService.obtenerUbicacionActual();

      if (!mounted) return;

      if (posicion == null) {
        setState(() {
          cargando = false;
          mensajeError =
              'No se pudo obtener tu ubicación. '
              'Revisa los permisos de Chrome.';
        });
        return;
      }

      final resultados =
          await RestauranteService.obtenerRestaurantesCercanos(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
      );

      if (!mounted) return;

      setState(() {
        restaurantes = resultados;
        cargando = false;

        // Si la categoría elegida ya no existe, vuelve a "Todo".
        if (!_categoriasDisponibles.contains(categoriaSeleccionada)) {
          categoriaSeleccionada = 'Todo';
        }
      });
    } catch (e) {
      debugPrint('Error al cargar restaurantes: $e');

      if (!mounted) return;

      setState(() {
        cargando = false;
        mensajeError =
            'No se pudieron cargar los restaurantes.';
      });
    }
  }

  // =====================================================
  // PEDIDOS DEL CLIENTE (tarjeta de seguimiento
  // y "Pide de nuevo")
  // =====================================================

  Future<void> _cargarPedidos() async {
    if (!_esCliente) return;

    try {
      final resultado =
          await PedidoService.misPedidos(widget.usuario.token);

      if (!mounted) return;

      setState(() => _pedidos = resultado);
    } catch (e) {
      // Es información extra: si falla, el inicio sigue igual.
      debugPrint('No se pudieron cargar los pedidos: $e');
    }
  }

  // Pedido más reciente que todavía no termina.
  Pedido? get _pedidoActivo {
    Pedido? elegido;

    for (final pedido in _pedidos) {
      final enCurso =
          pedido.estado == 'pendiente' || pedido.activo;

      if (!enCurso) continue;

      if (elegido == null || pedido.id > elegido.id) {
        elegido = pedido;
      }
    }

    return elegido;
  }

  // Hasta 2 pedidos entregados, de restaurantes distintos.
  List<Pedido> get _pedidosParaRepetir {
    final entregados = _pedidos
        .where((pedido) => pedido.estado == 'entregado')
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));

    final vistos = <int>{};
    final resultado = <Pedido>[];

    for (final pedido in entregados) {
      if (vistos.add(pedido.restauranteId)) {
        resultado.add(pedido);
      }
      if (resultado.length == 2) break;
    }

    return resultado;
  }

  Restaurante? _restaurantePorId(int id) {
    for (final restaurante in restaurantes) {
      if (restaurante.id == id) return restaurante;
    }
    return null;
  }

  String _mensajeEstado(Pedido pedido) {
    if (pedido.pagoPendiente) {
      return 'Falta completar tu pago';
    }

    switch (pedido.estado) {
      case 'pendiente':
        return 'Buscando repartidor…';
      case 'aceptado':
        return 'Un repartidor aceptó tu pedido';
      case 'recogido':
        return 'Ya recogieron tu pedido';
      case 'en_camino':
        return 'Tu pedido va en camino';
      default:
        return textoEstado(pedido.estado);
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'pendiente':
        return ambar;
      case 'aceptado':
        return turquesa;
      case 'recogido':
      case 'en_camino':
        return verdeClaro;
      default:
        return verdeOscuro;
    }
  }

  // =====================================================
  // NOTIFICACIONES (Sprint 4, historia #15)
  // =====================================================

  Future<void> _sincronizarNotificaciones() async {
    if (!_esCliente) return;

    final token = widget.usuario.token;

    try {
      final nuevas = await NotificacionService.listar(
        token,
        desdeId: _ultimoNotificacionId,
        limite: _primeraSincronizacion ? 1 : 20,
      );
      final pendientes = await NotificacionService.noLeidas(token);

      if (!mounted) return;

      // La más nueva viene primero.
      if (nuevas.isNotEmpty) _ultimoNotificacionId = nuevas.first.id;

      // La primera vez solo se toma nota de las que ya existen
      // (sin avisos).
      if (!_primeraSincronizacion && nuevas.isNotEmpty) {
        _mostrarAviso(nuevas.first);
      }

      _primeraSincronizacion = false;
      setState(() => noLeidas = pendientes);
    } catch (e) {
      // Sin red: se reintenta en el siguiente ciclo.
      debugPrint('No se pudieron sincronizar las notificaciones: $e');
    }
  }

  void _mostrarAviso(Notificacion n) {
    final pedidoId = n.pedidoId;
    final mensajero = ScaffoldMessenger.of(context);

    mensajero.hideCurrentSnackBar();
    mensajero.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: verdeOscuro,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n.titulo,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              n.mensaje,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
        action: pedidoId == null
            ? null
            : SnackBarAction(
                label: 'Ver',
                textColor: verdeClaro,
                onPressed: () => _abrirRastreo(pedidoId),
              ),
      ),
    );
  }

  Future<void> _abrirRastreo(int pedidoId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RastreoScreen(
          usuario: widget.usuario,
          pedidoId: pedidoId,
        ),
      ),
    );

    if (mounted) _cargarPedidos();
  }

  Future<void> _abrirNotificaciones() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificacionesScreen(usuario: widget.usuario),
      ),
    );

    if (mounted) _sincronizarNotificaciones();
  }

  void _abrirPanelAdmin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminScreen(usuario: widget.usuario),
      ),
    );
  }

  // =====================================================
  // CATEGORÍAS
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

  String _categoriaTexto(String? categoria, String nombre) {
    final texto = _normalizar('${categoria ?? ''} $nombre');

    if (texto.contains('pizza') ||
        texto.contains('pizzeria')) {
      return 'Pizza';
    }

    if (texto.contains('taco') ||
        texto.contains('mexicana') ||
        texto.contains('taqueria')) {
      return 'Tacos';
    }

    if (texto.contains('hamburgues') ||
        texto.contains('burger')) {
      return 'Hamburguesas';
    }

    if (texto.contains('sushi') ||
        texto.contains('japones')) {
      return 'Sushi';
    }

    if (texto.contains('postre') ||
        texto.contains('pasteleria') ||
        texto.contains('reposteria')) {
      return 'Postres';
    }

    if (texto.contains('cafe') ||
        texto.contains('cafeteria')) {
      return 'Café';
    }

    return 'Otros';
  }

  String _categoriaDe(Restaurante restaurante) {
    return _categoriaTexto(
      restaurante.categoria,
      restaurante.nombre,
    );
  }

  // Solo se muestran las categorías que sí devolvió la API.
  List<String> get _categoriasDisponibles {
    final presentes = restaurantes.map(_categoriaDe).toSet();

    return [
      'Todo',
      ..._ordenCategorias.where(presentes.contains),
    ];
  }

  IconData _iconoCategoria(String categoria) {
    switch (categoria) {
      case 'Todo':
        return Icons.apps;
      case 'Pizza':
        return Icons.local_pizza_outlined;
      case 'Tacos':
        return Icons.lunch_dining_outlined;
      case 'Hamburguesas':
        return Icons.fastfood_outlined;
      case 'Sushi':
        return Icons.rice_bowl_outlined;
      case 'Postres':
        return Icons.cake_outlined;
      case 'Café':
        return Icons.coffee_outlined;
      default:
        return Icons.restaurant_outlined;
    }
  }

  // Foto según la categoría. Más adelante, si el backend manda
  // una foto real, se usa esa y esta queda como respaldo.
  String _imagenCategoria(String categoria) {
    switch (categoria) {
      case 'Pizza':
        return 'assets/images/$_prefijoFoto-pizza.png';

      case 'Tacos':
        return 'assets/images/$_prefijoFoto-tacos.png';

      case 'Hamburguesas':
        return 'assets/images/$_prefijoFoto-hamburguesas.png';

      case 'Sushi':
        return 'assets/images/$_prefijoFoto-sushi.png';

      case 'Postres':
        return 'assets/images/$_prefijoFoto-postres.png';

      case 'Café':
        return 'assets/images/$_prefijoFoto-cafe.png';

      default:
        return 'assets/images/$_prefijoFoto-general.png';
    }
  }

  List<Restaurante> get restaurantesFiltrados {
    final texto = _normalizar(busqueda.trim());

    final resultado = restaurantes.where((restaurante) {
      final categoria = _categoriaDe(restaurante);

      final coincideCategoria =
          categoriaSeleccionada == 'Todo' ||
          categoria == categoriaSeleccionada;

      final coincideBusqueda = texto.isEmpty ||
          _normalizar(restaurante.nombre).contains(texto) ||
          _normalizar(restaurante.categoria ?? '')
              .contains(texto);

      final dentroDelRadio = restaurante.distanciaKm <= radioKm;

      return coincideCategoria &&
          coincideBusqueda &&
          dentroDelRadio;
    }).toList();

    // La API sí proporciona distancia real.
    // No inventamos calificaciones ni tiempos.
    resultado.sort(
      (a, b) => a.distanciaKm.compareTo(b.distanciaKm),
    );

    return resultado;
  }

  void _limpiarFiltros() {
    _busquedaController.clear();

    setState(() {
      busqueda = '';
      categoriaSeleccionada = 'Todo';
      radioKm = 10;
    });
  }

  // =====================================================
  // NAVEGACIÓN
  // =====================================================

  Future<void> _abrirRestaurante(Restaurante restaurante) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          restaurante: restaurante,
          usuario: widget.usuario,
        ),
      ),
    );

    if (mounted) _cargarPedidos();
  }

  Future<void> _abrirCarrito() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarritoScreen(
          usuario: widget.usuario,
        ),
      ),
    );

    if (mounted) _cargarPedidos();
  }

  Future<void> _abrirPedidos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MisPedidosScreen(
          usuario: widget.usuario,
        ),
      ),
    );

    if (mounted) _cargarPedidos();
  }

  void _abrirPanelRepartidor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepartidorScreen(
          usuario: widget.usuario,
        ),
      ),
    );
  }

  void _cerrarSesion() {
    CarritoService.instance.vaciar();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  // "Pedir ahora": baja hasta la lista de restaurantes.
  void _irALista() {
    final contexto = _claveLista.currentContext;

    if (contexto == null) return;

    Scrollable.ensureVisible(
      contexto,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  // "Volver a pedir": abre el menú del restaurante.
  void _volverAPedir(Pedido pedido) {
    final restaurante = _restaurantePorId(pedido.restauranteId);

    if (restaurante == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${pedido.restaurante} no está cerca de ti '
            'en este momento.',
          ),
        ),
      );
      return;
    }

    _abrirRestaurante(restaurante);
  }

  // =====================================================
  // BARRA SUPERIOR
  // =====================================================

  Widget _accionHeader({
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        icono,
        color: verdeOscuro,
        size: 25,
      ),
      label: Text(
        texto,
        style: const TextStyle(
          color: verdeOscuro,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Carrito con cuadrito verde (esquinas rectas)
  // que muestra cuántas piezas lleva.
  Widget _botonCarrito() {
    return ListenableBuilder(
      listenable: CarritoService.instance,
      builder: (context, _) {
        final cantidad =
            CarritoService.instance.totalPiezas;

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
                    constraints: const BoxConstraints(
                      minWidth: 19,
                    ),
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

  // Campana con cuadrito verde (esquinas rectas) que muestra
  // cuántas notificaciones no se han leído.
  Widget _botonNotificaciones() {
    return IconButton(
      tooltip: 'Notificaciones',
      onPressed: _abrirNotificaciones,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_outlined,
            size: 29,
            color: verdeOscuro,
          ),
          if (noLeidas > 0)
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
                  '$noLeidas',
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
  }

  Widget _cuenta() {
    return PopupMenuButton<String>(
      tooltip: 'Mi cuenta',
      onSelected: (valor) {
        if (valor == 'salir') {
          _cerrarSesion();
        }

        if (valor == 'actualizar') {
          buscarRestaurantes();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            widget.usuario.nombre,
            style: const TextStyle(
              color: verdeOscuro,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'actualizar',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 19),
              SizedBox(width: 9),
              Text('Actualizar restaurantes'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'salir',
          child: Row(
            children: [
              Icon(Icons.logout, size: 19),
              SizedBox(width: 9),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 27,
              color: verdeOscuro,
            ),
            SizedBox(width: 8),
            Text(
              'Mi cuenta',
              style: TextStyle(
                color: verdeOscuro,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // El buscador filtra por nombre y categoría
  // (no por platillos), por eso el texto de ayuda.
  Widget _buscador() {
    return TextField(
      controller: _busquedaController,
      onChanged: (valor) {
        setState(() => busqueda = valor);
      },
      style: const TextStyle(
        fontSize: 16,
        color: verdeOscuro,
      ),
      decoration: InputDecoration(
        hintText: 'Busca restaurantes o categorías',
        hintStyle: const TextStyle(
          color: grisTexto,
          fontSize: 15,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: verdeOscuro,
          size: 29,
        ),
        suffixIcon: busqueda.isNotEmpty
            ? IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _busquedaController.clear();
                  setState(() => busqueda = '');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(
            color: verdeOscuro,
            width: 1.5,
          ),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(
            color: turquesa,
            width: 2,
          ),
        ),
      ),
    );
  }

  // Ubicación en dos líneas (escritorio).
  Widget _ubicacion() {
    return InkWell(
      onTap: buscarRestaurantes,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_outlined,
            color: verdeOscuro,
            size: 29,
          ),
          SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entregar en',
                style: TextStyle(
                  color: grisTexto,
                  fontSize: 13,
                ),
              ),
              Row(
                children: [
                  Text(
                    'Tu ubicación actual',
                    style: TextStyle(
                      color: verdeOscuro,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: verdeOscuro,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Ubicación en una línea (compacto).
  Widget _ubicacionCompacta() {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: buscarRestaurantes,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                color: verdeOscuro,
                size: 19,
              ),
              SizedBox(width: 6),
              Text(
                'Entregar en ',
                style: TextStyle(
                  color: grisTexto,
                  fontSize: 13,
                ),
              ),
              Text(
                'Tu ubicación actual',
                style: TextStyle(
                  color: verdeOscuro,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: verdeOscuro,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool compacto) {
    if (compacto) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: grisBorde),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/images/logo-food-express.png',
                  width: 165,
                  height: 55,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                if (_esCliente)
                  IconButton(
                    tooltip: 'Mis pedidos',
                    onPressed: _abrirPedidos,
                    icon: const Icon(
                      Icons.receipt_long_outlined,
                      color: verdeOscuro,
                    ),
                  ),
                if (widget.usuario.rol == 'repartidor')
                  IconButton(
                    tooltip: 'Panel del repartidor',
                    onPressed: _abrirPanelRepartidor,
                    icon: const Icon(
                      Icons.delivery_dining_outlined,
                      color: verdeOscuro,
                    ),
                  ),
                if (_esAdmin)
                  IconButton(
                    tooltip: 'Panel administrativo',
                    onPressed: _abrirPanelAdmin,
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: verdeOscuro,
                    ),
                  ),
                if (_esCliente) _botonNotificaciones(),
                if (_esCliente) _botonCarrito(),
                _cuenta(),
              ],
            ),
            _ubicacionCompacta(),
            _buscador(),
          ],
        ),
      );
    }

    return Container(
      height: 102,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: grisBorde),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 42,
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo-food-express.png',
            width: 215,
            height: 75,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 40),
          _ubicacion(),
          const SizedBox(width: 40),
          Expanded(
            child: _buscador(),
          ),
          const SizedBox(width: 32),
          if (_esCliente) ...[
            _accionHeader(
              icono: Icons.receipt_long_outlined,
              texto: 'Pedidos',
              onTap: _abrirPedidos,
            ),
            const SizedBox(width: 10),
            _botonNotificaciones(),
            const SizedBox(width: 10),
            _botonCarrito(),
            const SizedBox(width: 15),
          ],
          if (widget.usuario.rol == 'repartidor')
            _accionHeader(
              icono: Icons.delivery_dining_outlined,
              texto: 'Repartidor',
              onTap: _abrirPanelRepartidor,
            ),
          if (_esAdmin)
            _accionHeader(
              icono: Icons.admin_panel_settings_outlined,
              texto: 'Administración',
              onTap: _abrirPanelAdmin,
            ),
          const SizedBox(width: 14),
          _cuenta(),
        ],
      ),
    );
  }

  // =====================================================
  // BANNER
  // =====================================================

  Widget _banner(bool compacto) {
    return SizedBox(
      width: double.infinity,
      height: compacto ? 245 : 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // IMAGEN: solamente el fondo ilustrado (sin texto).
          // Su lado izquierdo ya es oscuro, por eso
          // no hace falta ningún degradado encima.
          Image.asset(
            'assets/images/banner-promo.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),

          // TEXTO Y BOTÓN HECHOS CON FLUTTER.
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compacto ? 24 : 75,
              vertical: compacto ? 20 : 25,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compacto ? 340 : 720,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      color: verdeClaro,
                      child: Text(
                        'ENTREGAS EN NICOLÁS ROMERO',
                        style: TextStyle(
                          color: verdeOscuro,
                          fontSize: compacto ? 11 : 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tu antojo, en camino',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 31 : 52,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Pide en los restaurantes cercanos a ti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 16 : 22,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: compacto ? 200 : 240,
                      height: compacto ? 46 : 54,
                      child: ElevatedButton(
                        onPressed: _irALista,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: turquesa,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(),
                        ),
                        child: Text(
                          'Pedir ahora',
                          style: TextStyle(
                            fontSize: compacto ? 17 : 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TARJETA DE PEDIDO ACTIVO
  // =====================================================

  Widget _pildora(String texto, Color colorFondo, Color colorTexto) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: colorTexto,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _puntoPaso({
    required bool hecho,
    required bool actual,
    required bool enCamino,
  }) {
    if (actual) {
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: turquesa,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: enCamino
              ? const Icon(
                  Icons.delivery_dining,
                  color: Colors.white,
                  size: 19,
                )
              : Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      );
    }

    if (hecho) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: turquesa,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          color: Colors.white,
          size: 14,
        ),
      );
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: grisBorde, width: 2),
      ),
    );
  }

  // Barra de 5 pasos: Pendiente → Entregado.
  Widget _barraProgreso(Pedido pedido, bool compacto) {
    final encontrado = _pasos.indexOf(pedido.estado);
    final indice = encontrado < 0 ? 0 : encontrado;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_pasos.length, (i) {
        final esPrimero = i == 0;
        final esUltimo = i == _pasos.length - 1;

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        color: esPrimero
                            ? Colors.transparent
                            : (i <= indice ? turquesa : grisBorde),
                      ),
                    ),
                    _puntoPaso(
                      hecho: i < indice,
                      actual: i == indice,
                      enCamino: _pasos[i] == 'en_camino',
                    ),
                    Expanded(
                      child: Container(
                        height: 3,
                        color: esUltimo
                            ? Colors.transparent
                            : (i < indice ? turquesa : grisBorde),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                textoEstado(_pasos[i]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compacto ? 11 : 12,
                  color: i <= indice ? verdeOscuro : grisTexto,
                  fontWeight: i == indice
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _tarjetaPedidoActivo(bool compacto) {
    final pedido = _pedidoActivo;

    if (!_esCliente || pedido == null) {
      return const SizedBox.shrink();
    }

    final colorEstado = _colorEstado(pedido.estado);
    final colorTextoEstado =
        pedido.estado == 'aceptado' ? Colors.white : verdeOscuro;

    final icono = Container(
      width: 54,
      height: 54,
      color: const Color(0xFFE5F5F3),
      child: const Icon(
        Icons.delivery_dining,
        color: turquesa,
        size: 34,
      ),
    );

    final informacion = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pedido #${pedido.id} · ${pedido.restaurante}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: verdeOscuro,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _pildora(
              textoEstado(pedido.estado),
              colorEstado,
              colorTextoEstado,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _mensajeEstado(pedido),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: grisTexto,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final boton = OutlinedButton(
      // Si falta pagar, "Mis pedidos" permite completar el pago;
      // si no, se abre el seguimiento de ese pedido.
      onPressed: () => pedido.pagoPendiente
          ? _abrirPedidos()
          : _abrirRastreo(pedido.id),
      style: OutlinedButton.styleFrom(
        foregroundColor: turquesa,
        side: const BorderSide(color: turquesa, width: 1.5),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 16,
        ),
      ),
      child: const Text(
        'Ver seguimiento',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final contenido = compacto
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icono,
                  const SizedBox(width: 14),
                  Expanded(child: informacion),
                ],
              ),
              const SizedBox(height: 16),
              _barraProgreso(pedido, true),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: boton),
            ],
          )
        : Row(
            children: [
              icono,
              const SizedBox(width: 16),
              SizedBox(width: 290, child: informacion),
              const SizedBox(width: 28),
              Expanded(child: _barraProgreso(pedido, false)),
              const SizedBox(width: 28),
              boton,
            ],
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compacto ? 24 : 75,
        22,
        compacto ? 24 : 75,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: verdeClaro, width: 4),
            top: BorderSide(color: grisBorde),
            right: BorderSide(color: grisBorde),
            bottom: BorderSide(color: grisBorde),
          ),
        ),
        child: contenido,
      ),
    );
  }

  // =====================================================
  // BARRA DE CATEGORÍAS
  // =====================================================

  Widget _categoria(String nombre) {
    final seleccionado = categoriaSeleccionada == nombre;

    return InkWell(
      onTap: () {
        setState(() {
          categoriaSeleccionada = nombre;
        });
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.only(
          top: 15,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: seleccionado ? turquesa : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconoCategoria(nombre),
              size: 35,
              color: seleccionado ? turquesa : verdeOscuro,
            ),
            const SizedBox(height: 5),
            Text(
              nombre,
              style: TextStyle(
                fontSize: 16,
                color: seleccionado ? turquesa : grisTexto,
                fontWeight: seleccionado
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraCategorias() {
    // Separación solo si hay tarjeta de pedido encima.
    final hayTarjeta = _esCliente && _pedidoActivo != null;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: hayTarjeta ? 22 : 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: grisBorde),
          bottom: BorderSide(color: grisBorde),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              // Ocupa al menos todo el ancho de la pantalla
              // para que spaceAround reparta las categorías.
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _categoriasDisponibles
                    .map(_categoria)
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  // =====================================================
  // FILTROS DE RESTAURANTES
  // =====================================================

  Widget _filtro({
    required String nombre,
    required VoidCallback onTap,
    bool activo = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: activo ? turquesa : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          nombre,
          style: TextStyle(
            color: activo ? turquesa : grisTexto,
            fontSize: 15,
            fontWeight: activo ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Menú "Radio: 10 km". La API ya devuelve hasta 10 km,
  // así que aquí solo se acota la lista.
  Widget _filtroRadio() {
    return PopupMenuButton<double>(
      tooltip: 'Radio de búsqueda',
      initialValue: radioKm,
      onSelected: (valor) {
        setState(() => radioKm = valor);
      },
      itemBuilder: (_) => _opcionesRadio
          .map(
            (valor) => PopupMenuItem<double>(
              value: valor,
              child: Text('${valor.toStringAsFixed(0)} km'),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: grisBorde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Radio: ${radioKm.toStringAsFixed(0)} km',
              style: const TextStyle(
                color: verdeOscuro,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: verdeOscuro,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _accionActualizar() {
    return InkWell(
      onTap: buscarRestaurantes,
      child: const Padding(
        padding: EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 18, color: grisTexto),
            SizedBox(width: 5),
            Text(
              'Actualizar',
              style: TextStyle(
                color: grisTexto,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezadoRestaurantes(bool compacto) {
    final titulo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Restaurantes cercanos',
            style: TextStyle(
              color: verdeOscuro,
              fontSize: compacto ? 26 : 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(width: 15),
        Text(
          '${restaurantesFiltrados.length} disponibles',
          style: const TextStyle(
            color: grisTexto,
            fontSize: 15,
          ),
        ),
      ],
    );

    final filtros = Wrap(
      spacing: 20,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filtroRadio(),
        _filtro(
          nombre: 'Más cercanos',
          activo: filtroSeleccionado == 'Más cercanos',
          onTap: () {
            setState(() {
              filtroSeleccionado = 'Más cercanos';
            });
          },
        ),
        _accionActualizar(),
      ],
    );

    if (compacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titulo,
          const SizedBox(height: 14),
          filtros,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titulo),
        filtros,
      ],
    );
  }

  // =====================================================
  // CUADRÍCULA Y TARJETAS
  // =====================================================

  // Reparte las tarjetas en 4, 3, 2 o 1 columnas según el ancho.
  // El alto se calcula con el ancho real de la tarjeta, así no
  // se desborda ("BOTTOM OVERFLOWED").
  Widget _cuadricula({
    required int cantidad,
    required Widget Function(int) construir,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;

        final columnas = ancho >= 1250
            ? 4
            : ancho >= 850
                ? 3
                : ancho >= 520
                    ? 2
                    : 1;

        const espacio = 24.0;

        final anchoTarjeta =
            (ancho - espacio * (columnas - 1)) / columnas;
        final altoTarjeta =
            anchoTarjeta / _proporcionImagen + _altoTextoTarjeta;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cantidad,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            crossAxisSpacing: espacio,
            mainAxisSpacing: 28,
            mainAxisExtent: altoTarjeta,
          ),
          itemBuilder: (context, index) => construir(index),
        );
      },
    );
  }

  Widget _tarjetaRestaurante(Restaurante restaurante) {
    final categoria = _categoriaDe(restaurante);
    final etiqueta = (restaurante.categoria ?? '').trim();

    return InkWell(
      onTap: () => _abrirRestaurante(restaurante),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: grisBorde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto con esquinas rectas y la categoría encima.
            AspectRatio(
              aspectRatio: _proporcionImagen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _imagenCategoria(categoria),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _sinImagen(),
                  ),
                  if (etiqueta.isNotEmpty)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        color: Colors.white,
                        child: Text(
                          etiqueta,
                          style: const TextStyle(
                            color: verdeOscuro,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurante.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: verdeOscuro,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: turquesa,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${restaurante.distanciaKm.toStringAsFixed(2)} km de ti',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: grisTexto,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // El envío real depende de la distancia
                  // (base + por km, con mínimo de $30).
                  const Row(
                    children: [
                      Icon(
                        Icons.delivery_dining_outlined,
                        size: 18,
                        color: turquesa,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Envío desde \$30',
                        style: TextStyle(
                          color: grisTexto,
                          fontSize: 14,
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
    );
  }

  // Se muestra mientras no exista la imagen.
  Widget _sinImagen() {
    return Container(
      color: const Color(0xFFE5F5F3),
      child: const Center(
        child: Icon(
          Icons.storefront_outlined,
          size: 58,
          color: turquesa,
        ),
      ),
    );
  }

  // Tarjeta gris mientras llegan los restaurantes.
  Widget _tarjetaEsqueleto() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: _proporcionImagen,
            child: Container(color: grisBorde),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 16,
                  color: grisBorde,
                ),
                const SizedBox(height: 12),
                Container(
                  width: 100,
                  height: 12,
                  color: grisBorde,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CONTENIDO DINÁMICO
  // =====================================================

  Widget _contenidoRestaurantes() {
    if (cargando) {
      return Column(
        children: [
          _cuadricula(
            cantidad: 4,
            construir: (_) => _tarjetaEsqueleto(),
          ),
          const SizedBox(height: 22),
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

    if (mensajeError != null) {
      return Padding(
        padding: const EdgeInsets.all(45),
        child: Center(
          child: Column(
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 48,
                color: verdeOscuro,
              ),
              const SizedBox(height: 12),
              Text(
                mensajeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: verdeOscuro,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: buscarRestaurantes,
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

    final lista = restaurantesFiltrados;

    if (lista.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(45),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5F5F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 38,
                  color: turquesa,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No encontramos restaurantes '
                'con esos filtros.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: grisTexto,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _limpiarFiltros,
                style: OutlinedButton.styleFrom(
                  foregroundColor: turquesa,
                  side: const BorderSide(
                    color: turquesa,
                    width: 1.5,
                  ),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 14,
                  ),
                ),
                child: const Text('Ver todos'),
              ),
            ],
          ),
        ),
      );
    }

    return _cuadricula(
      cantidad: lista.length,
      construir: (index) => _tarjetaRestaurante(lista[index]),
    );
  }

  // =====================================================
  // PIDE DE NUEVO
  // =====================================================

  Widget _tarjetaRepetir(Pedido pedido) {
    final restaurante = _restaurantePorId(pedido.restauranteId);
    final categoria =
        _categoriaTexto(restaurante?.categoria, pedido.restaurante);

    var detalle = '';
    if (pedido.items.isNotEmpty) {
      final primero = pedido.items.first;
      final otros = pedido.items.length - 1;

      detalle = '${primero.cantidad}× ${primero.nombre}';
      if (otros > 0) detalle = '$detalle y $otros más';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Image.asset(
              _imagenCategoria(categoria),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _sinImagen(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pedido.restaurante,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: verdeOscuro,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$detalle · ${dinero(pedido.total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grisTexto,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => _volverAPedir(pedido),
            style: OutlinedButton.styleFrom(
              foregroundColor: turquesa,
              side: const BorderSide(color: turquesa, width: 1.5),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            child: const Text(
              'Volver a pedir',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionPideDeNuevo(bool compacto) {
    final lista = _pedidosParaRepetir;

    if (!_esCliente || lista.isEmpty) {
      return const SizedBox.shrink();
    }

    final tarjetas = lista.map(_tarjetaRepetir).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pide de nuevo',
                  style: TextStyle(
                    color: verdeOscuro,
                    fontSize: compacto ? 24 : 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              InkWell(
                onTap: _abrirPedidos,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver historial',
                        style: TextStyle(
                          color: turquesa,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: turquesa,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (compacto)
            Column(
              children: [
                for (var i = 0; i < tarjetas.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  tarjetas[i],
                ],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tarjetas.length; i++) ...[
                  if (i > 0) const SizedBox(width: 24),
                  Expanded(child: tarjetas[i]),
                ],
                // Si solo hay una, deja la otra mitad vacía.
                if (tarjetas.length == 1) ...[
                  const SizedBox(width: 24),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // =====================================================
  // BARRA FIJA DEL CARRITO
  // =====================================================

  Widget _barraCarrito() {
    if (!_esCliente) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: CarritoService.instance,
      builder: (context, _) {
        final carrito = CarritoService.instance;

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
                    const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                    ),
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
          final compacto = constraints.maxWidth < 1100;

          return Column(
            children: [
              _header(compacto),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _banner(compacto),
                      _tarjetaPedidoActivo(compacto),
                      _barraCategorias(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compacto ? 24 : 75,
                          25,
                          compacto ? 24 : 75,
                          35,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KeyedSubtree(
                              key: _claveLista,
                              child: _encabezadoRestaurantes(compacto),
                            ),
                            const SizedBox(height: 23),
                            _contenidoRestaurantes(),
                            _seccionPideDeNuevo(compacto),
                          ],
                        ),
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