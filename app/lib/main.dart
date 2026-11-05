import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/auth/puerta_sesion.dart';

void main() {
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