import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import '../maps/mapas_service.dart';

/// Rastreo del pedido en tiempo real para el cliente (Sprint 4, historia #14).
/// Consulta el seguimiento cada 5 segundos y dibuja al repartidor en un mapa
/// de Google Maps, con la ruta por calles que calcula el backend (Routes API).
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
  GoogleMapController? _mapa;
  RutaMapa? _ruta;
  String? _estadoRuta;
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
      // La ruta por calles se pide una sola vez por estado (ahorra cuota).
      if (s.estado != _estadoRuta) {
        _estadoRuta = s.estado;
        _cargarRuta(s.estado);
      }
    } on ApiException catch (e) {
      _falla(e.mensaje);
    } catch (_) {
      _falla('No se pudo cargar el seguimiento.');
    }
  }

  Future<void> _cargarRuta(String estado) async {
    if (estado == 'entregado' || estado == 'cancelado') {
      if (mounted) setState(() => _ruta = null);
      return;
    }
    try {
      final ruta = await MapasService.rutaDePedido(
        widget.usuario.token,
        widget.pedidoId,
      );
      if (!mounted) return;
      setState(() => _ruta = ruta);
      _ajustarCamara();
    } catch (_) {
      // Sin ruta por calles: el mapa dibuja una línea recta de respaldo.
      debugPrint('No se pudo obtener la ruta por calles.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar('Rastreo de tu pedido'),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    final s = seguimiento;
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (s == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'No se pudo cargar el seguimiento.'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _mapaWidget(s),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _panel(s),
          ),
        ],
      ),
    );
  }

  LatLng? _punto(double? lat, double? lon) =>
      (lat == null || lon == null) ? null : LatLng(lat, lon);

  Marker _marcador(String id, LatLng posicion, String titulo, double tono) {
    return Marker(
      markerId: MarkerId(id),
      position: posicion,
      infoWindow: InfoWindow(title: titulo),
      icon: BitmapDescriptor.defaultMarkerWithHue(tono),
    );
  }

  /// Puntos que deben verse en el mapa (marcadores y ruta).
  List<LatLng> _puntosVisibles(Seguimiento s) {
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final antesDeRecoger = s.estado == 'pendiente' || s.estado == 'aceptado';

    return <LatLng>[
      if (antesDeRecoger && restaurante != null) restaurante,
      if (cliente != null) cliente,
      if (repartidor != null) repartidor,
      ...?_ruta?.puntos,
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
          56,
        ),
      );
    } catch (e) {
      debugPrint('No se pudo ajustar la cámara: $e');
    }
  }

  Widget _mapaWidget(Seguimiento s) {
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final antesDeRecoger = s.estado == 'pendiente' || s.estado == 'aceptado';

    // Trazo: la ruta por calles de Google; si no hay, una línea recta
    // repartidor -> (restaurante) -> cliente.
    final trazo = (_ruta != null && _ruta!.puntos.length >= 2)
        ? _ruta!.puntos
        : <LatLng>[
            if (repartidor != null) repartidor,
            if (antesDeRecoger && restaurante != null) restaurante,
            if (cliente != null) cliente,
          ];

    final marcadores = <Marker>{
      if (antesDeRecoger && restaurante != null)
        _marcador(
          'restaurante',
          restaurante,
          'Restaurante: ${s.restaurante}',
          BitmapDescriptor.hueAzure,
        ),
      if (cliente != null)
        _marcador('cliente', cliente, 'Tú', BitmapDescriptor.hueRed),
      if (repartidor != null)
        _marcador(
          'repartidor',
          repartidor,
          s.repartidorNombre ?? 'Repartidor',
          BitmapDescriptor.hueGreen,
        ),
    };

    final centro = _puntosVisibles(s).isNotEmpty
        ? _puntosVisibles(s).first
        : const LatLng(19.60, -99.31);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: centro, zoom: 15),
          markers: marcadores,
          polylines: {
            if (trazo.length >= 2)
              Polyline(
                polylineId: const PolylineId('ruta'),
                points: trazo,
                width: 5,
                color: AppColors.primary,
              ),
          },
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controlador) {
            _mapa = controlador;
            // Pequeña espera para que el mapa termine de dibujarse.
            Future.delayed(
              const Duration(milliseconds: 400),
              _ajustarCamara,
            );
          },
        ),
        Positioned(
          right: 10,
          top: 10,
          child: FloatingActionButton.small(
            heroTag: 'recentrar',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: _ajustarCamara,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _panel(Seguimiento s) {
    final activo = s.estado == 'aceptado' ||
        s.estado == 'recogido' ||
        s.estado == 'en_camino';

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activo)
            _PasosRastreo(estado: s.estado)
          else
            Text(_mensajeEstado(s.estado), style: AppTypography.subtitle()),
          if (activo) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.schedule, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _textoLlegada(s),
                    style: AppTypography.body(
                      weight: FontWeight.w700,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _textoRepartidor(s),
              style: AppTypography.body(color: AppColors.hint, size: 13),
            ),
            if (_ruta != null && _ruta!.esGoogle) ...[
              const SizedBox(height: 4),
              Text(
                'Ruta por calles (Google Maps): '
                '${(_ruta!.distanciaM / 1000).toStringAsFixed(1)} km · '
                '${(_ruta!.duracionS / 60).ceil()} min',
                style: AppTypography.body(color: AppColors.hint, size: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _mensajeEstado(String estado) => switch (estado) {
        'pendiente' => 'Buscando repartidor…',
        'entregado' => '¡Pedido entregado!',
        'cancelado' => 'Pedido cancelado.',
        _ => '',
      };

  String _textoLlegada(Seguimiento s) {
    final minutos = s.minutosRestantes;
    if (minutos == null) return 'Calculando tiempo de llegada…';
    final hora = DateTime.now().add(Duration(minutes: minutos));
    final hh = hora.hour.toString().padLeft(2, '0');
    final mm = hora.minute.toString().padLeft(2, '0');
    final km = s.distanciaRestanteKm;
    final distancia = km == null ? '' : ' · ${km.toStringAsFixed(1)} km';
    return 'Llega aprox. $hh:$mm$distancia';
  }

  String _textoRepartidor(Seguimiento s) {
    final nombre = s.repartidorNombre ?? 'Tu repartidor';
    final seg = s.segundosDesdeUbicacion;
    if (seg == null) return '$nombre aún no comparte su ubicación.';
    if (seg > 120) {
      return '$nombre — última señal hace ${(seg / 60).floor()} min.';
    }
    return '$nombre — ubicación en vivo.';
  }
}

/// Pasos del pedido: Aceptado → Recogido → En camino → Entregado.
class _PasosRastreo extends StatelessWidget {
  final String estado;

  const _PasosRastreo({required this.estado});

  static const _pasos = [
    ('aceptado', 'Aceptado', Icons.thumb_up_alt_outlined),
    ('recogido', 'Recogido', Icons.shopping_bag_outlined),
    ('en_camino', 'En camino', Icons.delivery_dining),
    ('entregado', 'Entregado', Icons.home_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final actual = _pasos.indexWhere((p) => p.$1 == estado);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(top: 18),
                color: i <= actual ? AppColors.primary : AppColors.border,
              ),
            ),
          _paso(_pasos[i].$2, _pasos[i].$3, i, actual),
        ],
      ],
    );
  }

  Widget _paso(String texto, IconData icono, int i, int actual) {
    final hecho = i < actual;
    final enCurso = i == actual;
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enCurso ? AppColors.primary : Colors.white,
            border: Border.all(
              color: (hecho || enCurso) ? AppColors.primary : AppColors.border,
              width: 2,
            ),
          ),
          child: Icon(
            hecho ? Icons.check : icono,
            size: 20,
            color: enCurso
                ? Colors.white
                : (hecho ? AppColors.primary : AppColors.hint),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          texto,
          style: AppTypography.body(
            size: 11,
            weight: enCurso ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}