import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import '../maps/mapas_service.dart';

/// Rastreo del pedido en tiempo real para el cliente (Sprint 4, historia #14).
///
/// Consulta el seguimiento cada 5 segundos y dibuja al repartidor en un mapa
/// de Google Maps, con la ruta por calles que calcula el backend (Routes API).
/// El recorrido va en dos colores, igual que en el panel del repartidor:
///   azul = repartidor -> restaurante, rojo = hacia tu domicilio.
///
/// Mismo diseño que el resto de la app: esquinas rectas, líneas finas, Poppins
/// y rótulos pequeños en mayúsculas. En pantalla ancha, el mapa va a la
/// izquierda y a la derecha una sola tarjeta con todo el detalle; en celular,
/// el mapa arriba y la tarjeta compacta abajo.
class RastreoScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final int pedidoId;

  const RastreoScreen({
    super.key,
    required this.usuario,
    required this.pedidoId,
  });

  @override
  State<RastreoScreen> createState() => _RastreoScreenState();
}

class _RastreoScreenState extends State<RastreoScreen> {
  // Colores y medidas (los mismos del resto de la app).
  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color menta = Color(0xFFE5F5F3);
  static const Color rojoClaro = Color(0xFFF8E3E6);

  // Colores del recorrido (los mismos que en el panel del repartidor).
  static const Color azulTramo = Color(0xFF1F6FEB);
  static const Color rojoTramo = Color(0xFFC8344B);
  static const Color ambar = Color(0xFFB7791F);
  static const Color verdeVivo = Color(0xFF2E9E5B);

  static const double _anchoConPanel = 900;
  static const double _anchoPanel = 380;

  static const _pasos = <({String estado, String titulo, String pista, IconData icono})>[
    (
      estado: 'pendiente',
      titulo: 'Pedido recibido',
      pista: 'Buscando repartidor',
      icono: Icons.receipt_long_outlined,
    ),
    (
      estado: 'aceptado',
      titulo: 'Aceptado',
      pista: 'Tu repartidor va al restaurante',
      icono: Icons.thumb_up_alt_outlined,
    ),
    (
      estado: 'recogido',
      titulo: 'Recogido',
      pista: 'Ya tiene tu pedido en la mochila',
      icono: Icons.shopping_bag_outlined,
    ),
    (
      estado: 'en_camino',
      titulo: 'En camino',
      pista: 'Viene directo hacia ti',
      icono: Icons.two_wheeler,
    ),
    (
      estado: 'entregado',
      titulo: 'Entregado',
      pista: '¡Buen provecho!',
      icono: Icons.home_outlined,
    ),
  ];

  GoogleMapController? _mapa;
  RutaMapa? _ruta;
  String? _estadoRuta;
  LatLng? _origenRuta;
  DateTime? _ultimaRuta;
  bool _pidiendoRuta = false;

  Seguimiento? seguimiento;
  String? error;
  bool cargando = true;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _cargar(),
    );
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _mapa?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final s = await PedidoService.seguimiento(
        widget.usuario.token,
        widget.pedidoId,
      );
      if (!mounted) return;
      setState(() {
        seguimiento = s;
        cargando = false;
        error = null;
      });
      if (s.estado == 'entregado' || s.estado == 'cancelado') {
        _temporizador?.cancel();
      }
      _actualizarRuta(s);
    } on ApiException catch (e) {
      _falla(e.mensaje);
    } catch (_) {
      _falla('No se pudo cargar el seguimiento.');
    }
  }

  /// Si ya hay datos en pantalla, un fallo suelto se ignora y se reintenta.
  void _falla(String mensaje) {
    if (!mounted || seguimiento != null) return;
    setState(() {
      error = mensaje;
      cargando = false;
    });
  }

  bool _enCurso(String estado) =>
      estado != 'entregado' && estado != 'cancelado';

  LatLng? _punto(double? lat, double? lon) =>
      (lat == null || lon == null) ? null : LatLng(lat, lon);

  double _metros(LatLng a, LatLng b) {
    const r = 6371000.0;
    double rad(double g) => g * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  /// La ruta por calles se vuelve a pedir cuando cambia el estado o cuando el
  /// repartidor se movió más de ~250 m (como máximo cada 15 s). Así el trazo
  /// sale siempre de donde está el repartidor, sin gastar cuota de más.
  void _actualizarRuta(Seguimiento s) {
    // Cancelado: no hay recorrido que mostrar.
    if (s.estado == 'cancelado') {
      if (_ruta != null) setState(() => _ruta = null);
      if (_estadoRuta != s.estado) {
        _estadoRuta = s.estado;
        Future.delayed(const Duration(milliseconds: 300), _ajustarCamara);
      }
      return;
    }

    // Entregado: se dibuja una sola vez el recorrido restaurante -> domicilio.
    if (s.estado == 'entregado') {
      if (_estadoRuta != s.estado) {
        _estadoRuta = s.estado;
        _cargarRuta(ajustar: true);
      }
      return;
    }

    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final cambioEstado = s.estado != _estadoRuta;
    final seMovio = repartidor != null &&
        (_origenRuta == null || _metros(repartidor, _origenRuta!) > 250);
    final yaPasoTiempo = _ultimaRuta == null ||
        DateTime.now().difference(_ultimaRuta!).inSeconds >= 15;

    if (cambioEstado || (seMovio && yaPasoTiempo)) {
      final ajustar = cambioEstado || _ruta == null;
      _estadoRuta = s.estado;
      _origenRuta = repartidor;
      _ultimaRuta = DateTime.now();
      _cargarRuta(ajustar: ajustar);
    }
  }

  Future<void> _cargarRuta({required bool ajustar}) async {
    if (_pidiendoRuta) return;
    _pidiendoRuta = true;
    try {
      final ruta = await MapasService.rutaDePedido(
        widget.usuario.token,
        widget.pedidoId,
      );
      if (!mounted) return;
      setState(() => _ruta = ruta);
      if (ajustar) _ajustarCamara();
    } catch (_) {
      // Sin ruta por calles: el mapa dibuja líneas rectas de respaldo.
      debugPrint('No se pudo obtener la ruta por calles.');
      if (ajustar) _ajustarCamara();
    } finally {
      _pidiendoRuta = false;
    }
  }

  // =====================================================
  // MAPA
  // =====================================================

  /// Tramos con su color: la ruta por calles de Google o, si no hay, líneas
  /// rectas de respaldo. Pedido entregado: el recorrido restaurante ->
  /// domicilio. Pedido cancelado: ninguno.
  List<({bool alRestaurante, List<LatLng> puntos})> _tramos(Seguimiento s) {
    if (s.estado == 'cancelado') return const [];

    final ruta = _ruta;
    if (ruta != null && ruta.tramos.isNotEmpty) {
      return [
        for (final t in ruta.tramos)
          if (t.puntos.length >= 2)
            (alRestaurante: t.haciaRestaurante, puntos: t.puntos),
      ];
    }

    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final antesDeRecoger = s.estado == 'pendiente' || s.estado == 'aceptado';

    if (s.estado == 'entregado') {
      return [
        if (restaurante != null && cliente != null)
          (alRestaurante: false, puntos: [restaurante, cliente]),
      ];
    }
    if (antesDeRecoger && restaurante != null) {
      return [
        if (repartidor != null)
          (alRestaurante: true, puntos: [repartidor, restaurante]),
        if (cliente != null)
          (alRestaurante: false, puntos: [restaurante, cliente]),
      ];
    }
    if (cliente != null) {
      return [
        (
          alRestaurante: false,
          puntos: [if (repartidor != null) repartidor else restaurante ?? cliente, cliente],
        ),
      ];
    }
    return const [];
  }

  /// Puntos que deben verse en el mapa (marcadores y recorrido).
  List<LatLng> _puntosVisibles(Seguimiento s) {
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final mostrarRestaurante =
        s.estado == 'pendiente' || s.estado == 'aceptado' || !_enCurso(s.estado);

    return <LatLng>[
      if (mostrarRestaurante && restaurante != null) restaurante,
      if (cliente != null) cliente,
      if (_enCurso(s.estado) && repartidor != null) repartidor,
      for (final t in _tramos(s)) ...t.puntos,
    ];
  }

  /// Acerca la cámara para que se vea todo el recorrido.
  Future<void> _ajustarCamara() async {
    final controlador = _mapa;
    final s = seguimiento;
    if (controlador == null || s == null) return;

    final puntos = _puntosVisibles(s);
    if (puntos.isEmpty) return;

    var minLat = puntos.first.latitude;
    var maxLat = minLat;
    var minLon = puntos.first.longitude;
    var maxLon = minLon;
    for (final p in puntos) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    try {
      if (minLat == maxLat && minLon == maxLon) {
        await controlador.animateCamera(
          CameraUpdate.newLatLngZoom(puntos.first, 16),
        );
        return;
      }
      await controlador.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLon),
            northeast: LatLng(maxLat, maxLon),
          ),
          64,
        ),
      );
    } catch (e) {
      debugPrint('No se pudo ajustar la cámara: $e');
    }
  }

  Marker _marcador(String id, LatLng posicion, String titulo, double tono) {
    return Marker(
      markerId: MarkerId(id),
      position: posicion,
      infoWindow: InfoWindow(title: titulo),
      icon: BitmapDescriptor.defaultMarkerWithHue(tono),
    );
  }

  /// Línea de color con borde blanco debajo para que resalte sobre las calles.
  /// El tramo hacia el restaurante va debajo y más ancho: si el regreso pasa
  /// por la misma calle, se ven los dos colores.
  Iterable<Polyline> _linea(
    String id,
    List<LatLng> puntos,
    Color color, {
    required double ancho,
    required int capa,
  }) {
    return [
      Polyline(
        polylineId: PolylineId('$id-borde'),
        points: puntos,
        width: ancho.round() + 4,
        color: Colors.white,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: capa * 2 + 1,
      ),
      Polyline(
        polylineId: PolylineId(id),
        points: puntos,
        width: ancho.round(),
        color: color,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: capa * 2 + 2,
      ),
    ];
  }

  Widget _mapaWidget(Seguimiento s) {
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final enCurso = _enCurso(s.estado);
    final mostrarRestaurante =
        s.estado == 'pendiente' || s.estado == 'aceptado' || !enCurso;

    final marcadores = <Marker>{
      if (mostrarRestaurante && restaurante != null)
        _marcador(
          'restaurante',
          restaurante,
          s.restaurante,
          BitmapDescriptor.hueOrange,
        ),
      if (cliente != null)
        _marcador('cliente', cliente, 'Tu domicilio', BitmapDescriptor.hueRed),
      if (enCurso && repartidor != null)
        _marcador(
          'repartidor',
          repartidor,
          s.repartidorNombre ?? 'Tu repartidor',
          BitmapDescriptor.hueAzure,
        ),
    };

    final lineas = <Polyline>{};
    for (final t in _tramos(s)) {
      lineas.addAll(
        t.alRestaurante
            ? _linea('al-restaurante', t.puntos, azulTramo, ancho: 7, capa: 0)
            : _linea('al-cliente', t.puntos, rojoTramo, ancho: 5, capa: 1),
      );
    }

    final visibles = _puntosVisibles(s);
    final centro = visibles.isNotEmpty ? visibles.first : const LatLng(19.60, -99.31);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: centro, zoom: 15),
          markers: marcadores,
          polylines: lineas,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controlador) {
            _mapa = controlador;
            // Pequeña espera para que el mapa termine de dibujarse.
            Future.delayed(const Duration(milliseconds: 400), _ajustarCamara);
          },
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: _ajustarCamara,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: grisBorde),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.my_location, size: 16, color: turquesa),
                    const SizedBox(width: 8),
                    Text(
                      'VER TODO EL RECORRIDO',
                      style: _rotulo(color: verdeOscuro, size: 9.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =====================================================
  // AYUDAS
  // =====================================================

  TextStyle _rotulo({Color color = grisTexto, double size = 10}) {
    return AppTypography.body(
      color: color,
      weight: FontWeight.w700,
      size: size,
    ).copyWith(letterSpacing: 1.5);
  }

  /// Paso actual; con el pedido entregado todos los pasos quedan completos.
  int _indicePaso(String estado) => estado == 'entregado'
      ? _pasos.length
      : _pasos.indexWhere((p) => p.estado == estado);

  String? _horaLlegada(Seguimiento s) {
    final minutos = s.minutosRestantes;
    if (minutos == null) return null;
    final hora = DateTime.now().add(Duration(minutes: minutos));
    final hh = hora.hour.toString().padLeft(2, '0');
    final mm = hora.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _detalleLlegada(Seguimiento s) {
    final partes = <String>[];
    if (s.minutosRestantes != null) partes.add('${s.minutosRestantes} min');
    final km = s.distanciaRestanteKm;
    if (km != null) partes.add('${km.toStringAsFixed(1)} km');
    return partes.join(' · ');
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
              'Rastreo de tu pedido',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title(size: 20),
            ),
          ),
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

  // =====================================================
  // PIEZAS DE LA TARJETA
  // =====================================================

  Widget _chipEstado(String estado) {
    final cancelado = estado == 'cancelado';
    final entregado = estado == 'entregado';
    final Color bg = cancelado
        ? AppColors.error
        : (entregado ? verdeOscuro : menta);
    final Color fg = (cancelado || entregado) ? Colors.white : verdeOscuro;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: bg,
      child: Text(
        textoEstado(estado).toUpperCase(),
        style: _rotulo(color: fg, size: 9.5),
      ),
    );
  }

  Widget _cabecera(Seguimiento s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PEDIDO #${s.pedidoId}', style: _rotulo()),
              const SizedBox(height: 3),
              Text(
                s.restaurante,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title(size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _chipEstado(s.estado),
      ],
    );
  }

  /// Hora de llegada grande (solo mientras el pedido va en curso).
  Widget _llegada(Seguimiento s, {required bool compacto}) {
    final hora = _horaLlegada(s);
    final detalle = _detalleLlegada(s);
    final recogido = s.estado == 'recogido' || s.estado == 'en_camino';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: compacto ? 38 : 46,
          height: compacto ? 38 : 46,
          color: verdeOscuro,
          child: Icon(
            Icons.schedule,
            color: Colors.white,
            size: compacto ? 20 : 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recogido ? 'LLEGA APROXIMADAMENTE' : 'LLEGADA ESTIMADA',
                style: _rotulo(size: 9.5),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    hora ?? 'Calculando…',
                    style: AppTypography.title(size: hora == null ? 16 : (compacto ? 24 : 30)),
                  ),
                  if (detalle.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        detalle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          color: grisTexto,
                          weight: FontWeight.w500,
                          size: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nodo({required bool hecho, required bool actual, double lado = 20}) {
    if (hecho) {
      return Container(
        width: lado,
        height: lado,
        color: turquesa,
        child: Icon(Icons.check, size: lado - 6, color: Colors.white),
      );
    }
    if (actual) {
      return Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: turquesa, width: 2),
        ),
        child: Center(
          child: Container(width: lado - 12, height: lado - 12, color: turquesa),
        ),
      );
    }
    return Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde, width: 1.5),
      ),
    );
  }

  /// Línea de tiempo vertical con una pista corta por paso (pantalla ancha).
  Widget _pasosVertical(String estado) {
    final actual = _indicePaso(estado);
    return Column(
      children: [
        for (var i = 0; i < _pasos.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      _nodo(hecho: i < actual, actual: i == actual),
                      if (i < _pasos.length - 1)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 2,
                              color: i < actual ? turquesa : grisBorde,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < _pasos.length - 1 ? 12 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _pasos[i].titulo,
                          style: AppTypography.body(
                            weight: i == actual
                                ? FontWeight.w700
                                : FontWeight.w600,
                            size: 13.5,
                            color: i > actual ? grisTexto : verdeOscuro,
                          ),
                        ),
                        if (i == actual)
                          Text(
                            _pasos[i].pista,
                            style: AppTypography.body(
                              color: grisTexto,
                              weight: FontWeight.w400,
                              size: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Línea de tiempo horizontal (celular).
  Widget _pasosHorizontal(String estado) {
    final actual = _indicePaso(estado);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _pasos.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= actual ? turquesa : grisBorde),
                      ),
                    ),
                    _nodo(hecho: i < actual, actual: i == actual, lado: 18),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == _pasos.length - 1
                            ? Colors.transparent
                            : (i < actual ? turquesa : grisBorde),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _pasos[i].titulo.replaceFirst('Pedido recibido', 'Recibido'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    size: 10.5,
                    weight: i == actual ? FontWeight.w700 : FontWeight.w500,
                    color: i > actual ? grisTexto : verdeOscuro,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _repartidor(Seguimiento s) {
    final nombre = s.repartidorNombre;
    if (nombre == null || nombre.trim().isEmpty) return const SizedBox.shrink();

    final seg = s.segundosDesdeUbicacion;
    final String senal;
    final Color colorSenal;
    if (seg == null) {
      senal = 'Aún no comparte su ubicación';
      colorSenal = grisTexto;
    } else if (seg > 120) {
      senal = 'Última señal hace ${(seg / 60).floor()} min';
      colorSenal = ambar;
    } else {
      senal = 'Ubicación en vivo';
      colorSenal = verdeVivo;
    }

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          color: menta,
          alignment: Alignment.center,
          child: Text(
            nombre.trim()[0].toUpperCase(),
            style: AppTypography.title(size: 18).copyWith(color: verdeOscuro),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TU REPARTIDOR', style: _rotulo(size: 9)),
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(weight: FontWeight.w700, size: 14.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 8, height: 8, color: colorSenal),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            senal,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              color: colorSenal,
              weight: FontWeight.w600,
              size: 12,
            ),
          ),
        ),
      ],
    );
  }

  /// Qué significa cada color del mapa.
  Widget _leyenda(Seguimiento s) {
    final antesDeRecoger = s.estado == 'pendiente' || s.estado == 'aceptado';
    Widget item(Color color, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 22, height: 4, color: color),
            const SizedBox(width: 8),
            Text(
              texto,
              style: AppTypography.body(
                color: grisTexto,
                weight: FontWeight.w500,
                size: 12,
              ),
            ),
          ],
        );
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        if (antesDeRecoger) item(azulTramo, 'Repartidor → restaurante'),
        item(rojoTramo, 'Hacia tu domicilio'),
      ],
    );
  }

  Widget _lineaDivisora() => Container(height: 1, color: grisBorde);

  /// Contenido de la tarjeta cuando el pedido ya terminó o aún no empieza.
  Widget _estadoSinRecorrido(Seguimiento s) {
    final IconData icono;
    final Color colorIcono;
    final Color fondoIcono;
    final String rotulo;
    final String titulo;
    final String texto;

    switch (s.estado) {
      case 'entregado':
        icono = Icons.check_circle_outline;
        colorIcono = turquesa;
        fondoIcono = menta;
        rotulo = 'COMPLETADO';
        titulo = '¡Pedido entregado!';
        texto = 'Gracias por pedir con Food Express. ¡Que lo disfrutes!';
        break;
      case 'cancelado':
        icono = Icons.cancel_outlined;
        colorIcono = AppColors.error;
        fondoIcono = rojoClaro;
        rotulo = 'CERRADO';
        titulo = 'Pedido cancelado';
        texto = 'Este pedido ya no se va a entregar. Puedes hacer otro '
            'cuando quieras.';
        break;
      default:
        icono = Icons.hourglass_top;
        colorIcono = Colors.white;
        fondoIcono = verdeOscuro;
        rotulo = 'EN ESPERA';
        titulo = 'Buscando repartidor…';
        texto = 'En cuanto alguien acepte tu pedido verás aquí su recorrido '
            'en vivo.';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          color: fondoIcono,
          child: Icon(icono, size: 26, color: colorIcono),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: _rotulo(size: 9.5)),
              const SizedBox(height: 2),
              Text(titulo, style: AppTypography.title(size: 18)),
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
    );
  }

  Widget _enlaceMisPedidos() {
    return InkWell(
      onTap: () => Navigator.pop(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back, size: 15, color: turquesa),
            const SizedBox(width: 6),
            Text(
              'VOLVER A MIS PEDIDOS',
              style: _rotulo(color: turquesa, size: 10),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // TARJETAS
  // =====================================================

  /// Todo el detalle del pedido (pantalla ancha). Va en una columna pegada al
  /// borde derecho, sin caja: solo líneas finas entre secciones.
  Widget _tarjetaAncha(Seguimiento s) {
    final enCurso = _enCurso(s.estado);
    final conRecorrido = s.estado != 'pendiente' && enCurso;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cabecera(s),
          const SizedBox(height: 16),
          _lineaDivisora(),
          const SizedBox(height: 16),
          if (conRecorrido) ...[
            _llegada(s, compacto: false),
            const SizedBox(height: 16),
            _lineaDivisora(),
            const SizedBox(height: 16),
          ] else ...[
            _estadoSinRecorrido(s),
            const SizedBox(height: 16),
            _lineaDivisora(),
            const SizedBox(height: 16),
          ],
          if (s.estado != 'cancelado') ...[
            Text('PROGRESO', style: _rotulo()),
            const SizedBox(height: 12),
            _pasosVertical(s.estado),
            const SizedBox(height: 16),
            _lineaDivisora(),
            const SizedBox(height: 16),
          ],
          if (enCurso && s.repartidorNombre != null) ...[
            _repartidor(s),
            const SizedBox(height: 16),
          ],
          if (conRecorrido) ...[
            _leyenda(s),
            const SizedBox(height: 12),
            if (_ruta != null && _ruta!.esGoogle)
              Text(
                'Ruta por calles · Google Maps',
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 12,
                ),
              ),
          ],
          if (s.estado == 'entregado') ...[
            Row(
              children: [
                Container(width: 22, height: 4, color: rojoTramo),
                const SizedBox(width: 8),
                Text(
                  'Recorrido de tu entrega',
                  style: AppTypography.body(
                    color: grisTexto,
                    weight: FontWeight.w500,
                    size: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (!enCurso) _enlaceMisPedidos(),
        ],
    );
  }

  /// Tarjeta compacta que va debajo del mapa en celular.
  Widget _tarjetaCompacta(Seguimiento s) {
    final enCurso = _enCurso(s.estado);
    final conRecorrido = s.estado != 'pendiente' && enCurso;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: grisBorde)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${s.pedidoId} · ${s.restaurante}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(weight: FontWeight.w700, size: 15),
                ),
              ),
              const SizedBox(width: 8),
              _chipEstado(s.estado),
            ],
          ),
          const SizedBox(height: 12),
          if (conRecorrido)
            _llegada(s, compacto: true)
          else
            _estadoSinRecorrido(s),
          if (s.estado != 'cancelado') ...[
            const SizedBox(height: 14),
            _pasosHorizontal(s.estado),
          ],
          if (enCurso && s.repartidorNombre != null) ...[
            const SizedBox(height: 14),
            _repartidor(s),
          ],
          if (conRecorrido) ...[
            const SizedBox(height: 12),
            _leyenda(s),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // ESTADOS: CARGANDO Y ERROR
  // =====================================================

  Widget _errorCarga() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: rojoClaro,
                  border: Border.all(color: grisBorde),
                ),
                child: const Icon(
                  Icons.cloud_off_outlined,
                  size: 40,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 18),
              Text('ALGO SALIÓ MAL', style: _rotulo(color: AppColors.error)),
              const SizedBox(height: 6),
              Text(
                error ?? 'No se pudo cargar el seguimiento.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14,
                ),
              ),
              const SizedBox(height: 18),
              Material(
                color: verdeOscuro,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      cargando = true;
                      error = null;
                    });
                    _cargar();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    child: Text(
                      'REINTENTAR',
                      style: _rotulo(color: Colors.white, size: 10.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final compacto = ancho < 700;
          return Column(
            children: [
              _barraSuperior(compacto ? 14.0 : 24.0),
              Expanded(child: _cuerpo(ancho >= _anchoConPanel)),
            ],
          );
        },
      ),
    );
  }

  Widget _cuerpo(bool conPanel) {
    final s = seguimiento;
    if (cargando) {
      return const Center(
        child: CircularProgressIndicator(color: turquesa, strokeWidth: 3),
      );
    }
    if (s == null) return _errorCarga();

    if (conPanel) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El mapa cubre toda la sección, de orilla a orilla.
          Expanded(child: _mapaWidget(s)),
          // Columna del detalle: alto completo, pegada a la orilla derecha.
          Container(
            width: _anchoPanel,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: grisBorde)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: _tarjetaAncha(s),
            ),
          ),
        ],
      );
    }

    // Celular o ventana angosta: mapa arriba y tarjeta compacta fija abajo.
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: _mapaWidget(s)),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: SingleChildScrollView(child: _tarjetaCompacta(s)),
          ),
        ],
      ),
    );
  }
}
