import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import 'mis_pedidos_screen.dart';

/// Pago de un pedido con Mercado Pago (historia #10).
///
/// Abre el enlace de pago en el navegador; cuando el cliente regresa a la app
/// el backend confirma el pago con Mercado Pago (la app nunca decide si se pagó).
class PagoScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final Pedido pedido;

  /// true: abre el enlace de pago apenas se muestra la pantalla.
  final bool abrirAlInicio;

  const PagoScreen({
    super.key,
    required this.usuario,
    required this.pedido,
    this.abrirAlInicio = false,
  });

  @override
  State<PagoScreen> createState() => _PagoScreenState();
}

class _PagoScreenState extends State<PagoScreen> with WidgetsBindingObserver {
  bool abriendo = false;
  bool verificando = false;
  bool esDemo = false;
  bool yaSeAbrio = false;
  String? aviso;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.abrirAlInicio) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirPago());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver del navegador, se confirma el pago sin que el usuario haga nada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && yaSeAbrio) {
      _verificar(silencioso: true);
    }
  }

  Future<void> _abrirPago() async {
    if (abriendo) return;
    setState(() {
      abriendo = true;
      aviso = null;
    });
    try {
      final preferencia = await PedidoService.crearPreferenciaPago(
        widget.usuario.token,
        widget.pedido.id,
      );
      final abierto = await launchUrl(
        Uri.parse(preferencia.initPoint),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        esDemo = preferencia.esDemo;
        yaSeAbrio = abierto;
        if (!abierto) aviso = 'No se pudo abrir la página de pago.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => aviso = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => aviso = 'No se pudo abrir la página de pago.');
    } finally {
      if (mounted) setState(() => abriendo = false);
    }
  }

  Future<void> _verificar({bool silencioso = false}) async {
    if (verificando) return;
    setState(() => verificando = true);
    try {
      final estado = await PedidoService.verificarPago(
        widget.usuario.token,
        widget.pedido.id,
      );
      if (!mounted) return;

      if (estado == 'pagado') {
        irAMisPedidos(
          context,
          widget.usuario,
          mensaje:
              '¡Pago recibido! Tu pedido #${widget.pedido.id} ya está buscando repartidor.',
        );
        return;
      }
      if (!silencioso) {
        showAppSnackBar(
          context,
          estado == 'rechazado'
              ? 'El pago fue rechazado. Puedes intentarlo de nuevo.'
              : 'Aún no vemos tu pago. Si ya pagaste, espera unos segundos.',
        );
      }
    } on ApiException catch (e) {
      if (mounted && !silencioso) showAppSnackBar(context, e.mensaje);
    } catch (_) {
      if (mounted && !silencioso) {
        showAppSnackBar(context, 'No se pudo confirmar el pago.');
      }
    } finally {
      if (mounted) setState(() => verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar('Pago con Mercado Pago'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                const Icon(
                  Icons.handshake_outlined,
                  size: 56,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pedido #${pedido.id} · ${pedido.restaurante}',
                  textAlign: TextAlign.center,
                  style: AppTypography.subtitle(),
                ),
                const SizedBox(height: 4),
                Text(dinero(pedido.total), style: AppTypography.title(size: 32)),
                const SizedBox(height: 12),
                Text(
                  yaSeAbrio
                      ? 'Termina el pago en la página que se abrió y regresa '
                          'aquí. Si no se confirma solo, toca «Ya pagué».'
                      : 'Toca «Pagar ahora» para abrir Mercado Pago.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(color: AppColors.hint, size: 14),
                ),
                if (esDemo) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Modo demo: el backend no tiene credenciales de Mercado '
                    'Pago, el cobro es simulado.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(color: AppColors.hint, size: 12),
                  ),
                ],
                if (aviso != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    aviso!,
                    textAlign: TextAlign.center,
                    style: AppTypography.body(color: AppColors.error, size: 13),
                  ),
                ],
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Ya pagué',
                  loading: verificando,
                  onPressed: () => _verificar(),
                ),
                const SizedBox(height: 10),
                OutlineActionButton(
                  label: yaSeAbrio ? 'Abrir el pago otra vez' : 'Pagar ahora',
                  icon: Icons.open_in_new,
                  onPressed: abriendo ? null : _abrirPago,
                ),
                TextButton(
                  onPressed: () => irAMisPedidos(
                    context,
                    widget.usuario,
                    mensaje:
                        'Tu pedido #${pedido.id} queda pendiente de pago. Puedes pagarlo cuando quieras.',
                  ),
                  child: const Text('Pagar después'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
