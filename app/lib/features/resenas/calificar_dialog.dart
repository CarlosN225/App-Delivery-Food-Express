import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/seguridad/sanitizador.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../delivery/pedido_model.dart';
import 'estrellas.dart';
import 'resena_service.dart';

/// Ventana para calificar un pedido entregado: restaurante (obligatorio),
/// repartidor (opcional) y un comentario corto. Devuelve true si se guardó.
Future<bool> mostrarCalificar(
  BuildContext context, {
  required String token,
  required Pedido pedido,
}) async {
  final guardado = await showDialog<bool>(
    context: context,
    builder: (_) => _CalificarDialog(token: token, pedido: pedido),
  );
  return guardado == true;
}

class _CalificarDialog extends StatefulWidget {
  final String token;
  final Pedido pedido;

  const _CalificarDialog({required this.token, required this.pedido});

  @override
  State<_CalificarDialog> createState() => _CalificarDialogState();
}

class _CalificarDialogState extends State<_CalificarDialog> {
  static const Color grisBorde = Color(0xFFD3E2DF);

  int _restaurante = 0;
  int _repartidor = 0;
  final TextEditingController _comentario = TextEditingController();
  bool _enviando = false;
  String? _error;

  TextStyle _rotulo({Color color = AppColors.hint}) => AppTypography.body(
        color: color,
        weight: FontWeight.w700,
        size: 10,
      ).copyWith(letterSpacing: 1.5);

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_restaurante == 0) {
      setState(() => _error = 'Elige de 1 a 5 estrellas para el restaurante.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ResenaService.crear(
        widget.token,
        pedidoId: widget.pedido.id,
        calificacionRestaurante: _restaurante,
        calificacionRepartidor:
            (widget.pedido.repartidorId != null && _repartidor > 0)
                ? _repartidor
                : null,
        comentario: _comentario.text,
      );
      if (!mounted) return;
      showAppSnackBar(context, '¡Gracias por tu reseña!', isError: false);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'No se pudo guardar tu reseña. Intenta de nuevo.';
      });
    }
  }

  Widget _bloque(String rotulo, String pregunta, int valor, ValueChanged<int> cambio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: _rotulo()),
        const SizedBox(height: 2),
        Text(pregunta, style: AppTypography.body(weight: FontWeight.w600, size: 14)),
        const SizedBox(height: 8),
        EstrellasSelector(valor: valor, onCambio: cambio),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final conRepartidor = widget.pedido.repartidorId != null;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(side: BorderSide(color: grisBorde)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CALIFICAR PEDIDO #${widget.pedido.id}', style: _rotulo()),
          const SizedBox(height: 4),
          Text(widget.pedido.restaurante, style: AppTypography.title(size: 20)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bloque('RESTAURANTE', '¿Qué tal estuvo la comida?', _restaurante,
                  (v) => setState(() => _restaurante = v)),
              if (conRepartidor) ...[
                const SizedBox(height: 16),
                _bloque('REPARTIDOR (OPCIONAL)', '¿Qué tal fue la entrega?', _repartidor,
                    (v) => setState(() => _repartidor = v)),
              ],
              const SizedBox(height: 16),
              Text('COMENTARIO (OPCIONAL)', style: _rotulo()),
              const SizedBox(height: 6),
              TextField(
                controller: _comentario,
                maxLines: 3,
                maxLength: 300,
                // Codificación segura: no se aceptan < > ni símbolos de marcado.
                inputFormatters: Sanitizador.formateadoresComentario,
                style: AppTypography.body(weight: FontWeight.w400, size: 14),
                decoration: InputDecoration(
                  hintText: 'Cuéntanos cómo te fue',
                  hintStyle: AppTypography.body(
                    color: AppColors.hint,
                    weight: FontWeight.w400,
                    size: 14,
                  ),
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: grisBorde),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: grisBorde),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppTypography.body(
                    color: AppColors.error,
                    weight: FontWeight.w500,
                    size: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context, false),
          child: Text('AHORA NO', style: _rotulo(color: AppColors.primaryDark)),
        ),
        TextButton(
          onPressed: _enviando ? null : _enviar,
          child: Text(
            _enviando ? 'ENVIANDO…' : 'ENVIAR RESEÑA',
            style: _rotulo(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
