import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import 'pedido_model.dart';
import 'pedido_service.dart';

/// Panel del repartidor (Sprint 3):
///  - Disponibles: pedidos pagados (o en efectivo) que esperan repartidor.
///  - En curso: pedidos aceptados con la ruta sugerida (#11) y los botones
///    Recogido / En camino / Entregado (#12).
class RepartidorScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const RepartidorScreen({super.key, required this.usuario});

  @override
  State<RepartidorScreen> createState() => _RepartidorScreenState();
}

class _RepartidorScreenState extends State<RepartidorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<PedidoDisponible> disponibles = [];
  List<Pedido> activos = [];
  RutaOptima? ruta;
  Position? posicion;

  bool cargando = true;
  String? error;

  /// Pedidos con una acción en curso (para no duplicar toques).
  final Set<int> _ocupados = {};

  String get _token => widget.usuario.token;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
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
      if (irAEnCurso && mounted) _tabs.animateTo(1);
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

  Future<void> _navegar(double? lat, double? lon) async {
    if (lat == null || lon == null) {
      showAppSnackBar(context, 'Este pedido no tiene coordenadas.');
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );
    final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abierto && mounted) {
      showAppSnackBar(context, 'No se pudo abrir el mapa.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(
        'Panel del repartidor',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: cargar,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Disponibles (${disponibles.length})'),
            Tab(text: 'En curso (${activos.length})'),
          ],
        ),
      ),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: cargar,
              child: const Text('Intentar nuevamente'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [_tabDisponibles(), _tabEnCurso()],
    );
  }

  Widget _vacio(String texto) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(texto, style: AppTypography.subtitle())),
      ],
    );
  }

  // ------------------------------------------------------------ disponibles

  Widget _tabDisponibles() {
    return RefreshIndicator(
      onRefresh: cargar,
      child: disponibles.isEmpty
          ? _vacio('No hay pedidos disponibles.')
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: disponibles.length,
              itemBuilder: (context, i) => _tarjetaDisponible(disponibles[i]),
            ),
    );
  }

  Widget _tarjetaDisponible(PedidoDisponible p) {
    final ocupado = _ocupados.contains(p.id);
    final distancias = <String>[
      if (p.distanciaKm != null)
        '${p.distanciaKm!.toStringAsFixed(1)} km hasta el restaurante',
      if (p.distanciaEntregaKm != null)
        '${p.distanciaEntregaKm!.toStringAsFixed(1)} km de entrega',
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.restaurante} · Pedido #${p.id}',
            style: AppTypography.body(weight: FontWeight.w700, size: 18),
          ),
          const SizedBox(height: 8),
          if (p.restauranteDireccion != null)
            _linea(Icons.storefront_outlined, 'Recoger: ${p.restauranteDireccion}'),
          if (p.direccionEntrega != null)
            _linea(Icons.location_on_outlined, 'Entregar: ${p.direccionEntrega}'),
          if (distancias.isNotEmpty)
            _linea(Icons.route_outlined, distancias.join(' · ')),
          if (p.minutosEstimados != null)
            _linea(Icons.timer_outlined, '≈ ${p.minutosEstimados} min en total'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dinero(p.total),
                style: AppTypography.title(size: 24),
              ),
              _EtiquetaCobro(efectivo: p.cobraEnEfectivo),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Aceptar',
                  loading: ocupado,
                  onPressed: () => _accion(
                    p.id,
                    () => PedidoService.aceptarPedido(_token, p.id),
                    exito: 'Pedido #${p.id} aceptado.',
                    irAEnCurso: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlineActionButton(
                  label: 'Rechazar',
                  onPressed: ocupado
                      ? null
                      : () => _accion(
                            p.id,
                            () => PedidoService.rechazarPedido(_token, p.id),
                            exito: 'Pedido rechazado.',
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- en curso

  Widget _tabEnCurso() {
    return RefreshIndicator(
      onRefresh: cargar,
      child: activos.isEmpty
          ? _vacio('No tienes pedidos en curso.')
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _tarjetaRuta(),
                for (final p in activos) _tarjetaActivo(p),
              ],
            ),
    );
  }

  /// Ruta óptima básica (#11): orden sugerido de paradas con km y minutos.
  Widget _tarjetaRuta() {
    final r = ruta;
    if (r == null || r.tramos.isEmpty) return const SizedBox.shrink();

    return AppCard(
      borderColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ruta sugerida', style: AppTypography.title(size: 20)),
          const SizedBox(height: 4),
          Text(
            '${r.distanciaTotalKm.toStringAsFixed(1)} km · ${r.minutosTotal} min en total',
            style: AppTypography.body(color: AppColors.hint, size: 14),
          ),
          if (posicion == null) ...[
            const SizedBox(height: 4),
            Text(
              'Activa tu ubicación para calcular la ruta desde donde estás.',
              style: AppTypography.body(color: AppColors.error, size: 12),
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < r.tramos.length; i++) _paradaRuta(i, r.tramos[i]),
        ],
      ),
    );
  }

  Widget _paradaRuta(int indice, Tramo t) {
    final recoger = t.tipo == 'recoger';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: recoger ? AppColors.mint : AppColors.primary,
            child: Text(
              '${indice + 1}',
              style: AppTypography.body(
                size: 12,
                weight: FontWeight.w700,
                color: recoger ? AppColors.primaryDark : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${recoger ? 'Recoger en' : 'Entregar en'} ${t.destino}',
                  style: AppTypography.body(weight: FontWeight.w600, size: 14),
                ),
                Text(
                  'Pedido #${t.pedidoId} · ${t.distanciaKm.toStringAsFixed(1)} km · ${t.minutos} min',
                  style: AppTypography.body(color: AppColors.hint, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaActivo(Pedido p) {
    final ocupado = _ocupados.contains(p.id);
    final haciaRestaurante = p.estado == 'aceptado';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedido #${p.id} · ${p.restaurante}',
                  style: AppTypography.body(weight: FontWeight.w700, size: 17),
                ),
              ),
              Text(
                textoEstado(p.estado),
                style: AppTypography.body(
                  color: AppColors.primary,
                  weight: FontWeight.w700,
                  size: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (p.restauranteDireccion != null)
            _linea(Icons.storefront_outlined, 'Recoger: ${p.restauranteDireccion}'),
          _linea(
            Icons.location_on_outlined,
            'Destino: ${p.direccionEntrega ?? 'Sin dirección'}',
          ),
          if (p.items.isNotEmpty)
            _linea(
              Icons.receipt_long_outlined,
              p.items.map((i) => '${i.cantidad}× ${i.nombre}').join(', '),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dinero(p.total), style: AppTypography.title(size: 22)),
              _EtiquetaCobro(efectivo: p.cobraEnEfectivo),
            ],
          ),
          const SizedBox(height: 12),
          _BotonesEstado(
            estado: p.estado,
            ocupado: ocupado,
            onCambiar: (nuevo) => _accion(
              p.id,
              () async {
                await PedidoService.cambiarEstado(_token, p.id, nuevo);
              },
              exito: nuevo == 'entregado'
                  ? '¡Pedido #${p.id} entregado!'
                  : 'Pedido #${p.id}: ${textoEstado(nuevo).toLowerCase()}.',
            ),
          ),
          const SizedBox(height: 10),
          OutlineActionButton(
            label: haciaRestaurante ? 'Ir al restaurante' : 'Ir con el cliente',
            icon: Icons.navigation_outlined,
            onPressed: () => haciaRestaurante
                ? _navegar(p.restauranteLatitud, p.restauranteLongitud)
                : _navegar(p.latitudEntrega, p.longitudEntrega),
          ),
        ],
      ),
    );
  }

  Widget _linea(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: AppTypography.body(size: 14))),
        ],
      ),
    );
  }
}

/// "Pagado" o "Cobrar en efectivo".
class _EtiquetaCobro extends StatelessWidget {
  final bool efectivo;

  const _EtiquetaCobro({required this.efectivo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: efectivo ? Colors.white : AppColors.mint,
        border: Border.all(
          color: efectivo ? AppColors.primary : AppColors.mint,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        efectivo ? 'Cobrar en efectivo' : 'Ya pagado',
        style: AppTypography.body(weight: FontWeight.w600, size: 12),
      ),
    );
  }
}

/// Botones del wireframe: Recogido | En camino | Entregado.
/// Solo está activo el siguiente paso; los anteriores aparecen como hechos.
class _BotonesEstado extends StatelessWidget {
  final String estado;
  final bool ocupado;
  final ValueChanged<String> onCambiar;

  const _BotonesEstado({
    required this.estado,
    required this.ocupado,
    required this.onCambiar,
  });

  static const _pasos = <(String, String)>[
    ('recogido', 'Recogido'),
    ('en_camino', 'En camino'),
    ('entregado', 'Entregado'),
  ];

  @override
  Widget build(BuildContext context) {
    // Orden de los estados para saber qué pasos ya se cumplieron.
    const orden = ['aceptado', 'recogido', 'en_camino', 'entregado'];
    final actual = orden.indexOf(estado);

    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _boton(i, actual)),
        ],
      ],
    );
  }

  Widget _boton(int i, int actual) {
    final (valor, texto) = _pasos[i];
    final hecho = actual >= i + 1; // el paso i corresponde al índice i+1 en `orden`
    final siguiente = actual == i;

    if (siguiente) {
      return SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: ocupado ? null : () => onCambiar(valor),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: ocupado
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    color: Colors.white,
                    weight: FontWeight.w600,
                    size: 13,
                  ),
                ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(
            color: hecho ? AppColors.mint : AppColors.border,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hecho) ...[
              const Icon(Icons.check, size: 16, color: AppColors.primary),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: hecho ? AppColors.primary : AppColors.hint,
                  weight: FontWeight.w600,
                  size: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
