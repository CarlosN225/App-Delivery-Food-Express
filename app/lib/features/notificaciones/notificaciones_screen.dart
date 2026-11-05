import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../cart/rastreo_screen.dart';
import 'notificacion_service.dart';

/// Lista de notificaciones del cliente (Sprint 4, historia #15).
/// Al tocar una, se marca como leída y se abre el rastreo de ese pedido.
///
/// Mismo diseño que el menú y el carrito: esquinas rectas, líneas finas,
/// Poppins y rótulos pequeños en mayúsculas. En pantalla ancha, la lista va a
/// la izquierda y un panel con el resumen y los filtros a la derecha; en
/// celular, los filtros pasan arriba de la lista.
class NotificacionesScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const NotificacionesScreen({super.key, required this.usuario});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

/// Cómo se ve cada tipo de aviso (se deduce del título que manda el backend).
class _Tipo {
  final IconData icono;
  final String etiqueta;
  final bool alerta;

  const _Tipo(this.icono, this.etiqueta, {this.alerta = false});
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  // Colores y medidas (los mismos del menú y el carrito).
  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color menta = Color(0xFFE5F5F3);

  static const double _anchoMaximo = 1600;
  static const double _anchoConPanel = 1000;
  static const double _anchoPanel = 300;

  List<Notificacion> notificaciones = [];
  bool cargando = true;
  String? error;
  bool soloSinLeer = false;
  Timer? _reloj;

  String get _token => widget.usuario.token;

  int get _sinLeer => notificaciones.where((n) => !n.leida).length;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Se actualiza sola para que los avisos nuevos aparezcan sin recargar.
    _reloj = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
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
      if (!mounted || silencioso) return;
      setState(() {
        error = e.mensaje;
        cargando = false;
      });
    } catch (_) {
      if (!mounted || silencioso) return;
      setState(() {
        error = 'No se pudieron cargar tus notificaciones.';
        cargando = false;
      });
    }
  }

  Future<void> _marcarTodas() async {
    if (_sinLeer == 0) return;
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

  // =====================================================
  // AYUDAS
  // =====================================================

  TextStyle _rotulo({Color color = grisTexto, double size = 10}) {
    return AppTypography.body(
      color: color,
      weight: FontWeight.w700,
      size: size,
    ).copyWith(letterSpacing: 1.5);
  }

  _Tipo _tipoDe(Notificacion n) {
    final t = n.titulo.toLowerCase();
    if (t.contains('cancel')) {
      return const _Tipo(Icons.cancel_outlined, 'CANCELADO', alerta: true);
    }
    if (t.contains('entregado')) {
      return const _Tipo(Icons.check_circle_outline, 'ENTREGADO');
    }
    if (t.contains('camino')) {
      return const _Tipo(Icons.two_wheeler, 'EN CAMINO');
    }
    if (t.contains('recogido')) {
      return const _Tipo(Icons.shopping_bag_outlined, 'RECOGIDO');
    }
    if (t.contains('aceptado')) {
      return const _Tipo(Icons.thumb_up_alt_outlined, 'ACEPTADO');
    }
    return const _Tipo(Icons.notifications_none, 'AVISO');
  }

  /// Texto corto que invita a tocar la tarjeta, según el tipo de aviso.
  String _accion(_Tipo tipo) {
    if (tipo.etiqueta == 'ENTREGADO') return 'VER DETALLE DEL PEDIDO';
    if (tipo.alerta) return 'VER QUÉ PASÓ';
    return 'SEGUIR MI PEDIDO';
  }

  String _grupoDe(int segundos) {
    if (segundos < 86400) return 'HOY';
    if (segundos < 7 * 86400) return 'ESTA SEMANA';
    return 'ANTES';
  }

  List<Notificacion> get _visibles =>
      soloSinLeer ? notificaciones.where((n) => !n.leida).toList() : notificaciones;

  // =====================================================
  // BARRA SUPERIOR
  // =====================================================

  Widget _barraSuperior(double margen) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: margen),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: grisBorde)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: grisBorde),
              ),
              child: const Icon(Icons.arrow_back, color: verdeOscuro),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text('Notificaciones', style: AppTypography.title(size: 20)),
          ),
          Tooltip(
            message: 'Actualizar',
            child: InkWell(
              onTap: _cargar,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: grisBorde),
                ),
                child: const Icon(Icons.refresh, color: verdeOscuro),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Marcar todas como leídas',
            child: InkWell(
              onTap: _sinLeer == 0 ? null : _marcarTodas,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: grisBorde),
                ),
                child: Icon(
                  Icons.done_all,
                  color: _sinLeer == 0 ? grisBorde : verdeOscuro,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 32, color: grisBorde),
          const SizedBox(width: 14),
          Image.asset(
            'assets/images/logo-food-express.png',
            width: 110,
            height: 40,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ENCABEZADO Y FILTROS
  // =====================================================

  Widget _encabezado({required bool compacto}) {
    final sinLeer = _sinLeer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TU BANDEJA', style: _rotulo()),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                'Novedades de tus pedidos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title(size: compacto ? 20 : 24),
              ),
            ),
            if (sinLeer > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: verdeOscuro,
                child: Text(
                  sinLeer == 1 ? '1 nueva' : '$sinLeer nuevas',
                  style: AppTypography.body(
                    color: Colors.white,
                    weight: FontWeight.w600,
                    size: 12.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Aquí te avisamos cada vez que tu repartidor acepta, recoge o '
          'entrega tu pedido.',
          style: AppTypography.body(
            color: grisTexto,
            weight: FontWeight.w400,
            size: 13,
          ),
        ),
      ],
    );
  }

  Widget _pestana(String texto, int cuantas, bool activa, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: activa ? verdeOscuro : Colors.white,
          border: Border.all(color: activa ? verdeOscuro : grisBorde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto.toUpperCase(),
              style: _rotulo(
                color: activa ? Colors.white : verdeOscuro,
                size: 10.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$cuantas',
              style: AppTypography.body(
                color: activa ? Colors.white : grisTexto,
                weight: FontWeight.w600,
                size: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _pestana(
          'Todas',
          notificaciones.length,
          !soloSinLeer,
          () => setState(() => soloSinLeer = false),
        ),
        _pestana(
          'Sin leer',
          _sinLeer,
          soloSinLeer,
          () => setState(() => soloSinLeer = true),
        ),
      ],
    );
  }

  // =====================================================
  // TARJETAS
  // =====================================================

  Widget _etiquetaNueva() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: verdeOscuro,
        child: Text('NUEVA', style: _rotulo(color: Colors.white, size: 8.5)),
      );

  /// Tarjeta compacta. En pantalla ancha todo va en una sola línea
  /// (icono, título, mensaje, pedido, hora y flecha); en celular, en dos.
  Widget _tarjeta(Notificacion n) {
    final tipo = _tipoDe(n);
    final nueva = !n.leida;
    const colorAlerta = AppColors.error;

    final Color fondoIcono = tipo.alerta
        ? (nueva ? colorAlerta : const Color(0xFFF8E3E6))
        : (nueva ? verdeOscuro : menta);
    final Color colorIcono = tipo.alerta
        ? (nueva ? Colors.white : colorAlerta)
        : (nueva ? Colors.white : grisTexto);
    final Color colorRotulo = tipo.alerta ? colorAlerta : turquesa;

    final etiquetaPedido = n.pedidoId == null
        ? tipo.etiqueta
        : '${tipo.etiqueta} · #${n.pedidoId}';

    final icono = Container(
      width: 40,
      height: 40,
      color: fondoIcono,
      child: Icon(tipo.icono, color: colorIcono, size: 21),
    );

    final titulo = Text(
      n.titulo,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body(
        weight: nueva ? FontWeight.w700 : FontWeight.w600,
        size: 14.5,
      ),
    );

    final mensaje = Text(
      n.mensaje,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body(
        color: nueva ? verdeOscuro : grisTexto,
        weight: FontWeight.w400,
        size: 13,
      ),
    );

    final hora = Text(
      tiempoRelativo(n.haceSegundos),
      style: AppTypography.body(
        color: grisTexto,
        weight: FontWeight.w500,
        size: 12,
      ),
    );

    final flecha = Tooltip(
      message: _accion(tipo)[0] + _accion(tipo).substring(1).toLowerCase(),
      child: Icon(
        Icons.arrow_forward,
        size: 17,
        color: n.pedidoId == null ? Colors.transparent : turquesa,
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final enFila = c.maxWidth >= 640;

        final Widget contenido;
        if (enFila) {
          contenido = Row(
            children: [
              icono,
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: Text(
                  etiquetaPedido,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rotulo(color: colorRotulo, size: 9.5),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: titulo,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: mensaje),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (nueva) ...[_etiquetaNueva(), const SizedBox(width: 12)],
              SizedBox(
                width: 104,
                child: Align(alignment: Alignment.centerRight, child: hora),
              ),
              const SizedBox(width: 12),
              flecha,
            ],
          );
        } else {
          contenido = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icono,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            etiquetaPedido,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _rotulo(color: colorRotulo, size: 9.5),
                          ),
                        ),
                        if (nueva) ...[
                          _etiquetaNueva(),
                          const SizedBox(width: 8),
                        ],
                        hora,
                      ],
                    ),
                    const SizedBox(height: 3),
                    titulo,
                    const SizedBox(height: 1),
                    mensaje,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              flecha,
            ],
          );
        }

        return Material(
          color: nueva ? menta : Colors.white,
          child: InkWell(
            onTap: () => _abrir(n),
            hoverColor: const Color(0xFFDDF1EE),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: nueva ? turquesa : grisBorde,
                  width: nueva ? 1.5 : 1,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: enFila ? 8 : 9,
              ),
              child: contenido,
            ),
          ),
        );
      },
    );
  }

  Widget _tituloGrupo(String texto, int cuantas) {
    return Row(
      children: [
        Text(texto, style: _rotulo(color: verdeOscuro, size: 10.5)),
        const SizedBox(width: 8),
        Text(
          '$cuantas',
          style: AppTypography.body(
            color: grisTexto,
            weight: FontWeight.w600,
            size: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: grisBorde)),
      ],
    );
  }

  /// Tarjetas agrupadas por antigüedad (HOY, ESTA SEMANA, ANTES).
  List<Widget> _listaAgrupada() {
    final visibles = _visibles;
    if (visibles.isEmpty) return [_vacio()];

    final grupos = <String, List<Notificacion>>{};
    for (final n in visibles) {
      grupos.putIfAbsent(_grupoDe(n.haceSegundos), () => []).add(n);
    }

    final salida = <Widget>[];
    var primero = true;
    for (final g in grupos.entries) {
      if (!primero) salida.add(const SizedBox(height: 14));
      primero = false;
      salida.add(_tituloGrupo(g.key, g.value.length));
      salida.add(const SizedBox(height: 8));
      for (var i = 0; i < g.value.length; i++) {
        if (i > 0) salida.add(const SizedBox(height: 6));
        salida.add(_tarjeta(g.value[i]));
      }
    }
    return salida;
  }

  // =====================================================
  // PANEL DERECHO (pantalla ancha)
  // =====================================================

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            etiqueta,
            style: AppTypography.body(
              color: grisTexto,
              weight: FontWeight.w500,
              size: 13.5,
            ),
          ),
          const Spacer(),
          Text(
            valor,
            style: AppTypography.body(weight: FontWeight.w700, size: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _nota(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: turquesa),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: AppTypography.body(
                color: grisTexto,
                weight: FontWeight.w400,
                size: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    final sinLeer = _sinLeer;
    final total = notificaciones.length;
    final ultima =
        notificaciones.isEmpty ? '—' : tiempoRelativo(notificaciones.first.haceSegundos);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESUMEN', style: _rotulo()),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$sinLeer', style: AppTypography.title(size: 44)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  sinLeer == 1 ? 'aviso sin leer' : 'avisos sin leer',
                  style: AppTypography.body(
                    color: grisTexto,
                    weight: FontWeight.w500,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: grisBorde),
          const SizedBox(height: 8),
          _fila('Avisos en total', '$total'),
          _fila('Último aviso', ultima),
          const SizedBox(height: 10),
          Container(height: 1, color: grisBorde),
          const SizedBox(height: 16),
          Text('MOSTRAR', style: _rotulo()),
          const SizedBox(height: 10),
          _filtros(),
          const SizedBox(height: 18),
          Material(
            color: sinLeer == 0 ? const Color(0xFFBFD9D5) : verdeOscuro,
            child: InkWell(
              onTap: sinLeer == 0 ? null : _marcarTodas,
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.done_all, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'MARCAR TODAS COMO LEÍDAS',
                      style: _rotulo(color: Colors.white, size: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _nota(
            Icons.touch_app_outlined,
            'Toca un aviso para abrir el seguimiento de ese pedido.',
          ),
          _nota(
            Icons.sync,
            'Esta bandeja se actualiza sola cada pocos segundos.',
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ESTADOS: VACÍO, ERROR, CARGANDO
  // =====================================================

  Widget _vacio() {
    final filtrando = soloSinLeer && notificaciones.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: menta,
                  border: Border.all(color: grisBorde),
                ),
                child: Icon(
                  filtrando
                      ? Icons.mark_email_read_outlined
                      : Icons.notifications_none,
                  size: 40,
                  color: turquesa,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                filtrando ? 'ESTÁS AL DÍA' : 'TODO EN CALMA',
                style: _rotulo(),
              ),
              const SizedBox(height: 6),
              Text(
                filtrando ? 'No tienes avisos sin leer' : 'Aún no tienes avisos',
                textAlign: TextAlign.center,
                style: AppTypography.title(size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                filtrando
                    ? 'Ya revisaste todo lo que te mandamos.'
                    : 'Cuando hagas un pedido, aquí verás cada paso: cuándo '
                        'lo aceptan, lo recogen y llega a tu puerta.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14,
                ),
              ),
              if (filtrando) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => setState(() => soloSinLeer = false),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'VER TODAS LAS NOTIFICACIONES',
                      style: _rotulo(color: turquesa, size: 10.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCarga() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8E3E6),
                  border: Border.all(color: grisBorde),
                ),
                child: const Icon(
                  Icons.cloud_off_outlined,
                  size: 40,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 18),
              Text('ALGO SALIÓ MAL', style: _rotulo(color: AppColors.error)),
              const SizedBox(height: 6),
              Text(
                error ?? 'No se pudieron cargar tus notificaciones.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14,
                ),
              ),
              const SizedBox(height: 18),
              Material(
                color: verdeOscuro,
                child: InkWell(
                  onTap: _cargar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    child: Text(
                      'REINTENTAR',
                      style: _rotulo(color: Colors.white, size: 10.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final compacto = ancho < 700;
          final conPanel = ancho >= _anchoConPanel;

          final margen = ancho > _anchoMaximo + 48
              ? (ancho - _anchoMaximo) / 2
              : (compacto ? 14.0 : 24.0);

          return Column(
            children: [
              _barraSuperior(margen),
              Expanded(child: _cuerpo(margen, compacto, conPanel)),
            ],
          );
        },
      ),
    );
  }

  Widget _cuerpo(double margen, bool compacto, bool conPanel) {
    if (cargando) {
      return const Center(
        child: CircularProgressIndicator(color: turquesa, strokeWidth: 3),
      );
    }
    if (error != null) return _errorCarga();

    final lista = RefreshIndicator(
      color: turquesa,
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          conPanel ? 0 : margen,
          conPanel ? 18 : 14,
          conPanel ? 0 : margen,
          20,
        ),
        children: [
          _encabezado(compacto: compacto),
          if (!conPanel && notificaciones.isNotEmpty) ...[
            const SizedBox(height: 16),
            _filtros(),
          ],
          const SizedBox(height: 14),
          ..._listaAgrupada(),
        ],
      ),
    );

    if (!conPanel) return lista;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margen),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: lista),
          const SizedBox(width: 20),
          SizedBox(
            width: _anchoPanel,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 18, bottom: 20),
              child: _panel(),
            ),
          ),
        ],
      ),
    );
  }
}
