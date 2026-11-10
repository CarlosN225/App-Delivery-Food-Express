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
      home: const PuertaSesion(),
    );
  }
}