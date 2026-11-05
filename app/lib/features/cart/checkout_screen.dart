import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_service.dart';
import '../maps/mapas_service.dart';
import 'carrito_service.dart';
import 'mis_pedidos_screen.dart';
import 'pago_screen.dart';

/// Mapa claro; aquí SÍ se ven los lugares (escuelas, tiendas…) porque sirven
/// de referencia para colocar el pin. Solo se oculta el transporte.
const String _estiloMapa =
    '[{"featureType":"transit","stylers":[{"visibility":"off"}]}]';

/// Pantalla 2 del wireframe del Sprint 3: "Pagar" (método de pago).
///
/// Sprint 5: la dirección escrita se valida con Google (Geocoding, vía el
/// backend). El cliente ve el pin en un mapa, lo puede arrastrar hasta su
/// puerta y el envío se recalcula con ese punto. [latitud] y [longitud]
/// (el GPS del carrito) quedan como estimación inicial y como opción
/// «Usar mi ubicación actual».
class CheckoutScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final double latitud;
  final double longitud;
  final double costoEnvio;

  const CheckoutScreen({
    super.key,
    required this.usuario,
    required this.latitud,
    required this.longitud,
    required this.costoEnvio,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final CarritoService carrito = CarritoService.instance;
  final _formKey = GlobalKey<FormState>();
  final _direccionController = TextEditingController();
  final _referenciaController = TextEditingController();

  String metodo = 'mercado_pago'; // 'mercado_pago' | 'efectivo'
  bool enviando = false;

  // ---- punto de entrega (validado con Google o tomado del GPS)
  LatLng? _punto;
  String? _direccionGoogle;
  String _textoValidado = '';
  bool _porGps = false;
  bool _aproximada = false;
  bool _buscando = false;
  bool _cotizando = false;

  /// Vista de satélite (techos y patios) para ubicar la puerta exacta.
  bool _satelite = false;

  /// Celular: resumen de compra que se abre con el carrito de la barra superior.
  bool _resumenAbierto = false;

  /// Pantalla ancha: la tarjeta del pedido siempre está; el carrito pliega
  /// o despliega el detalle (productos, subtotal y envío).
  bool _detalleOculto = false;

  /// true mientras el código cambia el texto de la dirección (no es el usuario).
  bool _ajustandoTexto = false;

  /// true cuando el punto actual ya fue aceptado por el backend (en zona).
  bool _zonaOk = false;
  String? _errorDireccion;
  double? _costoEnvio;
  double? _distanciaKm;
  GoogleMapController? _mapa;

  /// Dirección + referencia en un solo texto (así la ve el repartidor).
  String get _direccionCompleta {
    final base = _direccionController.text.trim();
    final referencia = _referenciaController.text.trim();
    final texto = referencia.isEmpty ? base : '$base · Ref: $referencia';
    return texto.length > 255 ? texto.substring(0, 255) : texto;
  }

  double get _envio => _costoEnvio ?? widget.costoEnvio;
  double get total => carrito.subtotal + _envio;

  @override
  void initState() {
    super.initState();
    _direccionController.addListener(_alEscribir);
  }

  @override
  void dispose() {
    _direccionController.dispose();
    _referenciaController.dispose();
    _mapa?.dispose();
    super.dispose();
  }

  /// Si cambia el texto, la dirección validada ya no le corresponde.
  void _alEscribir() {
    if (_ajustandoTexto) return;
    if (_punto == null || _porGps) return;
    if (_direccionController.text.trim() == _textoValidado) return;
    setState(() {
      _punto = null;
      _direccionGoogle = null;
      _zonaOk = false;
      _costoEnvio = null;
      _distanciaKm = null;
    });
  }

  /// Pide al backend (Geocoding de Google) las coordenadas de lo escrito.
  Future<void> _validarDireccion() async {
    final texto = _direccionController.text.trim();
    if (texto.length < 5) {
      setState(() => _errorDireccion = 'Escribe calle, número y colonia.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _buscando = true;
      _errorDireccion = null;
    });
    try {
      final r = await MapasService.geocodificar(widget.usuario.token, texto);
      if (!mounted) return;
      final exacta =
          r.precision == 'ROOFTOP' || r.precision == 'RANGE_INTERPOLATED';
      setState(() {
        _punto = LatLng(r.latitud, r.longitud);
        _direccionGoogle = r.direccionFormateada;
        _textoValidado = texto;
        _porGps = false;
        _aproximada = r.coincidenciaParcial || !exacta;
        _zonaOk = false;
      });
      _centrarMapa();
      await _recotizar();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorDireccion = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorDireccion =
              'No pudimos validar la dirección. Intenta de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  /// Usa el GPS que ya se obtuvo en el carrito.
  void _usarMiUbicacion() {
    FocusScope.of(context).unfocus();
    setState(() {
      _punto = LatLng(widget.latitud, widget.longitud);
      _direccionGoogle = 'Tu ubicación actual (GPS)';
      _porGps = true;
      _aproximada = false;
      _errorDireccion = null;
      _zonaOk = false;
    });
    _centrarMapa();
    _recotizar();
  }

  /// El cliente arrastró el pin hasta su puerta.
  void _alMoverPin(LatLng nuevo) {
    setState(() {
      _punto = nuevo;
      _direccionGoogle = 'Buscando dirección…';
      _aproximada = false;
      _errorDireccion = null;
      _zonaOk = false;
    });
    _recotizar();
    _direccionDelPin(nuevo);
  }

  /// Pregunta a Google qué calle es el punto donde quedó el pin y actualiza
  /// el texto de la dirección para que coincida con el mapa.
  Future<void> _direccionDelPin(LatLng punto) async {
    try {
      final direccion = await MapasService.direccionDe(
        widget.usuario.token,
        punto.latitude,
        punto.longitude,
      );
      // Si el pin ya se movió otra vez, esta respuesta quedó vieja.
      if (!mounted || _punto != punto) return;
      final corta = direccion.replaceAll(RegExp(r',\s*México$'), '');
      _ajustandoTexto = true;
      _direccionController.text = corta;
      _ajustandoTexto = false;
      setState(() {
        _direccionGoogle = corta;
        _textoValidado = corta;
        _porGps = false;
      });
    } catch (_) {
      if (!mounted || _punto != punto) return;
      setState(() => _direccionGoogle = 'Ubicación ajustada en el mapa');
    }
  }

  void _centrarMapa() {
    final punto = _punto;
    if (punto == null) {
      _mapa?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(widget.latitud, widget.longitud), 15),
      );
      return;
    }
    _mapa?.animateCamera(CameraUpdate.newLatLngZoom(punto, 18));
  }

  /// Recalcula el envío con el punto elegido. El backend también comprueba
  /// que el punto esté dentro de la zona de servicio.
  Future<void> _recotizar() async {
    final punto = _punto;
    final restaurante = carrito.restaurante;
    if (punto == null || restaurante == null) return;

    setState(() => _cotizando = true);
    try {
      final cot = await PedidoService.cotizar(
        widget.usuario.token,
        restauranteId: restaurante.id,
        items: carrito.itemsParaApi,
        latitud: punto.latitude,
        longitud: punto.longitude,
      );
      if (!mounted) return;
      setState(() {
        _costoEnvio = cot.costoEnvio;
        _distanciaKm = cot.distanciaKm;
        _zonaOk = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _zonaOk = false;
        _errorDireccion = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _zonaOk = false;
        _errorDireccion = 'No pudimos calcular el envío. Intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  Future<void> _pagar() async {
    if (!_formKey.currentState!.validate()) return;
    final restaurante = carrito.restaurante;
    if (restaurante == null || carrito.vacio) {
      showAppSnackBar(context, 'Tu carrito está vacío.');
      return;
    }
    final punto = _punto;
    if (punto == null || !_zonaOk) {
      showAppSnackBar(
        context,
        _cotizando
            ? 'Estamos calculando tu envío, espera un momento.'
            : 'Valida tu dirección en el mapa antes de pagar.',
      );
      return;
    }

    setState(() => enviando = true);
    try {
      final pedido = await PedidoService.crearPedido(
        widget.usuario.token,
        restauranteId: restaurante.id,
        items: carrito.itemsParaApi,
        direccion: _direccionCompleta,
        latitud: punto.latitude,
        longitud: punto.longitude,
        metodoPago: metodo,
      );
      carrito.vaciar();

      if (!mounted) return;
      if (metodo == 'efectivo') {
        irAMisPedidos(
          context,
          widget.usuario,
          mensaje:
              'Pedido #${pedido.id} confirmado. Pagas ${dinero(pedido.total)} en efectivo al recibirlo.',
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PagoScreen(
              usuario: widget.usuario,
              pedido: pedido,
              abrirAlInicio: true,
            ),
          ),
          (route) => route.isFirst,
        );
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo generar el pedido. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  // ======================================================================
  // DISEÑO — el mapa es el protagonista (igual que el panel del repartidor):
  // celular = mapa a pantalla completa con tarjetas encima; pantalla ancha =
  // panel a la izquierda y mapa grande a la derecha. Esquinas rectas, Poppins.
  // ======================================================================

  static const Color _linea = AppColors.border;
  static const Color _papel = Color(0xFFF3F6F5);
  static const Color _apagado = Color(0xFF7FA9A9);
  static const Color _naranja = Color(0xFFE07B00);

  bool get _listo => _punto != null && _zonaOk && !_cotizando && !enviando;

  TextStyle _rotulo({Color color = AppColors.primaryDark, double size = 10.5}) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: color,
    );
  }

  String _piezasTexto() {
    final n = carrito.totalPiezas;
    return '$n ${n == 1 ? 'producto' : 'productos'}';
  }

  /// Texto corto de estado / desglose bajo el total.
  String _lineaResumen() {
    if (enviando) return 'Generando tu pedido…';
    if (_punto == null) return 'Valida tu dirección para continuar';
    if (_cotizando) return 'Calculando envío…';
    if (!_zonaOk) return 'Revisa tu dirección';
    return 'Subtotal ${dinero(carrito.subtotal)} · Envío ${dinero(_envio)}';
  }

  @override
  Widget build(BuildContext context) {
    final arriba = MediaQuery.of(context).padding.top;
    final ancha = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: _papel,
      // El teclado no debe empujar las tarjetas sobre el mapa.
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56 + arriba),
        child: _barraSuperior(),
      ),
      body: Form(
        key: _formKey,
        child: ancha
            ? Row(
                children: [
                  Container(
                    width: 440,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: _linea)),
                    ),
                    child: _panelAncho(),
                  ),
                  Expanded(child: _mapaConControles(ancha: true)),
                ],
              )
            : _mapaConControles(ancha: false),
      ),
    );
  }

  // ------------------------------------------------------------ barra superior

  Widget _barraSuperior() {
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _linea)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  InkWell(
                    onTap: enviando ? null : () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(border: Border.all(color: _linea)),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.primaryDark,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Pagar', style: AppTypography.title(size: 22)),
                  const Spacer(),
                  Tooltip(
                    message: 'Resumen de compra',
                    child: InkWell(
                      onTap: () => setState(() {
                        if (MediaQuery.of(context).size.width >= 980) {
                          _detalleOculto = !_detalleOculto;
                        } else {
                          _resumenAbierto = !_resumenAbierto;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (MediaQuery.of(context).size.width >= 980
                                  ? !_detalleOculto
                                  : _resumenAbierto)
                              ? AppColors.background
                              : Colors.transparent,
                          border: Border.all(
                            color: (MediaQuery.of(context).size.width >= 980
                                    ? !_detalleOculto
                                    : _resumenAbierto)
                                ? AppColors.primary
                                : Colors.transparent,
                          ),
                        ),
                        child: ListenableBuilder(
                          listenable: carrito,
                          builder: (context, _) {
                            final n = carrito.totalPiezas;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 26,
                                  color: AppColors.primaryDark,
                                ),
                                if (n > 0)
                                  Positioned(
                                    top: -9,
                                    right: -12,
                                    child: Container(
                                      constraints:
                                          const BoxConstraints(minWidth: 18),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      color: AppColors.mint,
                                      child: Text(
                                        '$n',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.body(
                                          size: 11,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  const _LogoFE(ancho: 92),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- el mapa

  Widget _mapaGoogle({required bool ancha}) {
    final centro = _punto ?? LatLng(widget.latitud, widget.longitud);
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: centro,
        zoom: _punto != null ? 18 : 15,
      ),
      mapType: _satelite ? MapType.hybrid : MapType.normal,
      style: _satelite ? null : _estiloMapa,
      markers: _punto == null
          ? <Marker>{}
          : {
              Marker(
                markerId: const MarkerId('entrega'),
                position: _punto!,
                draggable: true,
                onDragEnd: _alMoverPin,
              ),
            },
      zoomControlsEnabled: ancha,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      onMapCreated: (c) => _mapa = c,
    );
  }

  Widget _mapaConControles({required bool ancha}) {
    return Stack(
      children: [
        Positioned.fill(child: _mapaGoogle(ancha: ancha)),
        if (ancha) ...[
          Positioned(right: 16, top: 16, child: _botonesMapa()),
          Positioned(right: 16, top: 70, child: _tarjetaPedidoAncha()),
          if (_punto != null)
            Positioned(
              left: 16,
              top: 16,
              child: _etiquetaMapa('Arrastra el pin hasta tu puerta'),
            ),
        ] else ...[
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(width: double.infinity, child: _tarjetaDireccion()),
                    const SizedBox(height: 8),
                    _botonesMapa(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 26,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _bloquePedido(),
              ),
            ),
          ),
        ],
        if (_resumenAbierto && !ancha)
          Positioned(
            right: ancha ? 16 : 10,
            top: ancha ? 70 : 10,
            child: _popoverResumen(
              ancha
                  ? 360
                  : (MediaQuery.of(context).size.width - 20 < 340
                      ? MediaQuery.of(context).size.width - 20
                      : 340),
            ),
          ),
      ],
    );
  }

  /// Resumen de compra: se abre con el carrito de la barra superior.
  Widget _popoverResumen(double ancho) {
    const divisor = SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: _linea),
    );
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(BorderSide(color: _linea)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: carrito,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('RESUMEN DE COMPRA', style: _rotulo(size: 10)),
                      ),
                      InkWell(
                        onTap: () => setState(() => _resumenAbierto = false),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${carrito.restaurante?.nombre ?? 'Tu pedido'} · ${_piezasTexto()}',
                    style: AppTypography.body(color: AppColors.hint, size: 12.5),
                  ),
                  const SizedBox(height: 12),
                  for (final l in carrito.lineas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${l.cantidad}× ${l.producto.nombre}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(size: 13),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            dinero(l.importe),
                            style: AppTypography.body(
                              weight: FontWeight.w600,
                              size: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  divisor,
                  const SizedBox(height: 10),
                  _filaMonto('Subtotal', dinero(carrito.subtotal)),
                  const SizedBox(height: 8),
                  _filaMonto(
                    'Envío',
                    _cotizando ? '…' : dinero(_envio),
                    detalle: _detalleEnvio(),
                  ),
                  const SizedBox(height: 10),
                  divisor,
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('TOTAL', style: _rotulo(size: 12)),
                      Text(dinero(total), style: AppTypography.title(size: 26)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _etiquetaMapa(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _linea),
      ),
      child: Text(texto, style: _rotulo(size: 9.5)),
    );
  }

  /// Botón cuadrado (esquinas rectas) para el mapa y la barra de búsqueda.
  Widget _botonCuadro({
    required IconData icono,
    required String tooltip,
    required VoidCallback? onTap,
    bool relleno = false,
    bool cargando = false,
    double lado = 46,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: relleno ? AppColors.primaryDark : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: lado,
            height: lado,
            decoration: BoxDecoration(
              border: Border.all(
                color: relleno ? AppColors.primaryDark : _linea,
              ),
            ),
            child: cargando
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    icono,
                    size: 21,
                    color: relleno ? Colors.white : AppColors.primaryDark,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _botonesMapa() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _botonCuadro(
          icono: _satelite ? Icons.map_outlined : Icons.satellite_alt,
          tooltip: _satelite ? 'Ver mapa' : 'Ver satélite',
          onTap: () => setState(() => _satelite = !_satelite),
          lado: 42,
        ),
        const SizedBox(width: 8),
        _botonCuadro(
          icono: Icons.filter_center_focus,
          tooltip: 'Centrar mapa',
          onTap: _centrarMapa,
          lado: 42,
        ),
      ],
    );
  }

  // ------------------------------------------------------------- campos

  /// Campo de texto de esquinas rectas.
  Widget _campo({
    required TextEditingController controller,
    required String hint,
    required IconData icono,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
    TextInputAction? accion,
  }) {
    OutlineInputBorder borde(Color color, [double ancho = 1.4]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: color, width: ancho),
      );
    }

    return TextFormField(
      controller: controller,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      textInputAction: accion,
      style: AppTypography.body(size: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body(color: AppColors.hint, size: 13.5),
        prefixIcon: Icon(icono, color: AppColors.primaryDark, size: 21),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: borde(_linea),
        enabledBorder: borde(_linea),
        focusedBorder: borde(AppColors.primaryDark, 2),
        errorBorder: borde(AppColors.error),
        focusedErrorBorder: borde(AppColors.error, 2),
        errorStyle: AppTypography.body(color: AppColors.error, size: 11.5),
      ),
    );
  }

  /// Dirección + [mi ubicación] + [validar]. Enter también valida.
  Widget _filaBusqueda() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _campo(
            controller: _direccionController,
            hint: 'Calle, número y colonia',
            icono: Icons.location_on_outlined,
            accion: TextInputAction.search,
            onSubmitted: (_) {
              if (!_buscando && !enviando) _validarDireccion();
            },
            validator: (valor) {
              if (valor == null || valor.trim().length < 3) {
                return 'Escribe tu dirección de entrega.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 8),
        _botonCuadro(
          icono: Icons.my_location,
          tooltip: 'Usar mi ubicación actual',
          onTap: (_buscando || enviando) ? null : _usarMiUbicacion,
          lado: 46,
        ),
        const SizedBox(width: 8),
        _botonCuadro(
          icono: Icons.search,
          tooltip: 'Validar en el mapa',
          onTap: (_buscando || enviando) ? null : _validarDireccion,
          relleno: true,
          cargando: _buscando,
          lado: 46,
        ),
      ],
    );
  }

  Widget _campoReferencia() {
    return _campo(
      controller: _referenciaController,
      hint: 'Referencia: Puerta 4, portón negro, junto a la tiendita',
      icono: Icons.flag_outlined,
      accion: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
    );
  }

  Widget _estadoDireccion({required bool compacto}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _zonaOk ? Icons.check_circle : Icons.pending_outlined,
              size: 19,
              color: _zonaOk ? AppColors.primary : AppColors.hint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _direccionGoogle ?? '',
                maxLines: compacto ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(
                  weight: FontWeight.w600,
                  size: compacto ? 12.5 : 13.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _aproximada
              ? (compacto
                  ? 'Aproximada: arrastra el pin al punto exacto.'
                  : 'Ubicación aproximada: Google solo ubicó la calle. Arrastra el pin al punto exacto (tu puerta, la entrada…) y escribe una referencia.')
              : 'Si el pin no está justo en tu puerta, arrástralo.',
          style: AppTypography.body(
            color: _aproximada ? AppColors.error : AppColors.hint,
            size: compacto ? 11.5 : 12,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------ celular: tarjeta de dirección

  Widget _tarjetaDireccion() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 4),
          top: BorderSide(color: _linea),
          right: BorderSide(color: _linea),
          bottom: BorderSide(color: _linea),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('DIRECCIÓN DE ENTREGA', style: _rotulo(size: 9.5)),
          const SizedBox(height: 8),
          _filaBusqueda(),
          if (_errorDireccion != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorDireccion!,
              style: AppTypography.body(color: AppColors.error, size: 12),
            ),
          ],
          if (_punto != null) ...[
            const SizedBox(height: 10),
            _estadoDireccion(compacto: true),
            const SizedBox(height: 8),
            _campoReferencia(),
          ],
        ],
      ),
    );
  }

  // ------------------------------------- celular: bloque de pago y confirmar

  Widget _bloquePedido() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 4),
          top: BorderSide(color: _linea),
          right: BorderSide(color: _linea),
          bottom: BorderSide(color: _linea),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _selectorPago(compacto: true),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TOTAL', style: _rotulo(size: 9.5)),
                    Text(dinero(total), style: AppTypography.title(size: 24)),
                    Text(
                      _lineaResumen(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        color: _listo ? AppColors.hint : _naranja,
                        size: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 162, child: _botonPagar()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonPagar({double alto = 52}) {
    final etiqueta = metodo == 'efectivo' ? 'CONFIRMAR' : 'PAGAR';
    return SizedBox(
      height: alto,
      child: Material(
        color: _listo || enviando ? AppColors.primaryDark : _apagado,
        child: InkWell(
          onTap: enviando ? null : _pagar,
          child: Center(
            child: enviando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        etiqueta,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.arrow_forward,
                        size: 19,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- método de pago

  Widget _selectorPago({required bool compacto}) {
    final mercadoPago = _opcionPago(
      valor: 'mercado_pago',
      titulo: 'Mercado Pago',
      detalle: 'Paga en línea de forma segura',
      icono: Icons.account_balance_wallet_outlined,
      compacto: compacto,
    );
    final efectivo = _opcionPago(
      valor: 'efectivo',
      titulo: 'Efectivo',
      detalle: 'Paga al repartidor al recibir',
      icono: Icons.payments_outlined,
      compacto: compacto,
    );
    if (compacto) {
      return Row(
        children: [
          Expanded(child: mercadoPago),
          const SizedBox(width: 8),
          Expanded(child: efectivo),
        ],
      );
    }
    return Column(
      children: [mercadoPago, const SizedBox(height: 10), efectivo],
    );
  }

  Widget _opcionPago({
    required String valor,
    required String titulo,
    required String detalle,
    required IconData icono,
    required bool compacto,
  }) {
    final seleccionado = metodo == valor;

    if (compacto) {
      return Material(
        color: seleccionado ? AppColors.primaryDark : Colors.white,
        child: InkWell(
          onTap: enviando ? null : () => setState(() => metodo = valor),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: seleccionado ? AppColors.primaryDark : _linea,
                width: 1.3,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icono,
                  size: 19,
                  color: seleccionado ? Colors.white : AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: seleccionado ? Colors.white : AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: seleccionado ? AppColors.background : Colors.white,
      child: InkWell(
        onTap: enviando ? null : () => setState(() => metodo = valor),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: seleccionado ? AppColors.primary : _linea,
              width: seleccionado ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _linea),
                ),
                child: Icon(icono, color: AppColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: AppTypography.body(
                        weight: FontWeight.w700,
                        size: 15,
                      ),
                    ),
                    Text(
                      detalle,
                      style: AppTypography.body(
                        color: AppColors.hint,
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                seleccionado
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: seleccionado ? AppColors.primary : AppColors.hint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------- pantalla ancha: panel izquierdo

  String _detalleEnvio() {
    if (_cotizando) return 'Calculando…';
    if (_zonaOk) {
      final km = _distanciaKm == null
          ? ''
          : ' · ${_distanciaKm!.toStringAsFixed(1)} km';
      return 'Calculado para tu dirección$km';
    }
    return 'Estimado · se confirma al validar tu dirección';
  }

  Widget _filaMonto(String etiqueta, String valor, {String? detalle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: AppTypography.body(color: AppColors.hint, size: 14.5),
              ),
              if (detalle != null)
                Text(
                  detalle,
                  style: AppTypography.body(color: AppColors.hint, size: 11.5),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(valor, style: AppTypography.body(weight: FontWeight.w600, size: 14.5)),
      ],
    );
  }

  /// Pantalla ancha: UNA sola tarjeta sobre el mapa, a la derecha, con todo
  /// el pedido (productos, subtotal, envío, total) y el botón de pagar.
  Widget _tarjetaPedidoAncha() {
    const divisor = SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: _linea),
    );
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(BorderSide(color: _linea)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: carrito,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _detalleOculto = !_detalleOculto),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('RESUMEN DE COMPRA', style: _rotulo(size: 10)),
                    ),
                    Icon(
                      _detalleOculto ? Icons.expand_more : Icons.expand_less,
                      size: 22,
                      color: AppColors.primaryDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${carrito.restaurante?.nombre ?? 'Tu pedido'} · ${_piezasTexto()}',
                style: AppTypography.body(color: AppColors.hint, size: 12.5),
              ),
              if (!_detalleOculto) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in carrito.lineas)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${l.cantidad}× ${l.producto.nombre}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.body(size: 13),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  dinero(l.importe),
                                  style: AppTypography.body(
                                    weight: FontWeight.w600,
                                    size: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        divisor,
                        const SizedBox(height: 10),
                        _filaMonto('Subtotal', dinero(carrito.subtotal)),
                        const SizedBox(height: 8),
                        _filaMonto(
                          'Envío',
                          _cotizando ? '…' : dinero(_envio),
                          detalle: _detalleEnvio(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              divisor,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('TOTAL', style: _rotulo(size: 12)),
                  Text(dinero(total), style: AppTypography.title(size: 30)),
                ],
              ),
              const SizedBox(height: 14),
              _botonPagar(alto: 54),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _lineaResumen(),
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    color: _listo ? AppColors.hint : _naranja,
                    size: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Panel izquierdo (sin scroll): solo dirección y método de pago.
  Widget _panelAncho() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
      children: [
        Text('PAGO Y ENTREGA', style: _rotulo()),
        const SizedBox(height: 6),
        Text('Confirma tu pedido', style: AppTypography.title(size: 27)),
        const SizedBox(height: 4),
        Text(
          '${carrito.restaurante?.nombre ?? 'Tu pedido'} · ${_piezasTexto()}',
          style: AppTypography.body(color: AppColors.hint, size: 13),
        ),
        const SizedBox(height: 22),
        Text('DIRECCIÓN DE ENTREGA', style: _rotulo(size: 10)),
        const SizedBox(height: 8),
        _filaBusqueda(),
        if (_errorDireccion != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorDireccion!,
            style: AppTypography.body(color: AppColors.error, size: 12.5),
          ),
        ],
        const SizedBox(height: 10),
        if (_punto == null)
          Text(
            'Escribe tu dirección y toca la lupa (o Enter) para ubicarla en el mapa.',
            style: AppTypography.body(color: AppColors.hint, size: 12.5),
          )
        else ...[
          _estadoDireccion(compacto: false),
          const SizedBox(height: 10),
          _campoReferencia(),
          const SizedBox(height: 4),
          Text(
            'El repartidor verá esta referencia junto con tu dirección.',
            style: AppTypography.body(color: AppColors.hint, size: 11.5),
          ),
        ],
        const SizedBox(height: 24),
        Text('MÉTODO DE PAGO', style: _rotulo(size: 10)),
        const SizedBox(height: 8),
        _selectorPago(compacto: false),
      ],
    );
  }
}

/// Logo de Food Express recortado a su parte visible. El PNG trae mucho
/// margen transparente; así queda del tamaño y la posición correctos.
class _LogoFE extends StatelessWidget {
  final double ancho;

  const _LogoFE({required this.ancho});

  @override
  Widget build(BuildContext context) {
    const anchoPng = 1672.0;
    const altoPng = 941.0;
    const margenIzq = 123.0;
    const margenSup = 200.0;
    const anchoVisible = 1471.0;
    const altoVisible = 524.0;

    final escala = ancho / anchoVisible;

    return SizedBox(
      width: ancho,
      height: altoVisible * escala,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -margenIzq * escala,
            top: -margenSup * escala,
            width: anchoPng * escala,
            height: altoPng * escala,
            child: Image.asset(
              'assets/images/logo-food-express.png',
              fit: BoxFit.fill,
            ),
          ),
        ],
      ),
    );
  }
}