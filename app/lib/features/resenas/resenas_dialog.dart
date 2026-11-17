import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'estrellas.dart';
import 'resena_service.dart';

/// Lista de reseñas de un restaurante (se abre desde su menú).
Future<void> mostrarResenasRestaurante(
  BuildContext context, {
  required int restauranteId,
  required String nombre,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ResenasDialog(restauranteId: restauranteId, nombre: nombre),
  );
}

class _ResenasDialog extends StatelessWidget {
  static const Color grisBorde = Color(0xFFD3E2DF);

  final int restauranteId;
  final String nombre;

  const _ResenasDialog({required this.restauranteId, required this.nombre});

  TextStyle _rotulo() => AppTypography.body(
        color: AppColors.hint,
        weight: FontWeight.w700,
        size: 10,
      ).copyWith(letterSpacing: 1.5);

  String _hace(int dias) {
    if (dias <= 0) return 'hoy';
    if (dias == 1) return 'ayer';
    return 'hace $dias días';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(side: BorderSide(color: grisBorde)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESEÑAS', style: _rotulo()),
          const SizedBox(height: 4),
          Text(nombre, style: AppTypography.title(size: 20)),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 360,
        child: FutureBuilder<ResenasRestaurante>(
          future: ResenaService.deRestaurante(restauranteId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snap.hasError || snap.data == null) {
              return Center(
                child: Text(
                  'No se pudieron cargar las reseñas.',
                  style: AppTypography.body(
                    color: AppColors.hint,
                    weight: FontWeight.w400,
                    size: 14,
                  ),
                ),
              );
            }
            final datos = snap.data!;
            if (datos.total == 0) {
              return Center(
                child: Text(
                  'Todavía no hay reseñas.\nSé el primero en calificar después de tu pedido.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    color: AppColors.hint,
                    weight: FontWeight.w400,
                    size: 14,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      datos.promedio!.toStringAsFixed(1),
                      style: AppTypography.title(size: 34),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Estrellas(valor: datos.promedio!, tamano: 18),
                        Text(
                          '${datos.total} ${datos.total == 1 ? 'reseña' : 'reseñas'}',
                          style: AppTypography.body(
                            color: AppColors.hint,
                            weight: FontWeight.w400,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: datos.resenas.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: grisBorde),
                    itemBuilder: (_, i) {
                      final r = datos.resenas[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Estrellas(valor: r.calificacion.toDouble(), tamano: 14),
                                const SizedBox(width: 8),
                                Text(
                                  '${r.autor} · ${_hace(r.haceDias)}',
                                  style: AppTypography.body(
                                    color: AppColors.hint,
                                    weight: FontWeight.w500,
                                    size: 12,
                                  ),
                                ),
                              ],
                            ),
                            if (r.comentario != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                r.comentario!,
                                style: AppTypography.body(
                                  weight: FontWeight.w400,
                                  size: 13.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CERRAR', style: _rotulo().copyWith(color: AppColors.primaryDark)),
        ),
      ],
    );
  }
}
