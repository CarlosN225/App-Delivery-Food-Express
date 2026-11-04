import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../cart/rastreo_screen.dart';
import 'notificacion_service.dart';

/// Lista de notificaciones del cliente (Sprint 4, historia #15).
/// Al tocar una, se marca como leída y se abre el rastreo de ese pedido.
class NotificacionesScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const NotificacionesScreen({super.key, required this.usuario});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  List<Notificacion> notificaciones = [];
  bool cargando = true;
  String? error;

  String get _token => widget.usuario.token;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        cargando = true;
        error = null;
      });
    }
    try {
      final resultado = await NotificacionService.listar(_token);
      if (!mounted) return;
      setState(() {
        notificaciones = resultado;
        cargando = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudieron cargar tus notificaciones.';
        cargando = false;
      });
    }
  }

  Future<void> _marcarTodas() async {
    try {
      await NotificacionService.marcarTodasLeidas(_token);
      await _cargar(silencioso: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    }
  }

  Future<void> _abrir(Notificacion n) async {
    if (!n.leida) {
      try {
        await NotificacionService.marcarLeida(_token, n.id);
      } catch (_) {}
      if (mounted) {
        setState(() {
          notificaciones = [
            for (final x in notificaciones) x.id == n.id ? x.copiaLeida() : x,
          ];
        });
      }
    }
    final pedidoId = n.pedidoId;
    if (pedidoId == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RastreoScreen(
          usuario: widget.usuario,
          pedidoId: pedidoId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAppBar(
        'Notificaciones',
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Marcar todas como leídas',
            onPressed: _marcarTodas,
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
      child: notificaciones.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    'Aún no tienes notificaciones.',
                    style: AppTypography.subtitle(),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: notificaciones.length,
              itemBuilder: (context, i) => _tarjeta(notificaciones[i]),
            ),
    );
  }

  Widget _tarjeta(Notificacion n) {
    return GestureDetector(
      onTap: () => _abrir(n),
      child: AppCard(
        borderColor: n.leida ? null : AppColors.primary,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Icon(
                Icons.notifications,
                color: n.leida ? AppColors.hint : AppColors.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    style: AppTypography.body(
                      weight: n.leida ? FontWeight.w600 : FontWeight.w700,
                      size: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(n.mensaje, style: AppTypography.body(size: 13)),
                  const SizedBox(height: 6),
                  Text(
                    tiempoRelativo(n.haceSegundos),
                    style: AppTypography.body(color: AppColors.hint, size: 12),
                  ),
                ],
              ),
            ),
            if (!n.leida)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 6),
                child: CircleAvatar(radius: 5, backgroundColor: AppColors.primary),
              ),
          ],
        ),
      ),
    );
  }
}