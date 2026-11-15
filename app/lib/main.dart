import 'package:flutter/material.dart';
import 'core/seguridad/entorno.dart';
import 'core/seguridad/registro.dart';
import 'core/theme.dart';
import 'features/auth/puerta_sesion.dart';

void main() {
  // Todos los logs pasan por un filtro: solo en DEBUG y sin datos personales.
  Registro.instalar();
  Registro.info('Arranque: ${Entorno.resumen}');
  runApp(const FoodExpressApp());
}

class FoodExpressApp extends StatelessWidget {
  const FoodExpressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Food Express',
      debugShowCheckedModeBanner: false,
      theme: buildFoodExpressTheme(),
      // Android 15 dibuja la app debajo de la barra de estado y la de
      // navegación; SafeArea la mantiene entre las dos. En web no cambia nada.
      builder: (context, child) => SafeArea(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const PuertaSesion(),
    );
  }
}