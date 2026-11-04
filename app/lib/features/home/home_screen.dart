import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../cart/carrito_screen.dart';
import '../cart/carrito_service.dart';
import '../cart/mis_pedidos_screen.dart';
import '../auth/login_screen.dart';
import '../restaurants/restaurant_model.dart';
import '../restaurants/restaurant_service.dart';
import '../restaurants/menu_screen.dart';
import '../delivery/repartidor_screen.dart';
import '../cart/rastreo_screen.dart';
import '../notificaciones/notificacion_service.dart';
import '../notificaciones/notificaciones_screen.dart';
import '../admin/admin_screen.dart';

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
  List<Restaurante> restaurantes = [];

  bool cargando = false;
  String? mensajeError;

  // --- Notificaciones (Sprint 4, historia #15) ---
  Timer? _temporizadorNotificaciones;
  int noLeidas = 0;
  int _ultimoNotificacionId = 0;
  bool _primeraSincronizacion = true;

  @override
  void initState() {
    super.initState();

    buscarRestaurantes();

    // Historia #15: el cliente revisa sus notificaciones cada 10 segundos.
    if (widget.usuario.rol == 'cliente') {
      _sincronizarNotificaciones();
      _temporizadorNotificaciones = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sincronizarNotificaciones(),
      );
    }
  }

  @override
  void dispose() {
    _temporizadorNotificaciones?.cancel();
    super.dispose();
  }

  Future<void> buscarRestaurantes() async {
    setState(() {
      cargando = true;
      mensajeError = null;
    });

    try {
      final posicion = await LocationService.obtenerUbicacionActual();

print('LATITUD: ${posicion?.latitude}');
print('LONGITUD: ${posicion?.longitude}');

      if (posicion == null) {
        setState(() {
          mensajeError = 'No se pudo obtener tu ubicación.';
          cargando = false;
        });

        return;
      }

      final resultados =
          await RestauranteService.obtenerRestaurantesCercanos(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
      );

      setState(() {
        restaurantes = resultados;
        cargando = false;
      });
    } catch (e) {
      setState(() {
        mensajeError = 'No se pudieron cargar los restaurantes.';
        cargando = false;
      });

      print('Error: $e');
    }
  }

  Future<void> _sincronizarNotificaciones() async {
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

      // La primera vez solo se toma nota de las que ya existen (sin avisos).
      if (!_primeraSincronizacion && nuevas.isNotEmpty) {
        _mostrarAviso(nuevas.first);
      }
      _primeraSincronizacion = false;
      setState(() => noLeidas = pendientes);
    } catch (_) {
      // Sin red: se reintenta en el siguiente ciclo.
    }
  }

  void _mostrarAviso(Notificacion n) {
    final pedidoId = n.pedidoId;
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.hideCurrentSnackBar();
    mensajero.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n.titulo,
              style: AppTypography.body(
                color: Colors.white,
                weight: FontWeight.w700,
              ),
            ),
            Text(
              n.mensaje,
              style: AppTypography.body(color: Colors.white, size: 13),
            ),
          ],
        ),
        action: pedidoId == null
            ? null
            : SnackBarAction(
                label: 'Ver',
                textColor: AppColors.mint,
                onPressed: () => _abrirRastreo(pedidoId),
              ),
      ),
    );
  }

  void _abrirRastreo(int pedidoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RastreoScreen(
          usuario: widget.usuario,
          pedidoId: pedidoId,
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          'Food Express',
          style: AppTypography.barTitle(),
        ),
        actions: [
          if (widget.usuario.rol == 'cliente') ...[
            ListenableBuilder(
              listenable: CarritoService.instance,
              builder: (context, _) => IconButton(
                tooltip: 'Mi carrito',
                icon: Badge(
                  isLabelVisible: !CarritoService.instance.vacio,
                  label: Text('${CarritoService.instance.totalPiezas}'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CarritoScreen(usuario: widget.usuario),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Mis pedidos',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        MisPedidosScreen(usuario: widget.usuario),
                  ),
                );
              },
            ),
          ],
          if (widget.usuario.rol == 'repartidor')
                      IconButton(
              tooltip: 'Notificaciones',
              icon: Badge(
                isLabelVisible: noLeidas > 0,
                label: Text('$noLeidas'),
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: _abrirNotificaciones,
            ),
  IconButton(
    icon: const Icon(Icons.delivery_dining),
    tooltip: 'Panel del repartidor',
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RepartidorScreen(
            usuario: widget.usuario,
          ),
        ),
      );
    },
  
  ),
            if (widget.usuario.rol == 'administrador')
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Panel administrativo',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminScreen(usuario: widget.usuario),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Buscar restaurantes',
            onPressed: buscarRestaurantes,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () {
              CarritoService.instance.vaciar();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              '¡Bienvenido, ${widget.usuario.nombre}!',
              style: AppTypography.title(size: 24),
            ),

            const SizedBox(height: 8),

            Text(
              'Restaurantes cercanos',
              style: AppTypography.title(size: 20),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _contenidoRestaurantes(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenidoRestaurantes() {
    if (cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (mensajeError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off,
              size: 60,
            ),

            const SizedBox(height: 12),

            Text(
              mensajeError!,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: buscarRestaurantes,
              child: const Text('Intentar nuevamente'),
            ),
          ],
        ),
      );
    }

    if (restaurantes.isEmpty) {
      return const Center(
        child: Text(
          'No hay restaurantes cercanos.',
        ),
      );
    }

    return ListView.builder(
      itemCount: restaurantes.length,

      itemBuilder: (context, index) {
        final restaurante = restaurantes[index];

        return Card(
  margin: const EdgeInsets.only(bottom: 12),

  child: InkWell(
    borderRadius: BorderRadius.circular(12),

    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MenuScreen(
            restaurante: restaurante,
            usuario: widget.usuario,
          ),
        ),
      );
    },

    child: ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.restaurant),
      ),

      title: Text(
        restaurante.nombre,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),

      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          if (restaurante.categoria != null)
            Text(restaurante.categoria!),

          if (restaurante.direccion != null)
            Text(restaurante.direccion!),

          const SizedBox(height: 4),

          Text(
            '${restaurante.distanciaKm.toStringAsFixed(2)} km de distancia',
          ),
        ],
      ),

      isThreeLine: true,

      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
      ),
    ),
  ),
);
      },
    );
  }
}