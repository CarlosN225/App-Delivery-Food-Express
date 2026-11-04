import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';

/// Rastreo del pedido en tiempo real para el cliente (Sprint 4, historia #14).
/// Consulta el seguimiento cada 5 segundos y dibuja al repartidor en el mapa.
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
  final MapController _mapa = MapController();
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

  Widget _mapaWidget(Seguimiento s) {
    final restaurante = _punto(s.restauranteLatitud, s.restauranteLongitud);
    final cliente = _punto(s.clienteLatitud, s.clienteLongitud);
    final repartidor = _punto(s.repartidorLatitud, s.repartidorLongitud);
    final antesDeRecoger = s.estado == 'pendiente' || s.estado == 'aceptado';

    // Puntos que deben verse en el mapa.
    final puntos = <LatLng>[
      if (antesDeRecoger && restaurante != null) restaurante,
      if (cliente != null) cliente,
      if (repartidor != null) repartidor,
    ];

    // Recorrido restante: repartidor -> (restaurante) -> cliente.
    final linea = <LatLng>[
      if (repartidor != null) repartidor,
      if (antesDeRecoger && restaurante != null && repartidor != null)
        restaurante,
      if (cliente != null) cliente,
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapa,
          options: MapOptions(
            initialCenter:
                puntos.isNotEmpty ? puntos.first : const LatLng(19.60, -99.31),
            initialZoom: 15,
            initialCameraFit: puntos.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(puntos),
                    padding: const EdgeInsets.all(56),
                    maxZoom: 17,
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.food_express',
            ),
            if (linea.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: linea,
                    strokeWidth: 4,
                    color: AppColors.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (antesDeRecoger && restaurante != null)
                  _marcador(
                    restaurante,
                    Icons.store,
                    'Restaurante',
                    AppColors.primaryDark,
                  ),
                if (cliente != null)
                  _marcador(cliente, Icons.location_on, 'Tú', AppColors.error),
                if (repartidor != null)
                  _marcador(
                    repartidor,
                    Icons.delivery_dining,
                    'Repartidor',
                    AppColors.primary,
                  ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap contributors'),
            ),
          ],
        ),
        Positioned(
          right: 10,
          top: 10,
          child: FloatingActionButton.small(
            heroTag: 'recentrar',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: () => _recentrar(puntos),
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  void _recentrar(List<LatLng> puntos) {
    if (puntos.length >= 2) {
      _mapa.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(puntos),
          padding: const EdgeInsets.all(56),
          maxZoom: 17,
        ),
      );
    } else if (puntos.length == 1) {
      _mapa.move(puntos.first, 16);
    }
  }

  Marker _marcador(LatLng punto, IconData icono, String etiqueta, Color color) {
    return Marker(
      point: punto,
      width: 96,
      height: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              etiqueta,
              style: AppTypography.body(
                color: Colors.white,
                size: 11,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Icon(icono, color: color, size: 32),
        ],
      ),
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