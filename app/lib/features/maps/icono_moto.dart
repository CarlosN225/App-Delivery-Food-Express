import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Ícono de moto para el repartidor en los mapas: círculo de color con borde
/// blanco y la moto de Material Icons (sin imágenes externas). Se usa con
/// `anchor: Offset(0.5, 0.5)` para que el centro quede sobre la posición.
Future<BitmapDescriptor> crearIconoMoto({
  Color color = const Color(0xFF1F6FEB),
  double tamano = 56,
}) async {
  const escala = 2.0;
  final grabador = ui.PictureRecorder();
  final lienzo = ui.Canvas(grabador)..scale(escala);
  final centro = Offset(tamano / 2, tamano / 2);

  // Sombra, borde blanco y relleno.
  lienzo.drawCircle(
    centro.translate(0, 2),
    tamano / 2 - 3,
    ui.Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  lienzo.drawCircle(centro, tamano / 2 - 3, ui.Paint()..color = Colors.white);
  lienzo.drawCircle(centro, tamano / 2 - 7, ui.Paint()..color = color);

  // Moto: el glifo de motocicleta de Material Icons, en blanco y centrado.
  const icono = Icons.two_wheeler;
  final pintor = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icono.codePoint),
      style: TextStyle(
        fontFamily: icono.fontFamily,
        package: icono.fontPackage,
        fontSize: tamano * 0.56,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  pintor.paint(
    lienzo,
    centro - Offset(pintor.width / 2, pintor.height / 2),
  );

  final imagen = await grabador.endRecording().toImage(
        (tamano * escala).round(),
        (tamano * escala).round(),
      );
  final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    datos!.buffer.asUint8List(),
    width: tamano,
    height: tamano,
  );
}
