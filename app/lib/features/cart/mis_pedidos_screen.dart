import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import '../resenas/calificar_dialog.dart';
import '../resenas/estrellas.dart';
import '../resenas/resena_service.dart';
import 'pago_screen.dart';
import 'rastreo_screen.dart';

/// Abre "Mis pedidos" dejando la pantalla de inicio como única pantalla anterior.
void irAMisPedidos(
  BuildContext context,
  UsuarioAutenticado usuario, {
  String? mensaje,
}) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => MisPedidosScreen(usuario: usuario, mensajeInicial: mensaje),
    ),
    (route) => route.isFirst,
  );
}

/// Seguimiento del estado de los pedidos del cliente (historia #12, lado cliente).
/// Se actualiza sola cada 15 segundos.
///
/// Mismo diseño que el menú, el carrito y las notificaciones: esquinas rectas,
/// líneas finas, Poppins y rótulos pequeños en mayúsculas. En pantalla ancha,
/// cada pedido es una fila compacta y a la derecha hay un panel con el resumen
/// y los filtros; en celular, la tarjeta se acomoda en tres renglones.
class MisPedidosScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final String? mensajeInicial;

  const MisPedidosScreen({
    super.key,
    required this.usuario,
    this.mensajeInicial,
  });

  @override
  State<MisPedidosScreen> createState() => _MisPedidosScreenState();
}

enum _Filtro { todos, enCurso, entregados, cancelados }

class _MisPedidosScreenState extends State<MisPedidosScreen> {
  // Colores y medidas (los mismos del menú, el carrito y las notificaciones).
  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color menta = Color(0xFFE5F5F3);
  static const Color rojoClaro = Color(0xFFF8E3E6);

  static const double _anchoMaximo = 1600;
  static const double _anchoConPanel = 1000;
  static const double _anchoPanel = 300;
  static const double _anchoFila = 900;

  static const _pasos = [
    'pendiente',
    'aceptado',
    'recogido',
    'en_camino',
    'entregado',
  ];

  List<Pedido> pedidos = [];
  // Reseñas que ya hice, por número de pedido (Sprint 5, historia #28).
  Map<int, MiResena> _misResenas = {};
  bool cargando = true;
  String? error;
  _Filtro filtro = _Filtro.todos;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cargar(silencioso: true),
    );
    final mensaje = widget.mensajeInicial;
    if (mensaje != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppSnackBar(context, mensaje, isError: false);
      });
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
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
      final resultado = await PedidoService.misPedidos(widget.usuario.token);
      Map<int, MiResena> resenas = _misResenas;
      try {
        final lista = await ResenaService.mias(widget.usuario.token);
        resenas = {for (final r in lista) r.pedidoId: r};
      } catch (_) {
        // Sin reseñas la pantalla sigue funcionando; solo no se ven las estrellas.
      }
      if (!mounted) return;
      setState(() {
        _misResenas = resenas;
        pedidos = resultado;
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
        error = 'No se pudieron cargar tus pedidos.';
        cargando = false;
      });
    }
  }

  Future<void> _cancelar(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: grisBorde),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CANCELAR PEDIDO', style: _rotulo()),
            const SizedBox(height: 4),
            Text(
              '¿Cancelar el pedido #${pedido.id}?',
              style: AppTypography.title(size: 20),
            ),
          ],
        ),
        content: Text(
          'Dejaremos de buscar repartidor para este pedido. '
          'Esta acción no se puede deshacer.',
          style: AppTypography.body(
            color: grisTexto,
            weight: FontWeight.w400,
            size: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('NO, CONSERVAR', style: _rotulo(color: verdeOscuro)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'SÍ, CANCELAR',
              style: _rotulo(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await PedidoService.cancelarPedido(widget.usuario.token, pedido.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Pedido cancelado.', isError: false);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    }
    await _cargar(silencioso: true);
  }

  Future<void> _calificar(Pedido pedido) async {
    final guardada = await mostrarCalificar(
      context,
      token: widget.usuario.token,
      pedido: pedido,
    );
    if (guardada && mounted) await _cargar(silencioso: true);
  }

  void _rastrear(Pedido pedido) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RastreoScreen(
          usuario: widget.usuario,
          pedidoId: pedido.id,
        ),
      ),
    );
  }

  Future<void> _pagar(Pedido pedido) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PagoScreen(
          usuario: widget.usuario,
          pedido: pedido,
          abrirAlInicio: true,
        ),
      ),
    );
    if (mounted) _cargar(silencioso: true);
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

  bool _enCurso(Pedido p) => p.estado != 'entregado' && p.estado != 'cancelado';

  int get _nEnCurso => pedidos.where(_enCurso).length;
  int get _nEntregados => pedidos.where((p) => p.estado == 'entregado').length;
  int get _nCancelados => pedidos.where((p) => p.estado == 'cancelado').length;

  double get _gastado => pedidos
      .where((p) => p.estado == 'entregado')
      .fold(0.0, (suma, p) => suma + p.total);

  List<Pedido> get _visibles {
    switch (filtro) {
      case _Filtro.todos:
        return pedidos;
      case _Filtro.enCurso:
        return pedidos.where(_enCurso).toList();
      case _Filtro.entregados:
        return pedidos.where((p) => p.estado == 'entregado').toList();
      case _Filtro.cancelados:
        return pedidos.where((p) => p.estado == 'cancelado').toList();
    }
  }

  IconData _iconoDe(String estado) {
    switch (estado) {
      case 'pendiente':
        return Icons.hourglass_top;
      case 'aceptado':
        return Icons.storefront_outlined;
      case 'recogido':
        return Icons.shopping_bag_outlined;
      case 'en_camino':
        return Icons.two_wheeler;
      case 'entregado':
        return Icons.check_circle_outline;
      default:
        return Icons.cancel_outlined;
    }
  }

  String _mensajeDe(String estado) {
    switch (estado) {
      case 'pendiente':
        return 'Buscando repartidor…';
      case 'aceptado':
        return 'El repartidor va al restaurante';
      case 'recogido':
        return 'El repartidor ya recogió tu pedido';
      case 'en_camino':
        return 'Tu pedido va en camino';
      case 'entregado':
        return '¡Pedido entregado!';
      default:
        return 'Pedido cancelado';
    }
  }

  String? _fecha(Pedido p) {
    final d = DateTime.tryParse(p.fechaCreacion ?? '')?.toLocal();
    if (d == null) return null;
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${d.day} ${meses[d.month - 1]}';
  }

  String _resumenItems(Pedido p) =>
      p.items.map((i) => '${i.cantidad}× ${i.nombre}').join(', ');

  // =====================================================
  // BARRA SUPERIOR
  // =====================================================

  Widget _botonBarra(IconData icono, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: grisBorde),
          ),
          child: Icon(icono, color: verdeOscuro),
        ),
      ),
    );
  }

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
          _botonBarra(Icons.arrow_back, 'Regresar', () => Navigator.pop(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Text('Mis pedidos', style: AppTypography.title(size: 20)),
          ),
          _botonBarra(Icons.refresh, 'Actualizar', _cargar),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HISTORIAL', style: _rotulo()),
        const SizedBox(height: 4),
        Text(
          'Tus pedidos',
          style: AppTypography.title(size: compacto ? 20 : 24),
        ),
      ],
    );
  }

  Widget _pestana(String texto, int cuantos, _Filtro valor) {
    final activa = filtro == valor;
    return InkWell(
      onTap: () => setState(() => filtro = valor),
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
              '$cuantos',
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
        _pestana('Todos', pedidos.length, _Filtro.todos),
        _pestana('En curso', _nEnCurso, _Filtro.enCurso),
        _pestana('Entregados', _nEntregados, _Filtro.entregados),
        if (_nCancelados > 0)
          _pestana('Cancelados', _nCancelados, _Filtro.cancelados),
      ],
    );
  }

  // =====================================================
  // PIEZAS DE LA TARJETA
  // =====================================================

  Widget _icono(Pedido p) {
    final cancelado = p.estado == 'cancelado';
    final enCurso = _enCurso(p);
    return Container(
      width: 36,
      height: 36,
      color: cancelado ? rojoClaro : (enCurso ? verdeOscuro : menta),
      child: Icon(
        _iconoDe(p.estado),
        size: 19,
        color: cancelado
            ? AppColors.error
            : (enCurso ? Colors.white : turquesa),
      ),
    );
  }

  /// Estado del pedido, lo más simple posible:
  ///  - en curso: texto + una línea fina que se va llenando;
  ///  - entregado / cancelado: solo un icono pequeño y la palabra.
  Widget _progreso(Pedido p) {
    if (p.estado == 'entregado' || p.estado == 'cancelado') {
      final ok = p.estado == 'entregado';
      final color = ok ? turquesa : AppColors.error;
      return Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            ok ? 'Entregado' : 'Cancelado',
            style: AppTypography.body(
              weight: FontWeight.w600,
              size: 13.5,
              color: ok ? verdeOscuro : color,
            ),
          ),
        ],
      );
    }

    final avance = (_pasos.indexOf(p.estado) + 1) / _pasos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _mensajeDe(p.estado),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(
            weight: FontWeight.w600,
            size: 13,
            color: verdeOscuro,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 3,
          color: grisBorde,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: avance,
            child: Container(color: turquesa),
          ),
        ),
      ],
    );
  }

  Widget _boton(
    String texto,
    VoidCallback onTap, {
    bool relleno = false,
    IconData? icono,
    Color color = verdeOscuro,
  }) {
    return Material(
      color: relleno ? color : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: relleno ? color : grisBorde),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(icono, size: 15, color: relleno ? Colors.white : color),
                const SizedBox(width: 6),
              ],
              Text(
                texto.toUpperCase(),
                style: _rotulo(
                  color: relleno ? Colors.white : color,
                  size: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Botones que correspondan al estado del pedido (vacío si no hay ninguno).
  List<Widget> _acciones(Pedido p) {
    final puedeCancelar = p.estado == 'pendiente' && p.estadoPago != 'pagado';
    return [
      if (p.activo)
        _boton(
          'Rastrear',
          () => _rastrear(p),
          icono: Icons.location_on_outlined,
          color: turquesa,
        ),
      if (p.estado == 'entregado')
        _misResenas.containsKey(p.id)
            ? Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: grisBorde)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CALIFICADO', style: _rotulo(size: 9.5)),
                    const SizedBox(width: 6),
                    Estrellas(
                      valor: _misResenas[p.id]!.calificacionRestaurante.toDouble(),
                      tamano: 13,
                    ),
                  ],
                ),
              )
            : _boton(
                'Calificar',
                () => _calificar(p),
                icono: Icons.star_border,
                relleno: true,
                color: turquesa,
              ),
      if (puedeCancelar)
        _boton('Cancelar', () => _cancelar(p), color: grisTexto),
      if (puedeCancelar && p.pagoPendiente)
        _boton(
          p.estadoPago == 'rechazado' ? 'Reintentar pago' : 'Pagar ahora',
          () => _pagar(p),
          relleno: true,
        ),
    ];
  }

  // Colores por método de pago: azul = Mercado Pago, verde = efectivo.
  static const Color colorMp = Color(0xFF1B7FC4);
  static const Color colorEfectivo = Color(0xFF2E9E5B);
  static const Color colorPendiente = Color(0xFFB7791F);

  /// Icono y nombre del método (con su color) y, debajo, el estado del pago.
  Widget _pago(Pedido p) {
    final mp = p.metodoPago == 'mercado_pago';
    final Color colorMetodo = mp ? colorMp : colorEfectivo;
    final pagado = p.estadoPago == 'pagado';

    final String texto;
    final Color colorEstado;
    switch (p.estadoPago) {
      case 'pagado':
        texto = 'Pagado';
        colorEstado = grisTexto;
        break;
      case 'rechazado':
        texto = 'Pago rechazado';
        colorEstado = AppColors.error;
        break;
      case 'contra_entrega':
        texto = 'Pagas al recibir';
        colorEstado = grisTexto;
        break;
      default:
        texto = 'Por pagar';
        colorEstado = colorPendiente;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          mp ? Icons.credit_card : Icons.payments_outlined,
          size: 20,
          color: colorMetodo,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mp ? 'Mercado Pago' : 'Efectivo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(
                  weight: FontWeight.w600,
                  size: 13,
                  color: colorMetodo,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pagado) ...[
                    Icon(Icons.check, size: 13, color: colorMetodo),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        weight: FontWeight.w500,
                        size: 12,
                        color: pagado ? colorMetodo : colorEstado,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================
  // TARJETA
  // =====================================================

  Widget _tarjeta(Pedido p) {
    final cancelado = p.estado == 'cancelado';
    final resumen = _resumenItems(p);
    final fecha = _fecha(p);

    final nombre = Row(
      children: [
        Flexible(
          child: Text(
            p.restaurante,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(weight: FontWeight.w700, size: 15),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '#${p.id}${fecha == null ? '' : ' · $fecha'}',
          style: AppTypography.body(
            color: grisTexto,
            weight: FontWeight.w500,
            size: 12,
          ),
        ),
      ],
    );

    final items = Text(
      resumen.isEmpty ? 'Sin detalle de productos' : resumen,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body(
        color: grisTexto,
        weight: FontWeight.w400,
        size: 12.5,
      ),
    );

    final total = Text(
      dinero(p.total),
      style: AppTypography.title(size: 18).copyWith(
        color: cancelado ? grisTexto : verdeOscuro,
        decoration: cancelado ? TextDecoration.lineThrough : null,
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final enFila = c.maxWidth >= _anchoFila;
        final acciones = _acciones(p);

        final Widget contenido;
        if (enFila) {
          contenido = Row(
            children: [
              _icono(p),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [nombre, const SizedBox(height: 2), items],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(flex: 3, child: _progreso(p)),
              const SizedBox(width: 24),
              SizedBox(width: 150, child: _pago(p)),
              SizedBox(
                width: 90,
                child: Align(alignment: Alignment.centerRight, child: total),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 200,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: acciones,
                  ),
                ),
              ),
            ],
          );
        } else {
          contenido = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _icono(p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [nombre, const SizedBox(height: 2), items],
                    ),
                  ),
                  const SizedBox(width: 10),
                  total,
                ],
              ),
              const SizedBox(height: 10),
              _progreso(p),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _pago(p),
                    ),
                  ),
                  if (acciones.isNotEmpty)
                    Flexible(
                      flex: 2,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: acciones,
                      ),
                    ),
                ],
              ),
            ],
          );
        }

        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => _rastrear(p),
            hoverColor: menta,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: grisBorde),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: enFila ? 11 : 12,
              ),
              child: contenido,
            ),
          ),
        );
      },
    );
  }

  Widget _tituloGrupo(String texto, int cuantos) {
    return Row(
      children: [
        Text(texto, style: _rotulo(color: verdeOscuro, size: 10.5)),
        const SizedBox(width: 8),
        Text(
          '$cuantos',
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

  /// Primero lo que está en curso y luego el historial.
  List<Widget> _listaAgrupada() {
    final visibles = _visibles;
    if (visibles.isEmpty) return [_vacio()];

    final enCurso = visibles.where(_enCurso).toList();
    final historial = visibles.where((p) => !_enCurso(p)).toList();

    final salida = <Widget>[];
    void grupo(String titulo, List<Pedido> lista) {
      if (lista.isEmpty) return;
      if (salida.isNotEmpty) salida.add(const SizedBox(height: 14));
      salida.add(_tituloGrupo(titulo, lista.length));
      salida.add(const SizedBox(height: 8));
      for (var i = 0; i < lista.length; i++) {
        if (i > 0) salida.add(const SizedBox(height: 6));
        salida.add(_tarjeta(lista[i]));
      }
    }

    grupo('EN CURSO', enCurso);
    grupo('HISTORIAL', historial);
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

  Widget _panel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EN CURSO', style: _rotulo()),
          const SizedBox(height: 4),
          Text('$_nEnCurso', style: AppTypography.title(size: 40)),
          const SizedBox(height: 10),
          _fila('Pedidos en total', '${pedidos.length}'),
          _fila('Entregados', '$_nEntregados'),
          _fila('Gastado', dinero(_gastado)),
          const SizedBox(height: 12),
          Container(height: 1, color: grisBorde),
          const SizedBox(height: 14),
          Text('MOSTRAR', style: _rotulo()),
          const SizedBox(height: 10),
          _filtros(),
        ],
      ),
    );
  }

  // =====================================================
  // ESTADOS: VACÍO, ERROR, CARGANDO
  // =====================================================

  Widget _vacio() {
    final filtrando = filtro != _Filtro.todos && pedidos.isNotEmpty;
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
                  filtrando ? Icons.filter_alt_outlined : Icons.receipt_long_outlined,
                  size: 40,
                  color: turquesa,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                filtrando ? 'SIN RESULTADOS' : 'AÚN NO HAY PEDIDOS',
                style: _rotulo(),
              ),
              const SizedBox(height: 6),
              Text(
                filtrando
                    ? 'Nada en esta categoría'
                    : 'Todavía no has hecho pedidos',
                textAlign: TextAlign.center,
                style: AppTypography.title(size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                filtrando
                    ? 'Prueba con otro filtro para ver tus demás pedidos.'
                    : 'Elige un restaurante, arma tu carrito y aquí podrás '
                        'seguir tu pedido paso a paso.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: filtrando
                    ? () => setState(() => filtro = _Filtro.todos)
                    : () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    filtrando ? 'VER TODOS LOS PEDIDOS' : 'VER RESTAURANTES',
                    style: _rotulo(color: turquesa, size: 10.5),
                  ),
                ),
              ),
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
                  color: rojoClaro,
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
                error ?? 'No se pudieron cargar tus pedidos.',
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
          if (!conPanel && pedidos.isNotEmpty) ...[
            const SizedBox(height: 14),
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
