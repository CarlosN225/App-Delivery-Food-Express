import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Color de las estrellas llenas.
const Color colorEstrella = Color(0xFFE5A100);

/// Estrellas de solo lectura (1 a 5). Acepta decimales: 4.5 muestra media estrella.
class Estrellas extends StatelessWidget {
  final double valor;
  final double tamano;

  const Estrellas({super.key, required this.valor, this.tamano = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final IconData icono;
        if (valor >= i + 1) {
          icono = Icons.star;
        } else if (valor >= i + 0.5) {
          icono = Icons.star_half;
        } else {
          icono = Icons.star_border;
        }
        return Icon(icono, size: tamano, color: colorEstrella);
      }),
    );
  }
}

/// Texto corto de calificación: "★ 4.5 (12)" o "Sin reseñas".
class ResumenCalificacion extends StatelessWidget {
  final double? promedio;
  final int total;
  final double tamano;
  final Color color;

  const ResumenCalificacion({
    super.key,
    required this.promedio,
    required this.total,
    this.tamano = 14,
    this.color = AppColors.hint,
  });

  @override
  Widget build(BuildContext context) {
    if (promedio == null || total == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: tamano + 4, color: colorEstrella),
          const SizedBox(width: 4),
          Text(
            'Sin reseñas',
            style: AppTypography.body(color: color, weight: FontWeight.w400, size: tamano),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: tamano + 4, color: colorEstrella),
        const SizedBox(width: 4),
        Text(
          promedio!.toStringAsFixed(1),
          style: AppTypography.body(
            color: AppColors.primaryDark,
            weight: FontWeight.w700,
            size: tamano,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($total)',
          style: AppTypography.body(color: color, weight: FontWeight.w400, size: tamano),
        ),
      ],
    );
  }
}

/// Estrellas que se pueden tocar para elegir una calificación de 1 a 5.
class EstrellasSelector extends StatelessWidget {
  final int valor; // 0 = todavía sin elegir
  final ValueChanged<int> onCambio;
  final double tamano;

  const EstrellasSelector({
    super.key,
    required this.valor,
    required this.onCambio,
    this.tamano = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final llena = valor >= i + 1;
        return InkWell(
          onTap: () => onCambio(i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              llena ? Icons.star : Icons.star_border,
              size: tamano,
              color: colorEstrella,
            ),
          ),
        );
      }),
    );
  }
}
