import 'package:flutter/material.dart';

import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../restaurants/restaurant_model.dart';
import '../restaurants/restaurant_service.dart';
import '../restaurants/menu_screen.dart';
import '../delivery/repartidor_screen.dart';

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

  @override
  void initState() {
    super.initState();

    buscarRestaurantes();
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
          if (widget.usuario.rol == 'repartidor')
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Buscar restaurantes',
            onPressed: buscarRestaurantes,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () {
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