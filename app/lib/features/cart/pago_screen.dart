import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import 'mis_pedidos_screen.dart';

/// Pago de un pedido con Mercado Pago (historia #10).
///
/// Abre el enlace de pago en una ventana nueva. Mientras el cliente paga, esta
/// pantalla revisa el pago cada pocos segundos; en cuanto el backend lo
/// confirma (la app nunca decide si se pagó), avanza sola a "Mis pedidos". La
/// ventana de pago se cierra sola al terminar.
///
/// Mismo diseño que el resto de la app: esquinas rectas, líneas finas, Poppins
/// y rótulos pequeños en mayúsculas.
class PagoScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final Pedido pedido;

  /// true: abre el enlace de pago apenas se muestra la pantalla.
  final bool abrirAlInicio;

  const PagoScreen({
    super.key,
    required this.usuario,
    required this.pedido,
    this.abrirAlInicio = false,
  });

  @override
  State<PagoScreen> createState() => _PagoScreenState();
}

class _PagoScreenState extends State<PagoScreen> with WidgetsBindingObserver {
  // Colores y medidas (los mismos del resto de la app).
  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color menta = Color(0xFFE5F5F3);
  static const Color colorMp = Color(0xFF1B7FC4);

  bool abriendo = false;
  bool verificando = false;
  bool esDemo = false;
  bool yaSeAbrio = false;
  bool confirmado = false;
  String? aviso;
  String? info;
  Timer? _revisor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.abrirAlInicio) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirPago());
    }
  }

  @override
  void dispose() {
    _revisor?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver a la pestaña, se confirma el pago sin que el usuario haga nada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && yaSeAbrio) {
      _verificar(silencioso: true);
    }
  }

  /// Mientras la ventana de pago está abierta, se revisa el pago cada 3 s.
  void _empezarARevisar() {
    _revisor?.cancel();
    _revisor = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _verificar(silencioso: true),
    );
  }

  void _dejarDeRevisar() {
    _revisor?.cancel();
    _revisor = null;
  }

  Future<void> _abrirPago() async {
    if (abriendo) return;
    setState(() {
      abriendo = true;
      aviso = null;
      info = null;
    });
    try {
      final preferencia = await PedidoService.crearPreferenciaPago(
        widget.usuario.token,
        widget.pedido.id,
      );
      final abierto = await launchUrl(
        Uri.parse(preferencia.initPoint),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        esDemo = preferencia.esDemo;
        yaSeAbrio = abierto;
        if (!abierto) {
          aviso = 'No se pudo abrir la página de pago. '
              'Revisa que el navegador no haya bloqueado la ventana.';
        }
      });
      if (abierto) _empezarARevisar();
    } on ApiException catch (e) {
      if (mounted) setState(() => aviso = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => aviso = 'No se pudo abrir la página de pago.');
    } finally {
      if (mounted) setState(() => abriendo = false);
    }
  }

  Future<void> _verificar({bool silencioso = false}) async {
    if (verificando || confirmado) return;
    if (!silencioso) setState(() => verificando = true);
    verificando = true;
    try {
      final estado = await PedidoService.verificarPago(
        widget.usuario.token,
        widget.pedido.id,
      );
      if (!mounted) return;

      if (estado == 'pagado') {
        _dejarDeRevisar();
        setState(() {
          confirmado = true;
          aviso = null;
          info = null;
        });
        // Un instante para que se vea la confirmación y luego "Mis pedidos".
        await Future.delayed(const Duration(milliseconds: 1400));
        if (!mounted) return;
        irAMisPedidos(
          context,
          widget.usuario,
          mensaje:
              '¡Pago recibido! Tu pedido #${widget.pedido.id} ya está buscando repartidor.',
        );
        return;
      }
      if (estado == 'rechazado') {
        _dejarDeRevisar();
        setState(() {
          yaSeAbrio = false;
          info = null;
          aviso = 'El pago fue rechazado. No se hizo ningún cargo; '
              'puedes intentarlo de nuevo.';
        });
        return;
      }
      if (!silencioso) {
        setState(() {
          aviso = null;
          info = 'Aún no vemos tu pago. Si ya pagaste, espera unos segundos.';
        });
      }
    } on ApiException catch (e) {
      if (mounted && !silencioso) setState(() => aviso = e.mensaje);
    } catch (_) {
      if (mounted && !silencioso) {
        setState(() => aviso = 'No se pudo confirmar el pago.');
      }
    } finally {
      verificando = false;
      if (mounted) setState(() {});
    }
  }

  void _pagarDespues() {
    _dejarDeRevisar();
    irAMisPedidos(
      context,
      widget.usuario,
      mensaje:
          'Tu pedido #${widget.pedido.id} queda pendiente de pago. Puedes pagarlo cuando quieras.',
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

  Widget _barraSuperior() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
            child: Text('Pagar', style: AppTypography.title(size: 20)),
          ),
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

  Widget _nodo({required bool hecho, required bool actual}) {
    if (hecho) {
      return Container(
        width: 20,
        height: 20,
        color: turquesa,
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    if (actual) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: turquesa, width: 2),
        ),
        child: Center(child: Container(width: 8, height: 8, color: turquesa)),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde, width: 1.5),
      ),
    );
  }

  /// Los tres pasos del pago en una sola fila, con una línea continua entre
  /// ellos (ocupa poco alto para que todo quepa sin hacer scroll).
  Widget _pasos() {
    final titulos = [
      ('Abre Mercado Pago', 'Se abre en una ventana nueva'),
      ('Completa tu pago', 'Hazlo con calma allí'),
      ('Regresas aquí solo', 'Se cierra sola y confirmamos'),
    ];
    // 0 = por abrir, 1 = pagando, 3 = confirmado
    final actual = confirmado ? 3 : (yaSeAbrio ? 1 : 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < titulos.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= actual ? turquesa : grisBorde),
                      ),
                    ),
                    _nodo(hecho: i < actual, actual: i == actual),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == titulos.length - 1
                            ? Colors.transparent
                            : (i < actual ? turquesa : grisBorde),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  titulos[i].$1,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    weight: i == actual ? FontWeight.w700 : FontWeight.w600,
                    size: 13,
                    color: i > actual ? grisTexto : verdeOscuro,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titulos[i].$2,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    color: grisTexto,
                    weight: FontWeight.w400,
                    size: 11.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Línea de estado: esperando, confirmado, aviso o información.
  Widget _estado() {
    if (confirmado) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: menta,
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: turquesa, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PAGO RECIBIDO', style: _rotulo(color: turquesa, size: 9.5)),
                  Text(
                    '¡Listo! Te llevamos a tus pedidos…',
                    style: AppTypography.body(
                      weight: FontWeight.w700,
                      size: 14,
                      color: verdeOscuro,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (aviso != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFFF8E3E6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                aviso!,
                style: AppTypography.body(
                  weight: FontWeight.w600,
                  size: 13,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (yaSeAbrio) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: grisBorde),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: turquesa),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ESPERANDO', style: _rotulo(size: 9.5)),
                  Text(
                    info ?? 'Esperando la confirmación de tu pago…',
                    style: AppTypography.body(
                      weight: FontWeight.w600,
                      size: 13.5,
                      color: verdeOscuro,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      'Al tocar «Pagar con Mercado Pago» se abre una ventana segura. '
      'Cuando termines, esta pantalla lo detecta sola.',
      style: AppTypography.body(
        color: grisTexto,
        weight: FontWeight.w400,
        size: 13,
      ),
    );
  }

  Widget _botonPrincipal(String texto, VoidCallback? onTap, {bool cargando = false}) {
    return Material(
      color: onTap == null ? const Color(0xFFBFD9D5) : verdeOscuro,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: cargando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    texto.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _rotulo(color: Colors.white, size: 10.5),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _botonSecundario(String texto, VoidCallback? onTap, {Color color = verdeOscuro}) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        hoverColor: menta,
        child: Container(
          height: 48,
          decoration: BoxDecoration(border: Border.all(color: grisBorde)),
          child: Center(
            child: Text(
              texto.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _rotulo(
                color: onTap == null ? grisBorde : color,
                size: 10.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Los botones van en una sola fila (en celular, uno debajo de otro).
  Widget _botones(bool angosto) {
    final List<Widget> hijos;
    final List<int> pesos;

    if (!yaSeAbrio) {
      hijos = [
        _botonPrincipal(
          'Pagar con Mercado Pago',
          abriendo ? null : _abrirPago,
          cargando: abriendo,
        ),
        _botonSecundario('Pagar después', _pagarDespues, color: turquesa),
      ];
      pesos = [2, 1];
    } else {
      hijos = [
        _botonPrincipal(
          'Ya pagué',
          verificando ? null : () => _verificar(),
          cargando: verificando,
        ),
        _botonSecundario('Reabrir pago', abriendo ? null : _abrirPago),
        _botonSecundario('Pagar después', _pagarDespues, color: turquesa),
      ];
      pesos = [1, 1, 1];
    }

    if (angosto) {
      return Column(
        children: [
          for (var i = 0; i < hijos.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: hijos[i]),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < hijos.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(flex: pesos[i], child: hijos[i]),
        ],
      ],
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;

    return Scaffold(
      backgroundColor: fondo,
      body: Column(
        children: [
          _barraSuperior(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final angosto = c.maxWidth < 540;
                return Center(
                  // Todo cabe en pantalla; solo si la ventana es muy baja, el
                  // contenido se desplaza como respaldo.
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(angosto ? 14 : 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Container(
                        padding: EdgeInsets.all(angosto ? 18 : 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: grisBorde),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  color: colorMp,
                                  child: const Icon(
                                    Icons.credit_card,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'PAGO CON MERCADO PAGO',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _rotulo(color: colorMp, size: 10),
                                  ),
                                ),
                                const Spacer(),
                                if (esDemo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    color: menta,
                                    child: Text(
                                      'MODO DEMO · SIN COBRO',
                                      style: _rotulo(
                                        color: verdeOscuro,
                                        size: 8.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'PEDIDO #${pedido.id}',
                                        style: _rotulo(),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        pedido.restaurante,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.title(size: 20),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('TOTAL', style: _rotulo()),
                                    Text(
                                      dinero(pedido.total),
                                      style: AppTypography.title(size: 30),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(height: 1, color: grisBorde),
                            const SizedBox(height: 16),
                            _pasos(),
                            const SizedBox(height: 18),
                            _estado(),
                            const SizedBox(height: 18),
                            if (!confirmado) _botones(angosto),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
