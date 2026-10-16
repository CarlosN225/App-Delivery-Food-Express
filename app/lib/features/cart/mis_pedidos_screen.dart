import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import 'pago_screen.dart';

/// Abre "Mis pedidos" dejando la pantalla de inicio como única pantalla anterior.
void irAMisPedidos(
  BuildContext context,
  UsuarioAutenticado usuario, {
  String? mensaje,
}) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => MisPedidosScreen(usuario: usuario, mensajeInicial: mensaje),
    ),
    (route) => route.isFirst,
  );
}

/// Seguimiento del estado de los pedidos del cliente (historia #12, lado cliente).
/// Se actualiza sola cada 15 segundos.
class MisPedidosScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final String? mensajeInicial;

  const MisPedidosScreen({
    super.key,
    required this.usuario,
    this.mensajeInicial,
  });

  @override
  State<MisPedidosScreen> createState() => _MisPedidosScreenState();
}

class _MisPedidosScreenState extends State<MisPedidosScreen> {
  List<Pedido> pedidos = [];
  bool cargando = true;
  String? error;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cargar(silencioso: true),
    );
    final mensaje = widget.mensajeInicial;
    if (mensaje != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppSnackBar(context, mensaje, isError: false);
      });
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        cargando = true;
        error = null;
      });
    }
    try {
      final resultado = await PedidoService.misPedidos(widget.usuario.token);
      if (!mounted) return;
      setState(() {
        pedidos = resultado;
        cargando = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || silencioso) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted || silencioso) return;
      setState(() {
        error = 'No se pudieron cargar tus pedidos.';
        cargando = false;
      });
    }
  }

  Future<void> _cancelar(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Cancelar el pedido #${pedido.id}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await PedidoService.cancelarPedido(widget.usuario.token, pedido.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Pedido cancelado.', isError: false);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    }
    await _cargar(silencioso: true);
  }

  Future<void> _pagar(Pedido pedido) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PagoScreen(
          usuario: widget.usuario,
          pedido: pedido,
          abrirAlInicio: true,
        ),
      ),
    );
    if (mounted) _cargar(silencioso: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(
        'Mis pedidos',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargar,
          ),
        ],
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
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: pedidos.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    'Todavía no has hecho pedidos.',
                    style: AppTypography.subtitle(),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: pedidos.length,
              itemBuilder: (context, i) => _tarjeta(pedidos[i]),
            ),
    );
  }

  Widget _tarjeta(Pedido pedido) {
    final resumen = pedido.items
        .map((i) => '${i.cantidad}× ${i.nombre}')
        .join(', ');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedido #${pedido.id} · ${pedido.restaurante}',
                  style: AppTypography.body(weight: FontWeight.w700, size: 16),
                ),
              ),
              _EtiquetaEstado(estado: pedido.estado),
            ],
          ),
          const SizedBox(height: 6),
          if (resumen.isNotEmpty)
            Text(resumen, style: AppTypography.body(color: AppColors.hint, size: 13)),
          const SizedBox(height: 10),
          if (pedido.estado != 'cancelado') _ProgresoEntrega(estado: pedido.estado),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${pedido.metodoPagoTexto} · ${_textoPago(pedido)}',
                style: AppTypography.body(size: 13),
              ),
              Text(
                dinero(pedido.total),
                style: AppTypography.body(weight: FontWeight.w700, size: 18),
              ),
            ],
          ),
          if (pedido.estado == 'pendiente' && pedido.estadoPago != 'pagado') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlineActionButton(
                    label: 'Cancelar',
                    onPressed: () => _cancelar(pedido),
                  ),
                ),
                if (pedido.pagoPendiente) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: () => _pagar(pedido),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          pedido.estadoPago == 'rechazado'
                              ? 'Reintentar pago'
                              : 'Pagar ahora',
                          style: AppTypography.body(
                            color: Colors.white,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _textoPago(Pedido pedido) {
    switch (pedido.estadoPago) {
      case 'pagado':
        return 'pagado';
      case 'rechazado':
        return 'pago rechazado';
      case 'contra_entrega':
        return 'pagas al recibir';
      default:
        return 'pendiente de pago';
    }
  }
}

class _EtiquetaEstado extends StatelessWidget {
  final String estado;

  const _EtiquetaEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    final cancelado = estado == 'cancelado';
    final entregado = estado == 'entregado';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cancelado
            ? AppColors.error
            : (entregado ? AppColors.primaryDark : AppColors.mint),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        textoEstado(estado),
        style: AppTypography.body(
          weight: FontWeight.w600,
          size: 12,
          color: (cancelado || entregado) ? Colors.white : AppColors.primaryDark,
        ),
      ),
    );
  }
}

/// Barra con los pasos: Pendiente → Aceptado → Recogido → En camino → Entregado.
class _ProgresoEntrega extends StatelessWidget {
  final String estado;

  const _ProgresoEntrega({required this.estado});

  static const _pasos = ['pendiente', 'aceptado', 'recogido', 'en_camino', 'entregado'];

  @override
  Widget build(BuildContext context) {
    final actual = _pasos.indexOf(estado);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: actual < 0 ? 0 : (actual + 1) / _pasos.length,
            backgroundColor: AppColors.border,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          switch (estado) {
            'pendiente' => 'Buscando repartidor…',
            'aceptado' => 'El repartidor va al restaurante',
            'recogido' => 'El repartidor ya recogió tu pedido',
            'en_camino' => 'Tu pedido va en camino',
            'entregado' => '¡Pedido entregado!',
            _ => '',
          },
          style: AppTypography.body(size: 13, weight: FontWeight.w600),
        ),
      ],
    );
  }
}
