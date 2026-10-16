import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_service.dart';
import 'carrito_service.dart';
import 'mis_pedidos_screen.dart';
import 'pago_screen.dart';

/// Pantalla 2 del wireframe del Sprint 3: "Pagar" (método de pago).
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

  String metodo = 'mercado_pago'; // 'mercado_pago' | 'efectivo'
  bool enviando = false;

  double get total => carrito.subtotal + widget.costoEnvio;

  @override
  void dispose() {
    _direccionController.dispose();
    super.dispose();
  }

  Future<void> _pagar() async {
    if (!_formKey.currentState!.validate()) return;
    final restaurante = carrito.restaurante;
    if (restaurante == null || carrito.vacio) {
      showAppSnackBar(context, 'Tu carrito está vacío.');
      return;
    }

    setState(() => enviando = true);
    try {
      final pedido = await PedidoService.crearPedido(
        widget.usuario.token,
        restauranteId: restaurante.id,
        items: carrito.itemsParaApi,
        direccion: _direccionController.text.trim(),
        latitud: widget.latitud,
        longitud: widget.longitud,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar('Pagar'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dirección de entrega', style: AppTypography.title(size: 20)),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _direccionController,
                    hint: 'Calle, número y colonia',
                    icon: Icons.location_on_outlined,
                    validator: (valor) {
                      if (valor == null || valor.trim().length < 3) {
                        return 'Escribe tu dirección de entrega.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'El repartidor llegará a tu ubicación actual.',
                    style: AppTypography.body(color: AppColors.hint, size: 12),
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Método de pago', style: AppTypography.title(size: 22)),
                  const SizedBox(height: 12),
                  _opcionPago(
                    valor: 'mercado_pago',
                    titulo: 'Mercado Pago',
                    icono: Icons.handshake_outlined,
                  ),
                  const SizedBox(height: 10),
                  _opcionPago(
                    valor: 'efectivo',
                    titulo: 'Efectivo',
                    icono: Icons.payments_outlined,
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTypography.title(size: 24)),
                      Text(dinero(total), style: AppTypography.title(size: 24)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Incluye envío de ${dinero(widget.costoEnvio)}',
                      style: AppTypography.body(color: AppColors.hint, size: 13),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: metodo == 'efectivo'
                        ? 'Confirmar pedido ${dinero(total)}'
                        : 'Pagar ${dinero(total)}',
                    loading: enviando,
                    onPressed: _pagar,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcionPago({
    required String valor,
    required String titulo,
    required IconData icono,
  }) {
    final seleccionado = metodo == valor;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enviando ? null : () => setState(() => metodo = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? AppColors.primary : AppColors.border,
            width: seleccionado ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icono, color: AppColors.primaryDark, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                titulo,
                style: AppTypography.body(weight: FontWeight.w700, size: 17),
              ),
            ),
            Icon(
              seleccionado ? Icons.radio_button_checked : Icons.radio_button_off,
              color: seleccionado ? AppColors.mint : AppColors.primaryDark,
            ),
          ],
        ),
      ),
    );
  }
}
