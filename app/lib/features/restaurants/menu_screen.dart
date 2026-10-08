import 'package:flutter/material.dart';

import 'restaurant_model.dart';
import 'restaurant_service.dart';

class MenuScreen extends StatefulWidget {
  final Restaurante restaurante;

  const MenuScreen({
    super.key,
    required this.restaurante,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Producto> productos = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargarMenu();
  }

  Future<void> cargarMenu() async {
    try {
      final resultado =
          await RestauranteService.obtenerProductosRestaurante(
        widget.restaurante.id,
      );

      setState(() {
        productos = resultado;
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = 'No se pudo cargar el menú.';
        cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurante.nombre),
      ),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (error != null) {
      return Center(
        child: Text(error!),
      );
    }

    if (productos.isEmpty) {
      return const Center(
        child: Text('Este restaurante todavía no tiene productos.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: productos.length,
      itemBuilder: (context, index) {
        final producto = productos[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              producto.nombre,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              producto.descripcion ?? 'Sin descripción',
            ),
            trailing: Text(
              '\$${producto.precio.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}