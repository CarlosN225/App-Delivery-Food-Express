import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'pedido_model.dart';
import 'pedido_service.dart';


class RepartidorScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const RepartidorScreen({
    super.key,
    required this.usuario,
  });

  @override
  State<RepartidorScreen> createState() => _RepartidorScreenState();
}


class _RepartidorScreenState extends State<RepartidorScreen> {
  List<Pedido> pedidos = [];

  bool cargando = true;
  String? error;


  @override
  void initState() {
    super.initState();

    cargarPedidos();
  }


  Future<void> cargarPedidos() async {
    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final resultado =
          await PedidoService.obtenerPedidosDisponibles();

      setState(() {
        pedidos = resultado;
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = 'No se pudieron cargar los pedidos.';
        cargando = false;
      });
    }
  }


  Future<void> aceptarPedido(Pedido pedido) async {
    try {
      await PedidoService.aceptarPedido(
        pedidoId: pedido.id,
        repartidorId: widget.usuario.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido aceptado correctamente.'),
        ),
      );

      cargarPedidos();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo aceptar el pedido.'),
        ),
      );
    }
  }


  Future<void> rechazarPedido(Pedido pedido) async {
    try {
      await PedidoService.rechazarPedido(pedido.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido rechazado.'),
        ),
      );

      cargarPedidos();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo rechazar el pedido.'),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del repartidor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarPedidos,
          ),
        ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: cargarPedidos,
              child: const Text('Intentar nuevamente'),
            ),
          ],
        ),
      );
    }

    if (pedidos.isEmpty) {
      return const Center(
        child: Text(
          'No hay pedidos disponibles.',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pedidos.length,

      itemBuilder: (context, index) {
        final pedido = pedidos[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),

          child: Padding(
            padding: const EdgeInsets.all(16),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Pedido #${pedido.id}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Restaurante: ${pedido.restaurante}',
                ),

                const SizedBox(height: 6),

                Text(
                  'Total: \$${pedido.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          rechazarPedido(pedido);
                        },
                        child: const Text('Rechazar'),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          aceptarPedido(pedido);
                        },
                        child: const Text('Aceptar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}