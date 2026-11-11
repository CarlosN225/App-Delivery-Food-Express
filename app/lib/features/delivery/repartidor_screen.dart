import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/sesion_service.dart';
import '../cart/carrito_service.dart';
import '../maps/mapas_service.dart';
import 'pedido_model.dart';
import 'pedido_service.dart';
import 'perfil_repartidor_screen.dart';

// ---------------------------------------------------------------- estilo
// Diseño de esquinas rectas: líneas finas, tipografía serif en los títulos
// y rótulos pequeños en mayúsculas con espaciado.

const _tinta = AppColors.primaryDark;
const _linea = Color(0xFFD3E2DF);
const _papel = Color(0xFFF3F6F5);
const _naranja = Color(0xFFE07B00);
const _naranjaSuave = Color(0xFFFFF3E0);
const _rojo = Color(0xFFC8344B);
const _azul = Color(0xFF1F6FEB);
const _trazoSecundario = Color(0xFF8DB5B0);

/// Colores de los tramos: tú -> restaurante (azul) y restaurante -> cliente (rojo).
const _trazoAlRestaurante = _azul;
const _trazoAlCliente = _rojo;

/// Rótulo pequeño en mayúsculas.
TextStyle _rotulo({Color color = AppColors.hint, double size = 10.5}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: color,
    );

/// Títulos y cifras grandes: Poppins, la misma letra redondeada del Inicio.
/// (Poppins es más ancha que una serif, por eso se reduce un 10 %.)
TextStyle _titulo({double size = 22, Color color = _tinta}) =>
    GoogleFonts.poppins(
      fontSize: size * 0.9,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.2,
    );

/// Mapa claro y limpio: sin negocios de Google ni transporte, para que
/// resalten los pines de Food Express y la ruta.
const _estiloMapa = '''[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]''';

/// Panel del repartidor (Sprint 3 + mapa de Google del Sprint 5).
///  - Mapa grande a la derecha; el panel de pedidos a la izquierda.
///  - Disponibles: pedidos pagados (o en efectivo) que esperan repartidor.
///  - En curso: un solo pedido a la vez, con su itinerario, el avance
///    Recogido / En camino / Entregado (#12) y la ruta por calles de Google.
class RepartidorScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const RepartidorScreen({super.key, required this.usuario});

  @override
  State<RepartidorScreen> createState() => _RepartidorScreenState();
}

class _RepartidorScreenState extends State<RepartidorScreen> {
  /// 0 = Disponibles, 1 = En curso.
  int _tab = 0;

  /// Pedido resaltado en la lista y en el mapa.
  int? _sel;

  List<PedidoDisponible> disponibles = [];
  List<Pedido> activos = [];
  RutaOptima? ruta;
  Position? posicion;

  bool cargando = true;
  String? error;

  /// Pedidos con una acción en curso (para no duplicar toques).
  final Set<int> _ocupados = {};

  String get _token => widget.usuario.token;

  /// Historia #14: temporizador que manda la posición GPS del repartidor.
  Timer? _gps;
  bool _reportando = false;

  // ---- hoja inferior (solo en pantallas angostas / celular)
  final DraggableScrollableController _hoja = DraggableScrollableController();
  bool _movil = false;
  double _hojaInicial = 0.4;
  double _hojaMax = 0.92;

  // ---- mapa
  GoogleMapController? _mapa;

  /// Rutas por calles ya pedidas al backend, por "pedido-estado".
  final Map<String, RutaMapa> _rutas = {};
  final Set<String> _pidiendoRuta = {};

  /// Dónde estaba el repartidor cuando se pidió cada ruta (para recalcularla
  /// cuando se aleja más de [_metrosParaRecalcular]).
  final Map<String, LatLng?> _origenRuta = {};
  static const double _metrosParaRecalcular = 200;

  /// Pines propios (el mapa web ignora los colores de los pines de Google).
  BitmapDescriptor? _pinRestaurante;
  BitmapDescriptor? _pinEntrega;
  BitmapDescriptor? _pinYo;

  @override
  void initState() {
    super.initState();
    _crearPines();
    cargar();
    // Historia #14: con pedidos en curso, manda la posición cada 10 s.
    _gps = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _reportarUbicacion(),
    );
  }

  @override
  void dispose() {
    _gps?.cancel();
    _mapa?.dispose();
    _hoja.dispose();
    super.dispose();
  }

  Future<Position?> _ubicacion() async {
    try {
      return await LocationService.obtenerUbicacionActual();
    } catch (_) {
      return null;
    }
  }

  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        cargando = true;
        error = null;
      });
    }

    try {
      final pos = await _ubicacion();
      final lat = pos?.latitude;
      final lon = pos?.longitude;

      final nuevosDisponibles = await PedidoService.pedidosDisponibles(
        _token,
        latitud: lat,
        longitud: lon,
      );
      final nuevosActivos = await PedidoService.pedidosActivos(_token);
      final nuevaRuta = await PedidoService.rutaOptima(
        _token,
        latitud: lat,
        longitud: lon,
      );

      if (!mounted) return;
      setState(() {
        posicion = pos;
        disponibles = nuevosDisponibles;
        activos = nuevosActivos;
        ruta = nuevaRuta;
        cargando = false;
        error = null;
      });
      _pedirRutas();
      _ajustarCamaraConEspera();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudieron cargar los pedidos.';
        cargando = false;
      });
    }
  }

  /// Pide a Google (vía backend) la ruta por calles de cada pedido en curso.
  /// Se pide una vez por pedido y estado, y de nuevo cuando el repartidor se
  /// mueve más de 200 m, para que el trazo salga siempre desde donde está.
  void _pedirRutas() {
    final yo = _yoPunto;
    for (final p in activos) {
      _pedirRutaDe('${p.id}-${p.estado}', p.id, yo);
    }
    _pedirRutaDeDisponible();
  }

  /// Vista previa del recorrido del pedido disponible que se tocó.
  void _pedirRutaDeDisponible() {
    final d = _disponibleSel;
    if (d == null) return;
    _pedirRutaDe('disp-${d.id}', d.id, _yoPunto);
  }

  void _pedirRutaDe(String clave, int pedidoId, LatLng? yo) {
    final yaTiene = _rutas.containsKey(clave);
    final antes = _origenRuta[clave];
    final seMovio = yo != null &&
        (antes == null ||
            Geolocator.distanceBetween(
                  yo.latitude,
                  yo.longitude,
                  antes.latitude,
                  antes.longitude,
                ) >
                _metrosParaRecalcular);
    if ((yaTiene && !seMovio) || !_pidiendoRuta.add(clave)) return;
    MapasService.rutaDePedido(_token, pedidoId, desde: yo).then((r) {
      if (!mounted) return;
      _origenRuta[clave] = yo;
      setState(() => _rutas[clave] = r);
      _ajustarCamara();
    }).catchError((Object e) {
      // Sin ruta por calles: el mapa dibuja una línea recta de respaldo.
      debugPrint('No se pudo obtener la ruta del pedido $pedidoId: $e');
    }).whenComplete(() => _pidiendoRuta.remove(clave));
  }

  /// Ejecuta una acción sobre un pedido evitando toques repetidos.
  Future<void> _accion(
    int pedidoId,
    Future<void> Function() accion, {
    String? exito,
    bool irAEnCurso = false,
  }) async {
    if (!_ocupados.add(pedidoId)) return;
    setState(() {});
    try {
      await accion();
      if (!mounted) return;
      if (exito != null) showAppSnackBar(context, exito, isError: false);
      await cargar(silencioso: true);
      if (irAEnCurso && mounted) {
        _sel = pedidoId;
        _cambiarTab(1);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.mensaje);
      await cargar(silencioso: true);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'No se pudo completar la acción.');
    } finally {
      _ocupados.remove(pedidoId);
      if (mounted) setState(() {});
    }
  }

  /// Avanza el pedido al siguiente estado (Recogido, En camino, Entregado).
  Future<void> _cambiarEstado(Pedido p, String nuevo) async {
    await _accion(
      p.id,
      () async {
        await PedidoService.cambiarEstado(_token, p.id, nuevo);
      },
      exito: nuevo == 'entregado'
          ? '¡Pedido #${p.id} entregado!'
          : 'Pedido #${p.id}: ${textoEstado(nuevo).toLowerCase()}.',
    );
    // Entregado: queda libre y vuelve a ver los pedidos disponibles.
    if (nuevo == 'entregado' && mounted && activos.isEmpty) {
      _sel = null;
      _cambiarTab(0);
    }
  }

  /// Historia #14: manda la posición del repartidor para el rastreo del cliente.
  Future<void> _reportarUbicacion() async {
    if (_reportando || activos.isEmpty) return;
    _reportando = true;
    try {
      final pos = await _ubicacion();
      if (pos == null) return;
      if (mounted) {
        setState(() => posicion = pos);
        _pedirRutas();
      }
      for (final pedido in List<Pedido>.from(activos)) {
        await PedidoService.reportarUbicacion(
          _token,
          pedido.id,
          pos.latitude,
          pos.longitude,
        );
      }
    } catch (_) {
      // Sin red o sin GPS: se reintenta en el siguiente ciclo.
    } finally {
      _reportando = false;
    }
  }

  void _abrirPerfil() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PerfilRepartidorScreen(usuario: widget.usuario),
      ),
    );
  }

  void _cerrarSesion() {
    SesionService.borrar();
    CarritoService.instance.vaciar();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ------------------------------------------------------------- selección

  void _cambiarTab(int nueva) {
    setState(() => _tab = nueva);
    _colapsarHoja();
    _ajustarCamaraConEspera();
  }

  void _seleccionar(int pedidoId) {
    setState(() => _sel = pedidoId);
    if (_tab == 0) _pedirRutaDeDisponible();
    _colapsarHoja();
    _ajustarCamara();
  }

  // ----------------------------------------------------- hoja inferior (móvil)

  /// Baja la hoja para que el mapa quede grande y a la vista.
  void _colapsarHoja() {
    if (!_movil || !_hoja.isAttached) return;
    _hoja.animateTo(
      _hojaInicial,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _alternarHoja() {
    if (!_hoja.isAttached) return;
    final arriba = _hoja.size > (_hojaInicial + _hojaMax) / 2;
    _hoja.animateTo(
      arriba ? _hojaInicial : _hojaMax,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _arrastrarHoja(double dy, double alto) {
    if (!_hoja.isAttached || alto <= 0) return;
    final nuevo = (_hoja.size - dy / alto).clamp(_hojaInicial, _hojaMax);
    _hoja.jumpTo(nuevo.toDouble());
  }

  void _soltarHoja(double velocidad) {
    if (!_hoja.isAttached) return;
    final mitad = (_hojaInicial + _hojaMax) / 2;
    final double destino;
    if (velocidad < -300) {
      destino = _hojaMax;
    } else if (velocidad > 300) {
      destino = _hojaInicial;
    } else {
      destino = _hoja.size >= mitad ? _hojaMax : _hojaInicial;
    }
    _hoja.animateTo(
      destino,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Pedido disponible resaltado (solo en la pestaña Disponibles).
  PedidoDisponible? get _disponibleSel {
    for (final d in disponibles) {
      if (d.id == _sel) return d;
    }
    return null;
  }

  /// Pedido en curso resaltado; si no hay ninguno elegido, el primero.
  Pedido? get _activoSel {
    if (activos.isEmpty) return null;
    for (final p in activos) {
      if (p.id == _sel) return p;
    }
    return activos.first;
  }

  RutaMapa? _rutaDe(Pedido p) => _rutas['${p.id}-${p.estado}'];

  /// Tramo (recoger / entregar) de un pedido en la ruta sugerida.
  Tramo? _tramo(int pedidoId, String tipo) {
    final r = ruta;
    if (r == null) return null;
    for (final t in r.tramos) {
      if (t.pedidoId == pedidoId && t.tipo == tipo) return t;
    }
    return null;
  }

  // ------------------------------------------------------------------ pines

  /// Pin cuadrado con punta: relleno de color y un símbolo dibujado a mano.
  Future<BitmapDescriptor> _crearPin(
    Color color,
    void Function(ui.Canvas lienzo, Offset centro) glifo,
  ) async {
    const ancho = 52.0;
    const alto = 64.0;
    const escala = 2.0;

    final grabador = ui.PictureRecorder();
    final lienzo = ui.Canvas(grabador)..scale(escala);

    final cuerpo = Rect.fromLTWH(3, 3, ancho - 6, 46);
    final sombra = ui.Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    lienzo.drawRect(cuerpo.shift(const Offset(0, 3)), sombra);

    final blanco = ui.Paint()..color = Colors.white;
    lienzo.drawRect(cuerpo, blanco);
    lienzo.drawPath(
      ui.Path()
        ..moveTo(ancho / 2 - 9, cuerpo.bottom)
        ..lineTo(ancho / 2, alto - 3)
        ..lineTo(ancho / 2 + 9, cuerpo.bottom)
        ..close(),
      blanco,
    );

    final interior = cuerpo.deflate(3);
    final pintura = ui.Paint()..color = color;
    lienzo.drawRect(interior, pintura);
    lienzo.drawPath(
      ui.Path()
        ..moveTo(ancho / 2 - 6, interior.bottom)
        ..lineTo(ancho / 2, alto - 9)
        ..lineTo(ancho / 2 + 6, interior.bottom)
        ..close(),
      pintura,
    );

    glifo(lienzo, interior.center);

    final imagen = await grabador.endRecording().toImage(
          (ancho * escala).round(),
          (alto * escala).round(),
        );
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      datos!.buffer.asUint8List(),
      width: ancho,
      height: alto,
    );
  }

  Future<void> _crearPines() async {
    final blanco = ui.Paint()..color = Colors.white;
    try {
      // Restaurante: plato (círculos concéntricos).
      final restaurante = await _crearPin(_naranja, (lienzo, c) {
        lienzo.drawCircle(
          c,
          11,
          ui.Paint()
            ..color = Colors.white
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        lienzo.drawCircle(c, 4.5, blanco);
      });
      // Entrega: casa.
      final entrega = await _crearPin(_rojo, (lienzo, c) {
        lienzo.drawPath(
          ui.Path()
            ..moveTo(c.dx - 12, c.dy - 1)
            ..lineTo(c.dx, c.dy - 12)
            ..lineTo(c.dx + 12, c.dy - 1)
            ..close(),
          blanco,
        );
        lienzo.drawRect(
          Rect.fromLTRB(c.dx - 8, c.dy - 1, c.dx + 8, c.dy + 11),
          blanco,
        );
        lienzo.drawRect(
          Rect.fromLTRB(c.dx - 2.5, c.dy + 4, c.dx + 2.5, c.dy + 11),
          ui.Paint()..color = _rojo,
        );
      });
      // Tú: flecha de navegación.
      final yo = await _crearPin(_azul, (lienzo, c) {
        lienzo.drawPath(
          ui.Path()
            ..moveTo(c.dx, c.dy - 12)
            ..lineTo(c.dx + 10, c.dy + 11)
            ..lineTo(c.dx, c.dy + 5)
            ..lineTo(c.dx - 10, c.dy + 11)
            ..close(),
          blanco,
        );
      });
      if (!mounted) return;
      setState(() {
        _pinRestaurante = restaurante;
        _pinEntrega = entrega;
        _pinYo = yo;
      });
    } catch (e) {
      // Sin pines propios se usan los de Google.
      debugPrint('No se pudieron crear los pines: $e');
    }
  }

  // ------------------------------------------------------------------ mapa

  LatLng? _punto(double? lat, double? lon) =>
      (lat == null || lon == null) ? null : LatLng(lat, lon);

  LatLng? get _yoPunto => _punto(posicion?.latitude, posicion?.longitude);

  Marker _marcador(
    String id,
    LatLng pos,
    String titulo,
    BitmapDescriptor? icono,
    double tonoDeRespaldo, {
    String? detalle,
    VoidCallback? alTocar,
  }) {
    return Marker(
      markerId: MarkerId(id),
      position: pos,
      infoWindow: InfoWindow(title: titulo, snippet: detalle),
      icon: icono ?? BitmapDescriptor.defaultMarkerWithHue(tonoDeRespaldo),
      onTap: alTocar,
    );
  }

  Set<Marker> _marcadores() {
    final yo = _yoPunto;
    final marcadores = <Marker>{
      if (yo != null)
        _marcador(
          'yo',
          yo,
          'Tú estás aquí',
          _pinYo,
          BitmapDescriptor.hueAzure,
        ),
    };

    if (_tab == 0) {
      final elegido = _disponibleSel;
      for (final d in disponibles) {
        final r = _punto(d.restauranteLatitud, d.restauranteLongitud);
        if (r == null) continue;
        marcadores.add(
          _marcador(
            'r${d.id}',
            r,
            d.restaurante,
            _pinRestaurante,
            BitmapDescriptor.hueOrange,
            detalle: 'Pedido #${d.id} · ${dinero(d.total)}',
            alTocar: () => _seleccionar(d.id),
          ),
        );
      }
      if (elegido != null) {
        final e = _punto(elegido.latitudEntrega, elegido.longitudEntrega);
        if (e != null) {
          marcadores.add(
            _marcador(
              'e${elegido.id}',
              e,
              'Entrega · Pedido #${elegido.id}',
              _pinEntrega,
              BitmapDescriptor.hueRose,
              detalle: elegido.direccionEntrega,
            ),
          );
        }
      }
      return marcadores;
    }

    for (final p in activos) {
      final antesDeRecoger = p.estado == 'aceptado';
      final r = _punto(p.restauranteLatitud, p.restauranteLongitud);
      final c = _punto(p.latitudEntrega, p.longitudEntrega);
      if (antesDeRecoger && r != null) {
        marcadores.add(
          _marcador(
            'r${p.id}',
            r,
            p.restaurante,
            _pinRestaurante,
            BitmapDescriptor.hueOrange,
            detalle: 'Recoger · Pedido #${p.id}',
            alTocar: () => _seleccionar(p.id),
          ),
        );
      }
      if (c != null) {
        marcadores.add(
          _marcador(
            'c${p.id}',
            c,
            'Entrega · Pedido #${p.id}',
            _pinEntrega,
            BitmapDescriptor.hueRose,
            detalle: p.direccionEntrega,
            alTocar: () => _seleccionar(p.id),
          ),
        );
      }
    }
    return marcadores;
  }

  /// Tramos de un pedido en curso, cada uno con su color:
  /// tú -> restaurante (azul) y restaurante -> cliente (rojo). Usa la ruta por
  /// calles de Google; si no hay, líneas rectas de respaldo.
  List<({bool alRestaurante, List<LatLng> puntos, bool porCalles})> _tramosDe(
    Pedido p,
  ) {
    final ruta = _rutaDe(p);
    if (ruta != null && ruta.tramos.isNotEmpty) {
      return [
        for (final t in ruta.tramos)
          if (t.puntos.length >= 2)
            (
              alRestaurante: t.haciaRestaurante,
              puntos: t.puntos,
              porCalles: ruta.esGoogle,
            ),
      ];
    }
    final yo = _yoPunto;
    final r = _punto(p.restauranteLatitud, p.restauranteLongitud);
    final c = _punto(p.latitudEntrega, p.longitudEntrega);
    if (p.estado == 'aceptado' && r != null) {
      return [
        if (yo != null)
          (alRestaurante: true, puntos: [yo, r], porCalles: false),
        if (c != null) (alRestaurante: false, puntos: [r, c], porCalles: false),
      ];
    }
    return [
      if (c != null)
        (
          alRestaurante: false,
          puntos: [if (yo != null) yo else if (r != null) r, c],
          porCalles: false,
        ),
    ];
  }

  /// Todos los puntos del trazo de un pedido en curso (para encuadrar el mapa).
  List<LatLng> _trazoActivo(Pedido p) => [
        for (final t in _tramosDe(p)) ...t.puntos,
      ];

  /// Una línea de color (con borde blanco debajo, si [conBorde]) para que
  /// resalte sobre las calles. [capa] decide cuál va encima: el tramo de ir al
  /// restaurante va debajo y más ancho, así, cuando el recorrido de regreso
  /// pasa por la misma calle, se ven los dos colores.
  Iterable<Polyline> _trazoConBorde(
    String id,
    List<LatLng> puntos,
    Color color, {
    double ancho = 6,
    bool discontinua = false,
    int capa = 0,
    bool conBorde = true,
  }) {
    return [
      if (conBorde)
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
        patterns: discontinua
            ? <PatternItem>[PatternItem.dash(18), PatternItem.gap(10)]
            : const <PatternItem>[],
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: capa * 2 + 2,
      ),
    ];
  }

  Set<Polyline> _trazos() {
    final trazos = <Polyline>{};

    if (_tab == 0) {
      final d = _disponibleSel;
      if (d == null) return trazos;
      final ruta = _rutas['disp-${d.id}'];
      if (ruta != null && ruta.tramos.isNotEmpty) {
        for (var i = 0; i < ruta.tramos.length; i++) {
          final t = ruta.tramos[i];
          if (t.puntos.length < 2) continue;
          trazos.addAll(
            _trazoConBorde(
              'prev-${d.id}-$i',
              t.puntos,
              t.haciaRestaurante ? _trazoAlRestaurante : _trazoAlCliente,
              ancho: t.haciaRestaurante ? 10 : 6,
              capa: t.haciaRestaurante ? 0 : 1,
              conBorde: t.haciaRestaurante,
              discontinua: !ruta.esGoogle,
            ),
          );
        }
        return trazos;
      }
      // Respaldo mientras llega la ruta (o si Google no responde).
      final r = _punto(d.restauranteLatitud, d.restauranteLongitud);
      final e = _punto(d.latitudEntrega, d.longitudEntrega);
      final yo = _yoPunto;
      if (yo != null && r != null) {
        trazos.addAll(
          _trazoConBorde(
            'prev-yo',
            [yo, r],
            _trazoAlRestaurante,
            ancho: 10,
            discontinua: true,
          ),
        );
      }
      if (r != null && e != null) {
        trazos.addAll(
          _trazoConBorde(
            'prev-ent',
            [r, e],
            _trazoAlCliente,
            capa: 1,
            conBorde: false,
            discontinua: true,
          ),
        );
      }
      return trazos;
    }

    final elegido = _activoSel;
    for (final p in activos) {
      final esElegido = elegido != null && p.id == elegido.id;
      var i = 0;
      for (final t in _tramosDe(p)) {
        if (t.puntos.length < 2) continue;
        final color = !esElegido
            ? _trazoSecundario
            : (t.alRestaurante ? _trazoAlRestaurante : _trazoAlCliente);
        trazos.addAll(
          _trazoConBorde(
            'ruta-${p.id}-${i++}',
            t.puntos,
            color,
            ancho: !esElegido ? 4 : (t.alRestaurante ? 10 : 6),
            capa: t.alRestaurante ? 0 : 1,
            conBorde: !esElegido || t.alRestaurante,
            discontinua: !t.porCalles,
          ),
        );
      }
    }
    return trazos;
  }

  /// Puntos que deben verse en el mapa en la pestaña actual.
  List<LatLng> _puntosVisibles() {
    final puntos = <LatLng>[];
    final yo = _yoPunto;
    if (yo != null) puntos.add(yo);

    if (_tab == 0) {
      final d = _disponibleSel;
      if (d != null) {
        final ruta = _rutas['disp-${d.id}'];
        if (ruta != null && ruta.puntos.length >= 2) {
          puntos.addAll(ruta.puntos);
          return puntos;
        }
        final r = _punto(d.restauranteLatitud, d.restauranteLongitud);
        final e = _punto(d.latitudEntrega, d.longitudEntrega);
        if (r != null) puntos.add(r);
        if (e != null) puntos.add(e);
      } else {
        for (final x in disponibles) {
          final r = _punto(x.restauranteLatitud, x.restauranteLongitud);
          if (r != null) puntos.add(r);
        }
      }
      return puntos;
    }

    final p = _activoSel;
    if (p != null) puntos.addAll(_trazoActivo(p));
    return puntos;
  }

  /// Pequeña espera para que el mapa termine de dibujarse tras un cambio.
  void _ajustarCamaraConEspera() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _ajustarCamara();
    });
  }

  /// Acerca la cámara para que se vea todo lo importante.
  Future<void> _ajustarCamara() async {
    final controlador = _mapa;
    if (controlador == null) return;

    final puntos = _puntosVisibles();
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
          _movil ? 56 : 90,
        ),
      );
    } catch (e) {
      debugPrint('No se pudo ajustar la cámara: $e');
    }
  }

  // ----------------------------------------------------------------- build

  bool _esAncha(BuildContext context) =>
      MediaQuery.of(context).size.width >= 980;

  @override
  Widget build(BuildContext context) {
    final ancha = _esAncha(context);
    _movil = !ancha;
    final arriba = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _papel,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(64 + arriba),
        child: _barraSuperior(ancha),
      ),
      body: ancha
          ? Row(
              children: [
                Container(
                  width: 456,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: _linea)),
                  ),
                  child: _panel(ancha),
                ),
                Expanded(child: _mapaCompleto()),
              ],
            )
          : _cuerpoMovil(),
    );
  }

  // ------------------------------------------------- celular: mapa + hoja

  /// Mapa casi a pantalla completa y, debajo, una hoja que se arrastra hacia
  /// arriba para ver los pedidos.
  Widget _cuerpoMovil() {
    return LayoutBuilder(
      builder: (context, c) {
        final alto = c.maxHeight;
        final inicial = (330 / alto).clamp(0.3, 0.5).toDouble();
        _hojaInicial = inicial;
        _hojaMax = 0.94;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: alto * inicial,
              child: _mapaCompleto(compacto: true),
            ),
            DraggableScrollableSheet(
              controller: _hoja,
              initialChildSize: inicial,
              minChildSize: inicial,
              maxChildSize: _hojaMax,
              snap: true,
              builder: (context, scroll) => _hojaMovil(scroll, alto),
            ),
          ],
        );
      },
    );
  }

  Widget _hojaMovil(ScrollController scroll, double alto) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 14,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _alternarHoja,
            onVerticalDragUpdate: (d) =>
                _arrastrarHoja(d.primaryDelta ?? 0, alto),
            onVerticalDragEnd: (d) => _soltarHoja(d.primaryVelocity ?? 0),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                  child: SizedBox(
                    width: 44,
                    height: 4,
                    child: ColoredBox(color: Color(0xFFB7CBC8)),
                  ),
                ),
                _encabezadoMovil(),
              ],
            ),
          ),
          _selectorTabs(repartido: true),
          if (_tab == 1 && activos.isNotEmpty) _barraAccionMovil(),
          Expanded(child: _contenidoMovil(scroll)),
        ],
      ),
    );
  }

  Widget _encabezadoMovil() {
    final conGps = posicion != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CENTRO DE REPARTO', style: _rotulo(size: 9.5)),
                const SizedBox(height: 2),
                Text('Panel del repartidor', style: _titulo(size: 19)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: _linea)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  color: conGps ? AppColors.mint : AppColors.error,
                ),
                const SizedBox(width: 7),
                Text(
                  conGps ? 'EN LÍNEA' : 'SIN GPS',
                  style: _rotulo(color: _tinta, size: 9.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: cargar,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(border: Border.all(color: _tinta)),
              child: const Icon(Icons.refresh, color: _tinta, size: 19),
            ),
          ),
        ],
      ),
    );
  }

  /// Acción siguiente del pedido en curso, siempre a la vista (sin bajar).
  Widget _barraAccionMovil() {
    final p = _activoSel;
    if (p == null) return const SizedBox.shrink();

    const orden = ['aceptado', 'recogido', 'en_camino', 'entregado'];
    final indice = orden.indexOf(p.estado);
    final siguiente =
        (indice >= 0 && indice < orden.length - 1) ? orden[indice + 1] : null;
    const textoAccion = {
      'recogido': 'Confirmar recogido',
      'en_camino': 'Iniciar entrega',
      'entregado': 'Confirmar entrega',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _papel,
        border: Border(bottom: BorderSide(color: _linea)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PEDIDO #${p.id} · ${p.restaurante.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rotulo(size: 10),
                ),
              ),
              const SizedBox(width: 8),
              _Rotulo(
                texto: textoEstado(p.estado).toUpperCase(),
                fondo: _tinta,
                color: Colors.white,
              ),
            ],
          ),
          if (siguiente != null) ...[
            const SizedBox(height: 10),
            _Boton(
              texto: textoAccion[siguiente] ?? 'Continuar',
              icono: Icons.arrow_forward,
              cargando: _ocupados.contains(p.id),
              onPressed: () => _cambiarEstado(p, siguiente),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contenidoMovil(ScrollController scroll) {
    final List<Widget> hijos;
    if (cargando) {
      hijos = const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (error != null) {
      hijos = [
        Text(error!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _Boton(texto: 'Intentar nuevamente', onPressed: cargar),
      ];
    } else {
      hijos = _tab == 0 ? _listaDisponibles() : _listaEnCurso();
    }
    return ListView(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: hijos,
    );
  }

  // ---------------------------------------------------------- barra superior

  Widget _barraSuperior(bool ancha) {
    final angosta = MediaQuery.of(context).size.width < 600;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _linea)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Image.asset(
                    'assets/images/logo-food-express.png',
                    width: angosta ? 110 : 150,
                    height: 46,
                    fit: BoxFit.contain,
                  ),
                  if (!angosta) ...[
                    const SizedBox(width: 14),
                    const _Rotulo(
                      texto: 'REPARTIDOR',
                      icono: Icons.two_wheeler,
                      fondo: _tinta,
                      color: Colors.white,
                    ),
                  ],
                  if (ancha)
                    Expanded(child: Center(child: _estadoConexion()))
                  else
                    const Spacer(),
                  _cuenta(compacta: angosta),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _estadoConexion() {
    final conGps = posicion != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _linea),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            color: conGps ? AppColors.mint : AppColors.error,
          ),
          const SizedBox(width: 10),
          Text(
            conGps
                ? 'CONECTADO · EN LÍNEA PARA ENTREGAS'
                : 'SIN GPS · ACTIVA TU UBICACIÓN',
            style: _rotulo(color: _tinta, size: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _cuenta({required bool compacta}) {
    final nombre = widget.usuario.nombre;
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
    return PopupMenuButton<String>(
      tooltip: 'Mi cuenta',
      shape: const RoundedRectangleBorder(),
      onSelected: (valor) {
        if (valor == 'actualizar') cargar();
        if (valor == 'perfil') _abrirPerfil();
        if (valor == 'salir') _cerrarSesion();
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          value: 'perfil',
          child: Row(
            children: [
              Icon(Icons.badge_outlined, size: 19),
              SizedBox(width: 9),
              Text('Mi perfil'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'actualizar',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 19),
              SizedBox(width: 9),
              Text('Actualizar pedidos'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _tinta, width: 1.6),
            ),
            child: Text(
              inicial,
              style: AppTypography.body(
                color: _tinta,
                weight: FontWeight.w700,
              ),
            ),
          ),
          if (!compacta) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MI CUENTA', style: _rotulo(color: _tinta, size: 10)),
                  Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(color: AppColors.hint, size: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.hint),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ panel

  Widget _panel(bool ancha) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CENTRO DE REPARTO', style: _rotulo()),
                        const SizedBox(height: 6),
                        Text('Panel del repartidor', style: _titulo(size: 27)),
                        const SizedBox(height: 6),
                        Text(
                          _tab == 0
                              ? 'Revisa y acepta pedidos cercanos para reparto inmediato.'
                              : 'Gestiona la ruta y el estado de entrega en tiempo real.',
                          style: AppTypography.body(
                            color: AppColors.hint,
                            size: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: 'Actualizar',
                    child: InkWell(
                      onTap: cargar,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          border: Border.all(color: _tinta),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: _tinta,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!ancha) ...[
                const SizedBox(height: 12),
                _estadoConexion(),
              ],
            ],
          ),
        ),
        _selectorTabs(),
        Expanded(child: _contenidoPanel()),
      ],
    );
  }

  Widget _contenidoPanel() {
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: _Boton(texto: 'Intentar nuevamente', onPressed: cargar),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: _tab == 0 ? _listaDisponibles() : _listaEnCurso(),
      ),
    );
  }

  /// [repartido]: celular, las dos pestañas ocupan todo el ancho.
  Widget _selectorTabs({bool repartido = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: repartido ? 0 : 24),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _linea),
          bottom: BorderSide(color: _linea),
        ),
      ),
      child: Row(
        children: repartido
            ? [
                Expanded(
                  child: _pestana(0, 'Disponibles', disponibles.length,
                      centrada: true),
                ),
                Expanded(
                  child: _pestana(1, 'En curso', activos.length,
                      centrada: true),
                ),
              ]
            : [
                _pestana(0, 'Disponibles', disponibles.length),
                const SizedBox(width: 28),
                _pestana(1, 'En curso', activos.length),
              ],
      ),
    );
  }

  Widget _pestana(int indice, String texto, int cuantos,
      {bool centrada = false}) {
    final activa = _tab == indice;
    return InkWell(
      onTap: () => _cambiarTab(indice),
      child: Container(
        alignment: centrada ? Alignment.center : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: activa ? _tinta : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto.toUpperCase(),
              style: _rotulo(color: activa ? _tinta : AppColors.hint, size: 11.5),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              color: activa ? _tinta : _linea,
              child: Text(
                '$cuantos',
                style: AppTypography.body(
                  size: 11,
                  weight: FontWeight.w700,
                  color: activa ? Colors.white : _tinta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ disponibles

  List<Widget> _listaDisponibles() {
    return [
      if (activos.isNotEmpty) _avisoEnCurso(),
      if (disponibles.isEmpty)
        const _Vacio(
          icono: Icons.inbox_outlined,
          titulo: 'No hay pedidos disponibles',
          texto: 'Cuando un cliente pague un pedido aparecerá aquí.',
        ),
      for (final p in disponibles) _tarjetaDisponible(p),
    ];
  }

  // Entregas simultáneas (Sprint 5): hasta 2 pedidos a la vez, con restaurantes
  // a menos de 3 km entre sí. El backend valida las mismas reglas.
  static const int _maxPedidos = 2;
  static const double _maxKmEntreRestaurantes = 3.0;

  /// Por qué no se puede aceptar este pedido ahora (null = sí se puede).
  String? _motivoBloqueo(PedidoDisponible p) {
    if (activos.length >= _maxPedidos) {
      return 'Ya llevas $_maxPedidos pedidos. Entrega uno antes de aceptar otro.';
    }
    for (final a in activos) {
      if (a.estado == 'en_camino') {
        return 'Vas en camino a entregar el pedido #${a.id}. Termínalo primero.';
      }
    }
    final lat = p.restauranteLatitud;
    final lon = p.restauranteLongitud;
    if (lat == null || lon == null) return null;
    for (final a in activos) {
      final aLat = a.restauranteLatitud;
      final aLon = a.restauranteLongitud;
      if (aLat == null || aLon == null) continue;
      final km = Geolocator.distanceBetween(aLat, aLon, lat, lon) / 1000;
      if (km > _maxKmEntreRestaurantes) {
        return 'Queda a ${km.toStringAsFixed(1)} km del pedido #${a.id} '
            '(máximo ${_maxKmEntreRestaurantes.toStringAsFixed(0)} km).';
      }
    }
    return null;
  }

  /// Aviso de pedidos en curso: cuántos lleva y si todavía puede tomar otro.
  Widget _avisoEnCurso() {
    final llenos = activos.length >= _maxPedidos;
    final enCamino = activos.any((a) => a.estado == 'en_camino');
    final ids = activos.map((a) => '#${a.id}').join(' y ');
    return _Caja(
      acento: _naranja,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AVISO', style: _rotulo(color: _naranja)),
                const SizedBox(height: 4),
                Text(
                  llenos
                      ? 'Llevas $_maxPedidos pedidos en curso'
                      : 'Tienes un pedido en curso',
                  style: AppTypography.body(weight: FontWeight.w700, size: 15),
                ),
                Text(
                  llenos
                      ? 'Entrega uno de los pedidos $ids antes de aceptar otro.'
                      : enCamino
                          ? 'Termina la entrega del pedido $ids para poder aceptar otro.'
                          : 'Puedes tomar un segundo pedido si su restaurante queda a '
                          'menos de ${_maxKmEntreRestaurantes.toStringAsFixed(0)} km '
                          'del pedido $ids.',
                  style: AppTypography.body(color: AppColors.hint, size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _cambiarTab(1),
            style: TextButton.styleFrom(
              foregroundColor: _tinta,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text('VER RUTA', style: _rotulo(color: _tinta, size: 11)),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDisponible(PedidoDisponible p) {
    final ocupado = _ocupados.contains(p.id);
    // Hasta 2 pedidos a la vez (ver _motivoBloqueo).
    final motivo = _motivoBloqueo(p);
    final bloqueado = motivo != null;

    String km(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} km';

    return _Caja(
      seleccionada: _sel == p.id,
      onTap: () => _seleccionar(p.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PEDIDO #${p.id}', style: _rotulo()),
                    const SizedBox(height: 4),
                    Text(p.restaurante, style: _titulo(size: 21)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(dinero(p.total), style: _titulo(size: 22)),
                  const SizedBox(height: 6),
                  _etiquetaCobro(p.cobraEnEfectivo),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Itinerario(
            recoger: p.restauranteDireccion ?? p.restaurante,
            entregar: p.direccionEntrega ?? 'Sin dirección',
          ),
          const SizedBox(height: 18),
          _FranjaDatos(
            datos: [
              ('AL RESTAURANTE', km(p.distanciaKm)),
              ('DE ENTREGA', km(p.distanciaEntregaKm)),
              (
                'TIEMPO',
                p.minutosEstimados == null ? '—' : '≈ ${p.minutosEstimados} min',
              ),
            ],
          ),
          if (motivo != null) ...[
            const SizedBox(height: 12),
            Text(
              motivo,
              style: AppTypography.body(color: _naranja, size: 12.5),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Boton(
                  texto: 'Rechazar',
                  primario: false,
                  onPressed: ocupado
                      ? null
                      : () => _accion(
                            p.id,
                            () => PedidoService.rechazarPedido(_token, p.id),
                            exito: 'Pedido rechazado.',
                          ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _Boton(
                  texto: 'Aceptar pedido',
                  icono: Icons.check,
                  cargando: ocupado,
                  bloqueado: bloqueado,
                  onPressed: () => _accion(
                    p.id,
                    () => PedidoService.aceptarPedido(_token, p.id),
                    exito: 'Pedido #${p.id} aceptado.',
                    irAEnCurso: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _etiquetaCobro(bool efectivo) {
    return efectivo
        ? const _Rotulo(
            texto: 'COBRAR EN EFECTIVO',
            icono: Icons.payments_outlined,
            fondo: _naranjaSuave,
            color: _naranja,
          )
        : const _Rotulo(
            texto: 'YA PAGADO',
            icono: Icons.check,
            fondo: Color(0xFFDDF6E6),
            color: _tinta,
          );
  }

  // --------------------------------------------------------------- en curso

  List<Widget> _listaEnCurso() {
    if (activos.isEmpty) {
      return const [
        _Vacio(
          icono: Icons.alt_route,
          titulo: 'No tienes pedidos en curso',
          texto: 'Acepta uno en «Disponibles» y aquí verás tu ruta.',
        ),
      ];
    }
    return [
      _tarjetaRuta(),
      for (final p in activos) _tarjetaActivo(p),
    ];
  }

  /// Solo si hubiera varios pedidos a la vez: orden sugerido de paradas (#11).
  Widget _tarjetaRuta() {
    final r = ruta;
    if (activos.length < 2 || r == null || r.tramos.isEmpty) {
      return const SizedBox.shrink();
    }
    return _Caja(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('RUTA SUGERIDA', style: _rotulo())),
              Text(
                '${r.distanciaTotalKm.toStringAsFixed(1)} km · ${r.minutosTotal} min',
                style: _titulo(size: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < r.tramos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Nodo(texto: '${i + 1}', relleno: i == 0),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.tramos[i].tipo == 'recoger' ? 'Recoger en' : 'Entregar en'} ${r.tramos[i].destino}',
                          style: AppTypography.body(
                            weight: FontWeight.w600,
                            size: 13.5,
                          ),
                        ),
                        Text(
                          'Pedido #${r.tramos[i].pedidoId} · ${r.tramos[i].distanciaKm.toStringAsFixed(1)} km · ${r.tramos[i].minutos} min',
                          style: AppTypography.body(
                            color: AppColors.hint,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _ordenEstados = ['aceptado', 'recogido', 'en_camino', 'entregado'];
  static const _textoAccion = {
    'recogido': 'Confirmar recogido',
    'en_camino': 'Iniciar entrega',
    'entregado': 'Confirmar entrega',
  };

  /// Estado al que sigue el pedido (null si ya no hay más pasos).
  String? _siguienteDe(Pedido p) {
    final indice = _ordenEstados.indexOf(p.estado);
    return (indice >= 0 && indice < _ordenEstados.length - 1)
        ? _ordenEstados[indice + 1]
        : null;
  }

  /// En pantalla ancha, el avance y el botón de la acción siguiente del
  /// pedido elegido van sobre el mapa (abajo a la derecha), no en la lista.
  bool _accionEnMapa(Pedido p) => !_movil && _activoSel?.id == p.id;

  Widget _tarjetaActivo(Pedido p) {
    final ocupado = _ocupados.contains(p.id);
    final haciaRestaurante = p.estado == 'aceptado';
    final siguiente = _siguienteDe(p);
    const textoAccion = _textoAccion;

    String? detalle(Tramo? t) => t == null
        ? null
        : '${t.distanciaKm.toStringAsFixed(1)} km · ${t.minutos} min';

    return _Caja(
      seleccionada: activos.length > 1 && _activoSel?.id == p.id,
      onTap: () => _seleccionar(p.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ORDEN ACTIVA · PEDIDO #${p.id}', style: _rotulo()),
                    const SizedBox(height: 4),
                    Text(p.restaurante, style: _titulo(size: 21)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Rotulo(
                texto: textoEstado(p.estado).toUpperCase(),
                fondo: _tinta,
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Itinerario(
            recoger: p.restauranteDireccion ?? p.restaurante,
            entregar: p.direccionEntrega ?? 'Sin dirección',
            detalleRecoger: detalle(_tramo(p.id, 'recoger')),
            detalleEntregar: detalle(_tramo(p.id, 'entregar')),
            recogido: !haciaRestaurante,
          ),
          if (p.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: _papel,
                border: Border.fromBorderSide(BorderSide(color: _linea)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONTENIDO', style: _rotulo(size: 9.5)),
                  const SizedBox(height: 4),
                  Text(
                    p.items.map((i) => '${i.cantidad}× ${i.nombre}').join(', '),
                    style: AppTypography.body(size: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(dinero(p.total), style: _titulo(size: 22)),
                      _etiquetaCobro(p.cobraEnEfectivo),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (!_accionEnMapa(p)) ...[
            const SizedBox(height: 20),
            Text('AVANCE DE LA ENTREGA', style: _rotulo()),
            const SizedBox(height: 10),
            _ProgresoEntrega(estado: p.estado),
          ],
          // El botón de la acción siguiente del pedido elegido va fijo arriba
          // (celular) o sobre el mapa (pantalla ancha); aquí solo los demás.
          if (siguiente != null && _activoSel?.id != p.id) ...[
            const SizedBox(height: 18),
            _Boton(
              texto: textoAccion[siguiente] ?? 'Continuar',
              icono: Icons.arrow_forward,
              cargando: ocupado,
              onPressed: () => _cambiarEstado(p, siguiente),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ mapa grande

  Widget _mapaCompleto({bool compacto = false}) {
    final enCurso = _tab == 1;
    final activo = _activoSel;
    final elegido = _disponibleSel;
    final conGps = posicion != null;
    final r = (enCurso && activo != null) ? _rutaDe(activo) : null;
    final tramo =
        ruta != null && ruta!.tramos.isNotEmpty ? ruta!.tramos.first : null;

    // ---- tarjeta superior
    final String rotuloTarjeta;
    final String textoTarjeta;
    String? detalleTarjeta;
    if (enCurso) {
      if (activo == null) {
        rotuloTarjeta = 'RUTA EN TIEMPO REAL';
        textoTarjeta = 'Sin pedidos en curso';
      } else {
        rotuloTarjeta = 'PRÓXIMA PARADA';
        textoTarjeta = tramo?.destino ??
            (activo.estado == 'aceptado' ? activo.restaurante : 'Cliente');
        if (tramo != null) {
          detalleTarjeta =
              '${tramo.minutos} min · ${tramo.distanciaKm.toStringAsFixed(1)} km';
        }
      }
    } else {
      rotuloTarjeta = 'PEDIDOS EN TU ZONA';
      textoTarjeta = disponibles.length == 1
          ? '1 punto de recogida'
          : '${disponibles.length} puntos de recogida';
      detalleTarjeta = 'Toca un pin o una tarjeta';
    }

    // ---- barra de datos
    final List<(String, String)> datos;
    final String pie;
    if (enCurso) {
      datos = [
        (
          'DISTANCIA',
          r == null ? '—' : '${(r.distanciaM / 1000).toStringAsFixed(1)} km',
        ),
        ('TIEMPO', r == null ? '—' : '${(r.duracionS / 60).ceil()} min'),
        ('GPS', conGps ? 'Activo' : 'Apagado'),
      ];
      if (activo == null) {
        pie = 'ACEPTA UN PEDIDO PARA EMPEZAR LA RUTA';
      } else if (r == null) {
        pie = 'CALCULANDO RUTA POR CALLES…';
      } else if (r.esGoogle) {
        pie = 'RUTA POR CALLES · GOOGLE MAPS';
      } else {
        pie = 'RUTA APROXIMADA · LÍNEA RECTA';
      }
    } else {
      datos = [
        ('PEDIDOS', '${disponibles.length}'),
        ('SELECCIÓN', elegido == null ? '—' : '#${elegido.id}'),
        ('GPS', conGps ? 'Activo' : 'Apagado'),
      ];
      final previa = elegido == null ? null : _rutas['disp-${elegido.id}'];
      pie = elegido == null
          ? 'TOCA UN PIN PARA VER EL RECORRIDO'
          : (previa != null && previa.esGoogle
              ? 'RUTA POR CALLES · PEDIDO #${elegido.id}'
              : 'TRAZO APROXIMADO · PEDIDO #${elegido.id}');
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _yoPunto ?? const LatLng(19.62, -99.31),
              zoom: 13,
            ),
            style: _estiloMapa,
            markers: _marcadores(),
            polylines: _trazos(),
            zoomControlsEnabled: !compacto,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            onMapCreated: (controlador) {
              _mapa = controlador;
              _ajustarCamaraConEspera();
            },
          ),
        ),
        Positioned(
          left: compacto ? 10 : 16,
          top: compacto ? 10 : 16,
          right: compacto ? 62 : 150,
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: EdgeInsets.fromLTRB(14, compacto ? 8 : 10, 16, compacto ? 8 : 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border.fromBorderSide(BorderSide(color: _linea)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(rotuloTarjeta, style: _rotulo(size: 9.5)),
                  const SizedBox(height: 3),
                  Text(
                    textoTarjeta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titulo(size: compacto ? 15 : 17),
                  ),
                  if (detalleTarjeta != null)
                    Text(
                      detalleTarjeta,
                      style: AppTypography.body(
                        color: AppColors.hint,
                        size: 12,
                      ),
                    ),
                  if (compacto && enCurso && activo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(pie, style: _rotulo(size: 8.5)),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: compacto ? 10 : 16,
          top: compacto ? 10 : 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tooltip(
                message: 'Centrar mapa',
                child: InkWell(
                  onTap: _ajustarCamara,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _linea),
                    ),
                    child: const Icon(
                      Icons.my_location,
                      size: 20,
                      color: _tinta,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (compacto)
          Positioned(
            left: 10,
            bottom: 34,
            right: 10,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _linea),
                ),
                child: _leyendaMapa(conPines: false),
              ),
            ),
          ),
        if (!compacto)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final accion = _tarjetaAccionMapa();
                // Mapa ancho: datos a la izquierda y acción a la derecha.
                // Mapa angosto: la acción ocupa el ancho y los datos se ocultan.
                final lado = c.maxWidth >= 760;
                return Stack(
                  children: [
                    if (accion == null || lado)
                      Positioned(
                        left: 16,
                        bottom: 36,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: _linea),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FranjaDatos(datos: datos, conBorde: false),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: _papel,
                                    border: Border(
                                      top: BorderSide(color: _linea),
                                    ),
                                  ),
                                  child: Text(pie, style: _rotulo(size: 9)),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: _linea),
                                    ),
                                  ),
                                  child: _leyendaMapa(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (accion != null)
                      Positioned(
                        right: 72,
                        bottom: 36,
                        left: lado ? null : 16,
                        width: lado ? 320 : null,
                        child: accion,
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  /// Pantalla ancha: avance de la entrega y botón de la acción siguiente,
  /// en una tarjeta abajo a la derecha del mapa.
  Widget? _tarjetaAccionMapa() {
    final p = _activoSel;
    if (_tab != 1 || p == null) return null;
    final siguiente = _siguienteDe(p);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _linea),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PEDIDO #${p.id} · AVANCE DE LA ENTREGA',
            style: _rotulo(size: 9.5),
          ),
          const SizedBox(height: 10),
          _ProgresoEntrega(estado: p.estado),
          if (siguiente != null) ...[
            const SizedBox(height: 14),
            _Boton(
              texto: _textoAccion[siguiente] ?? 'Continuar',
              icono: Icons.arrow_forward,
              cargando: _ocupados.contains(p.id),
              onPressed: () => _cambiarEstado(p, siguiente),
            ),
          ],
        ],
      ),
    );
  }

  /// Leyenda del mapa (va abajo, para no estorbar arriba a la derecha):
  /// los dos tramos del recorrido y los pines.
  Widget _leyendaMapa({bool conPines = true, bool soloRelevantes = true}) {
    final activo = _activoSel;
    final alRestaurante = !soloRelevantes ||
        _tab == 0 ||
        (activo != null && activo.estado == 'aceptado');
    final alCliente = !soloRelevantes || _tab == 0 || activo != null;

    Widget linea(Color color, String texto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 22, height: 5, color: color),
          const SizedBox(width: 6),
          Text(texto, style: AppTypography.body(size: 11)),
        ],
      );
    }

    Widget pin(Color color, String texto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, color: color),
          const SizedBox(width: 5),
          Text(texto, style: AppTypography.body(size: 11)),
        ],
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (alRestaurante) linea(_trazoAlRestaurante, 'Ir por el pedido'),
        if (alCliente) linea(_trazoAlCliente, 'Entregar al cliente'),
        if (conPines) ...[
          pin(_naranja, 'Restaurante'),
          pin(_rojo, 'Entrega'),
          pin(_azul, 'Tú'),
        ],
      ],
    );
  }
}

// ======================================================= widgets de apoyo

/// Tarjeta blanca de esquinas rectas, sin barras de color a un lado. Resalta
/// con el borde completo cuando está elegida, o con un tinte suave ([acento]).
class _Caja extends StatelessWidget {
  final Widget child;
  final bool seleccionada;
  final Color? acento;
  final VoidCallback? onTap;

  const _Caja({
    required this.child,
    this.seleccionada = false,
    this.acento,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borde = BorderSide(
      color: seleccionada ? _tinta : (acento ?? _linea),
      width: seleccionada ? 1.6 : 1,
    );
    final fondo = acento == null
        ? Colors.white
        : Color.alphaBlend(acento!.withAlpha(22), Colors.white);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: fondo,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(border: Border.fromBorderSide(borde)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Rótulo rectangular (estado, pago…).
class _Rotulo extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final Color fondo;
  final Color color;

  const _Rotulo({
    required this.texto,
    required this.fondo,
    required this.color,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      color: fondo,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              texto,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuadro con letra o número (puntos del itinerario).
class _Nodo extends StatelessWidget {
  final String texto;
  final bool relleno;

  const _Nodo({required this.texto, required this.relleno});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: relleno ? _tinta : Colors.white,
        border: Border.all(color: _tinta, width: 1.5),
      ),
      child: Text(
        texto,
        style: AppTypography.body(
          size: 12,
          weight: FontWeight.w700,
          color: relleno ? Colors.white : _tinta,
        ),
      ),
    );
  }
}

/// Recoger (A) y entregar (B) unidos por una línea.
class _Itinerario extends StatelessWidget {
  final String recoger;
  final String entregar;
  final String? detalleRecoger;
  final String? detalleEntregar;

  /// true cuando el pedido ya se recogió: el punto A aparece cumplido.
  final bool recogido;

  const _Itinerario({
    required this.recoger,
    required this.entregar,
    this.detalleRecoger,
    this.detalleEntregar,
    this.recogido = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fila(
          nodo: _Nodo(texto: recogido ? '✓' : 'A', relleno: true),
          rotulo: 'RECOGER EN',
          texto: recoger,
          detalle: detalleRecoger,
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: SizedBox(
            width: 1,
            height: 16,
            child: ColoredBox(color: _tinta),
          ),
        ),
        _fila(
          nodo: const _Nodo(texto: 'B', relleno: false),
          rotulo: 'ENTREGAR EN',
          texto: entregar,
          detalle: detalleEntregar,
        ),
      ],
    );
  }

  Widget _fila({
    required Widget nodo,
    required String rotulo,
    required String texto,
    String? detalle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nodo,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: _rotulo(size: 9.5)),
              const SizedBox(height: 2),
              Text(
                texto,
                style: AppTypography.body(weight: FontWeight.w600, size: 14),
              ),
            ],
          ),
        ),
        if (detalle != null) ...[
          const SizedBox(width: 8),
          Text(
            detalle,
            style: AppTypography.body(color: AppColors.hint, size: 11.5),
          ),
        ],
      ],
    );
  }
}

/// Franja de cifras separadas por líneas finas.
class _FranjaDatos extends StatelessWidget {
  final List<(String, String)> datos;
  final bool conBorde;

  const _FranjaDatos({required this.datos, this.conBorde = true});

  @override
  Widget build(BuildContext context) {
    final celdas = <Widget>[];
    for (var i = 0; i < datos.length; i++) {
      if (i > 0) celdas.add(const VerticalDivider(width: 1, color: _linea));
      celdas.add(
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(datos[i].$1, style: _rotulo(size: 9)),
                const SizedBox(height: 4),
                Text(datos[i].$2, style: _titulo(size: 17)),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      decoration:
          conBorde ? BoxDecoration(border: Border.all(color: _linea)) : null,
      child: IntrinsicHeight(child: Row(children: celdas)),
    );
  }
}

/// Avance de 3 pasos: Recogido, En camino, Entregado.
class _ProgresoEntrega extends StatelessWidget {
  final String estado;

  const _ProgresoEntrega({required this.estado});

  static const _pasos = ['Recogido', 'En camino', 'Entregado'];

  @override
  Widget build(BuildContext context) {
    const orden = ['aceptado', 'recogido', 'en_camino', 'entregado'];
    final actual = orden.indexOf(estado);

    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < _pasos.length - 1 ? 6 : 0),
              child: _paso(i, actual),
            ),
          ),
      ],
    );
  }

  Widget _paso(int i, int actual) {
    final hecho = actual >= i + 1;
    final enCurso = actual == i;
    final colorBarra =
        hecho ? AppColors.primary : (enCurso ? AppColors.mint : _linea);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 5, color: colorBarra),
        const SizedBox(height: 8),
        Text('0${i + 1}', style: _rotulo(size: 9.5)),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                _pasos[i],
                style: AppTypography.body(
                  size: 12.5,
                  weight: (hecho || enCurso) ? FontWeight.w700 : FontWeight.w500,
                  color: (hecho || enCurso) ? _tinta : AppColors.hint,
                ),
              ),
            ),
            if (hecho) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 14, color: AppColors.primary),
            ],
          ],
        ),
      ],
    );
  }
}

/// Botón rectangular de acción. [primario] va relleno; si no, con borde.
class _Boton extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool primario;
  final bool cargando;
  final bool bloqueado;

  const _Boton({
    required this.texto,
    required this.onPressed,
    this.icono,
    this.primario = true,
    this.cargando = false,
    this.bloqueado = false,
  });

  @override
  Widget build(BuildContext context) {
    final deshabilitado = onPressed == null || bloqueado || cargando;
    final Color fondo;
    final Color borde;
    final Color tinta;
    if (bloqueado) {
      fondo = _papel;
      borde = _linea;
      tinta = AppColors.hint;
    } else if (primario) {
      fondo = _tinta;
      borde = _tinta;
      tinta = Colors.white;
    } else {
      fondo = Colors.white;
      borde = _tinta;
      tinta = _tinta;
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: fondo,
        child: InkWell(
          onTap: deshabilitado ? null : onPressed,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: borde)),
            child: cargando
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: tinta,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          texto.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: tinta,
                          ),
                        ),
                      ),
                      if (icono != null) ...[
                        const SizedBox(width: 10),
                        Icon(icono, size: 18, color: tinta),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Estado vacío (sin pedidos).
class _Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;

  const _Vacio({
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return _Caja(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(color: _linea),
                color: _papel,
              ),
              child: Icon(icono, size: 28, color: _tinta),
            ),
            const SizedBox(height: 16),
            Text(titulo, style: _titulo(size: 18)),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: AppTypography.body(color: AppColors.hint, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}
