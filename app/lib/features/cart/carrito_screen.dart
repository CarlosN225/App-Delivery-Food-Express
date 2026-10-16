import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import 'carrito_service.dart';
import 'checkout_screen.dart';

/// Pantalla 1 del wireframe del Sprint 3: "Mi carrito".
class CarritoScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const CarritoScreen({super.key, required this.usuario});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final CarritoService carrito = CarritoService.instance;

  Position? posicion;
  Cotizacion? cotizacion;
  bool cargandoEnvio = true;
  String? errorEnvio;

  @override
  void initState() {
    super.initState();
    _calcularEnvio();
  }

  /// El envío depende de la distancia restaurante -> ubicación del cliente.
  Future<void> _calcularEnvio() async {
    final restaurante = carrito.restaurante;
    if (carrito.vacio || restaurante == null) return;

    setState(() {
      cargandoEnvio = true;
      errorEnvio = null;
    });

    try {
      final pos = await LocationService.obtenerUbicacionActual();
      if (pos == null) {
        throw ApiException(
          'No pudimos obtener tu ubicación. Activa el GPS y da permiso a la app.',
        );
      }
      final resultado = await PedidoService.cotizar(
        widget.usuario.token,
        restauranteId: restaurante.id,
        items: carrito.itemsParaApi,
        latitud: pos.latitude,
        longitud: pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        posicion = pos;
        cotizacion = resultado;
        cargandoEnvio = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        errorEnvio = e.mensaje;
        cargandoEnvio = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorEnvio = 'No pudimos calcular el envío. Intenta de nuevo.';
        cargandoEnvio = false;
      });
    }
  }

  void _confirmar() {
    final pos = posicion;
    final cot = cotizacion;
    if (pos == null || cot == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          usuario: widget.usuario,
          latitud: pos.latitude,
          longitud: pos.longitude,
          costoEnvio: cot.costoEnvio,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar('Mi carrito'),
      body: ListenableBuilder(
        listenable: carrito,
        builder: (context, _) {
          if (carrito.vacio) return _carritoVacio();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  carrito.restaurante?.nombre ?? '',
                  style: AppTypography.title(size: 20),
                ),
              ),
              for (final linea in carrito.lineas) _tarjetaLinea(linea),
              _resumen(),
            ],
          );
        },
      ),
    );
  }

  Widget _carritoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: AppColors.hint,
            ),
            const SizedBox(height: 12),
            Text('Tu carrito está vacío', style: AppTypography.subtitle()),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Ver restaurantes',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaLinea(LineaCarrito linea) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea.producto.nombre,
                  style: AppTypography.body(weight: FontWeight.w700, size: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  'x${linea.cantidad}',
                  style: AppTypography.body(color: AppColors.hint),
                ),
                const SizedBox(height: 4),
                Text(
                  dinero(linea.importe),
                  style: AppTypography.body(weight: FontWeight.w700, size: 20),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.outlined(
                    tooltip: 'Quitar uno',
                    onPressed: () => carrito.quitarUno(linea.producto.id),
                    icon: const Icon(Icons.remove, color: AppColors.primary),
                  ),
                  IconButton.filled(
                    tooltip: 'Agregar otro',
                    onPressed: () => carrito.agregar(
                      carrito.restaurante!,
                      linea.producto,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              OutlineActionButton(
                label: 'Eliminar',
                icon: Icons.delete_outline,
                onPressed: () => carrito.eliminar(linea.producto.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumen() {
    final subtotal = carrito.subtotal;
    final envio = cotizacion?.costoEnvio;
    final total = envio == null ? null : subtotal + envio;

    return AppCard(
      child: Column(
        children: [
          _filaMonto('Subtotal', dinero(subtotal)),
          const SizedBox(height: 6),
          _filaMonto(
            'Envío',
            cargandoEnvio
                ? 'Calculando…'
                : (envio == null ? '—' : dinero(envio)),
          ),
          const Divider(height: 24),
          _filaMonto(
            'Total',
            total == null ? '—' : dinero(total),
            grande: true,
          ),
          if (errorEnvio != null) ...[
            const SizedBox(height: 10),
            Text(
              errorEnvio!,
              textAlign: TextAlign.center,
              style: AppTypography.body(color: AppColors.error, size: 13),
            ),
            TextButton(
              onPressed: _calcularEnvio,
              child: const Text('Reintentar'),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Confirmar pedido',
            loading: cargandoEnvio,
            onPressed: cotizacion == null ? null : _confirmar,
          ),
        ],
      ),
    );
  }

  Widget _filaMonto(String etiqueta, String valor, {bool grande = false}) {
    final estilo = AppTypography.body(
      weight: grande ? FontWeight.w700 : FontWeight.w600,
      size: grande ? 22 : 16,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(etiqueta, style: estilo), Text(valor, style: estilo)],
    );
  }
}
