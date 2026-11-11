import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../resenas/estrellas.dart';

// ---------------------------------------------------------------- estilo
// Mismo lenguaje que el panel del repartidor: esquinas rectas, líneas
// finas y rótulos pequeños en mayúsculas.

const _tinta = AppColors.primaryDark;
const _linea = Color(0xFFD3E2DF);
const _naranja = Color(0xFFE07B00);
const _barraSuave = Color(0xFFBFE3DE);

TextStyle _rotulo({Color color = AppColors.hint, double size = 10}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: color,
    );

TextStyle _cifra({double size = 24, Color color = _tinta}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.1,
    );

// ---------------------------------------------------------------- modelos

double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

class _Cifras {
  final int entregas;
  final double ganancias;
  final double km;
  final double efectivo;
  final double mercadoPago;

  const _Cifras({
    this.entregas = 0,
    this.ganancias = 0,
    this.km = 0,
    this.efectivo = 0,
    this.mercadoPago = 0,
  });

  factory _Cifras.fromJson(Map<String, dynamic> j) => _Cifras(
        entregas: (j['entregas'] as num?)?.toInt() ?? 0,
        ganancias: _num(j['ganancias']),
        km: _num(j['km']),
        efectivo: _num(j['efectivo']),
        mercadoPago: _num(j['mercado_pago']),
      );
}

class _Dia {
  final DateTime fecha;
  final int entregas;
  final double ganancias;

  const _Dia(this.fecha, this.entregas, this.ganancias);

  factory _Dia.fromJson(Map<String, dynamic> j) => _Dia(
        DateTime.parse(j['fecha'] as String),
        (j['entregas'] as num?)?.toInt() ?? 0,
        _num(j['ganancias']),
      );
}

class _Entrega {
  final int id;
  final String restaurante;
  final String direccion;
  final DateTime fecha;
  final double envio;
  final double total;
  final String metodo;
  final double km;

  const _Entrega({
    required this.id,
    required this.restaurante,
    required this.direccion,
    required this.fecha,
    required this.envio,
    required this.total,
    required this.metodo,
    required this.km,
  });

  bool get esEfectivo => metodo == 'efectivo';

  factory _Entrega.fromJson(Map<String, dynamic> j) => _Entrega(
        id: (j['id'] as num).toInt(),
        restaurante: (j['restaurante'] ?? '') as String,
        direccion: (j['direccion_entrega'] ?? '') as String,
        fecha: DateTime.parse(j['fecha'] as String),
        envio: _num(j['costo_envio']),
        total: _num(j['total']),
        metodo: (j['metodo_pago'] ?? '') as String,
        km: _num(j['km']),
      );
}

class _Resumen {
  final bool enEntrega;
  final double? calificacion; // promedio de las reseñas que recibió
  final int totalResenas;
  final _Cifras hoy;
  final _Cifras semana;
  final _Cifras mes;
  final List<_Dia> dias;
  final List<_Entrega> historial;

  const _Resumen({
    required this.enEntrega,
    this.calificacion,
    this.totalResenas = 0,
    required this.hoy,
    required this.semana,
    required this.mes,
    required this.dias,
    required this.historial,
  });

  factory _Resumen.fromJson(Map<String, dynamic> j) => _Resumen(
        enEntrega: j['en_entrega'] == true,
        calificacion:
            ((j['calificacion'] as Map<String, dynamic>?)?['promedio'] as num?)
                ?.toDouble(),
        totalResenas:
            ((j['calificacion'] as Map<String, dynamic>?)?['total'] as num?)
                    ?.toInt() ??
                0,
        hoy: _Cifras.fromJson(j['hoy'] as Map<String, dynamic>),
        semana: _Cifras.fromJson(j['semana'] as Map<String, dynamic>),
        mes: _Cifras.fromJson(j['mes'] as Map<String, dynamic>),
        dias: (j['dias'] as List<dynamic>)
            .map((d) => _Dia.fromJson(d as Map<String, dynamic>))
            .toList(),
        historial: (j['historial'] as List<dynamic>)
            .map((e) => _Entrega.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

Future<_Resumen> _pedirResumen(String token) async {
  final datos = await ApiClient.get(
    '/pedidos/repartidor/resumen',
    token: token,
    query: {'zona_min': DateTime.now().timeZoneOffset.inMinutes.toString()},
  );
  return _Resumen.fromJson(datos as Map<String, dynamic>);
}

// ---------------------------------------------------------------- pantalla

/// Perfil del repartidor. Pantalla dividida a la mitad:
///  - izquierda: quién es, ganancias del periodo y gráfica de 7 días;
///  - derecha: historial de entregas, una línea por entrega.
class PerfilRepartidorScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const PerfilRepartidorScreen({super.key, required this.usuario});

  @override
  State<PerfilRepartidorScreen> createState() => _PerfilRepartidorScreenState();
}

class _PerfilRepartidorScreenState extends State<PerfilRepartidorScreen> {
  _Resumen? _datos;
  String? _error;
  bool _cargando = true;
  Timer? _temporizador;

  /// 0 = hoy, 1 = esta semana, 2 = este mes.
  int _periodo = 0;

  /// En pantallas angostas: 0 = resumen, 1 = historial.
  int _vista = 0;

  static const _nombresPeriodo = ['HOY', 'SEMANA', 'MES'];
  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  static const _letrasDia = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final datos = await _pedirResumen(widget.usuario.token);
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        // Si ya hay datos, un fallo en el refresco silencioso no los borra.
        if (_datos == null) _error = e.toString();
      });
    }
  }

  // ------------------------------------------------------------- cálculos

  _Cifras get _cifrasActuales {
    final d = _datos;
    if (d == null) return const _Cifras();
    return [d.hoy, d.semana, d.mes][_periodo];
  }

  DateTime get _hoy {
    final d = _datos;
    if (d == null || d.dias.isEmpty) return DateTime.now();
    return d.dias.last.fecha;
  }

  List<_Entrega> get _entregasDelPeriodo {
    final d = _datos;
    if (d == null) return const [];
    final hoy = DateTime(_hoy.year, _hoy.month, _hoy.day);
    DateTime desde;
    if (_periodo == 0) {
      desde = hoy;
    } else if (_periodo == 1) {
      desde = hoy.subtract(Duration(days: hoy.weekday - 1));
    } else {
      desde = DateTime(hoy.year, hoy.month, 1);
    }
    return d.historial.where((e) {
      final dia = DateTime(e.fecha.year, e.fecha.month, e.fecha.day);
      return !dia.isBefore(desde);
    }).toList();
  }

  String _fechaCorta(DateTime f) {
    final hoy = DateTime(_hoy.year, _hoy.month, _hoy.day);
    final dia = DateTime(f.year, f.month, f.day);
    final hora =
        '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
    if (dia == hoy) return 'Hoy $hora';
    if (dia == hoy.subtract(const Duration(days: 1))) return 'Ayer $hora';
    return '${f.day} ${_meses[f.month - 1]} $hora';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _barra(),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _barra() {
    final angosta = MediaQuery.of(context).size.width < 600;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _linea)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver al panel',
                    icon: const Icon(Icons.arrow_back, color: _tinta),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Image.asset(
                    'assets/images/logo-food-express.png',
                    width: angosta ? 110 : 150,
                    height: 46,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    color: _tinta,
                    child: Text(
                      'MI PERFIL',
                      style: _rotulo(color: Colors.white, size: 10),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: const Icon(Icons.refresh, color: _tinta),
                    onPressed: _cargar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_datos == null) {
      if (_cargando) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 40, color: AppColors.hint),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No se pudo cargar tu perfil.',
                textAlign: TextAlign.center,
                style: AppTypography.body(color: AppColors.hint),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  side: const BorderSide(color: _tinta),
                  foregroundColor: _tinta,
                ),
                onPressed: _cargar,
                child: Text('REINTENTAR', style: _rotulo(color: _tinta)),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 900) return _ancho();
        return _angosto();
      },
    );
  }

  // ------------------------------------------------------------ disposición

  /// Mitad y mitad: perfil a la izquierda, historial a la derecha.
  Widget _ancho() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: _linea)),
            ),
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: _resumen(),
          ),
        ),
        Expanded(child: _historial(compacta: false)),
      ],
    );
  }

  Widget _angosto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              _pestana('RESUMEN', 0),
              _pestana('HISTORIAL', 1),
            ],
          ),
        ),
        const Divider(height: 1, color: _linea),
        Expanded(
          child: _vista == 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: _resumen(),
                )
              : _historial(compacta: true),
        ),
      ],
    );
  }

  Widget _pestana(String texto, int valor) {
    final activa = _vista == valor;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _vista = valor),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activa ? _tinta : Colors.white,
            border: Border.all(color: _tinta),
          ),
          child: Text(
            texto,
            style: _rotulo(color: activa ? Colors.white : _tinta),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- resumen

  Widget _resumen() {
    final c = _cifrasActuales;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _identidad(),
        const SizedBox(height: 22),
        _selector(),
        const SizedBox(height: 22),
        Text(
          'GANANCIAS · ${_nombresPeriodo[_periodo]}',
          style: _rotulo(size: 10.5),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(dinero(c.ganancias), style: _cifra(size: 48)),
        ),
        const SizedBox(height: 20),
        _datosSecundarios(c),
        const SizedBox(height: 24),
        Expanded(child: _grafica()),
      ],
    );
  }

  Widget _identidad() {
    final nombre = widget.usuario.nombre;
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
    final ocupado = _datos?.enEntrega ?? false;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _tinta, width: 1.5),
          ),
          child: Text(inicial, style: _cifra(size: 19)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(weight: FontWeight.w700, size: 16),
              ),
              Text(
                widget.usuario.correo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(color: AppColors.hint, size: 12),
              ),
              const SizedBox(height: 2),
              ResumenCalificacion(
                promedio: _datos?.calificacion,
                total: _datos?.totalResenas ?? 0,
                tamano: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 8,
          height: 8,
          color: ocupado ? _naranja : AppColors.mint,
        ),
        const SizedBox(width: 7),
        Text(
          ocupado ? 'EN ENTREGA' : 'DISPONIBLE',
          style: _rotulo(color: _tinta, size: 9.5),
        ),
      ],
    );
  }

  /// Selector de texto con raya inferior (sin cajas).
  Widget _selector() {
    return Row(
      children: [
        for (var i = 0; i < _nombresPeriodo.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 26),
            child: InkWell(
              onTap: () => setState(() => _periodo = i),
              child: Container(
                padding: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _periodo == i ? _tinta : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  _nombresPeriodo[i],
                  style: _rotulo(
                    color: _periodo == i ? _tinta : AppColors.hint,
                    size: 11,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Entregas, kilómetros, efectivo y Mercado Pago en una sola fila, separados por líneas.
  Widget _datosSecundarios(_Cifras c) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: _linea)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _dato('ENTREGAS', '${c.entregas}')),
            const VerticalDivider(width: 1, color: _linea),
            Expanded(child: _dato('KILÓMETROS', c.km.toStringAsFixed(1))),
            const VerticalDivider(width: 1, color: _linea),
            Expanded(child: _dato('EFECTIVO', dinero(c.efectivo))),
            const VerticalDivider(width: 1, color: _linea),
            Expanded(child: _dato('MERCADO PAGO', dinero(c.mercadoPago))),
          ],
        ),
      ),
    );
  }

  Widget _dato(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(rotulo, style: _rotulo(size: 9.5)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: _cifra(size: 22)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- gráfica

  /// Ganancias de los últimos 7 días. Hoy va en verde; el resto en tono suave.
  Widget _grafica() {
    final dias = _datos?.dias ?? const <_Dia>[];
    final maximo =
        dias.fold<double>(0, (m, d) => d.ganancias > m ? d.ganancias : m);
    final total = dias.fold<double>(0, (s, d) => s + d.ganancias);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('ÚLTIMOS 7 DÍAS', style: _rotulo(size: 10.5)),
            ),
            Text(dinero(total), style: _rotulo(color: _tinta, size: 11)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              if (c.maxHeight < 90 || dias.isEmpty) {
                return const SizedBox.shrink();
              }
              const pie = 40.0; // letra + número del día
              const cima = 20.0; // cifra sobre la barra
              final alturaMax = c.maxHeight - pie - cima;
              return Stack(
                children: [
                  // Guías: línea base, mitad y máximo.
                  for (final f in const [0.0, 0.5, 1.0])
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: pie + alturaMax * f,
                      child: Container(
                        height: 1,
                        color: f == 0.0 ? _tinta : _linea,
                      ),
                    ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < dias.length; i++)
                          Expanded(
                            child: _columna(
                              dias[i],
                              esHoy: i == dias.length - 1,
                              maximo: maximo,
                              alturaMax: alturaMax,
                              pie: pie,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _columna(
    _Dia dia, {
    required bool esHoy,
    required double maximo,
    required double alturaMax,
    required double pie,
  }) {
    final proporcion = maximo <= 0 ? 0.0 : dia.ganancias / maximo;
    final alto = dia.ganancias <= 0 ? 0.0 : 3 + (alturaMax - 3) * proporcion;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (dia.ganancias > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '\$${dia.ganancias.toStringAsFixed(0)}',
              style: _rotulo(color: _tinta, size: 10),
            ),
          ),
        Container(
          height: alto,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          color: esHoy ? AppColors.primary : _barraSuave,
        ),
        SizedBox(
          height: pie,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _letrasDia[dia.fecha.weekday - 1],
                style: _rotulo(
                  color: esHoy ? _tinta : AppColors.hint,
                  size: 11,
                ),
              ),
              Text(
                '${dia.fecha.day}',
                style: AppTypography.body(color: AppColors.hint, size: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- historial

  Widget _historial({required bool compacta}) {
    final entregas = _entregasDelPeriodo;
    final margen = compacta ? 20.0 : 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(margen, 28, margen, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compacta) ...[
                _selector(),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'HISTORIAL · ${_nombresPeriodo[_periodo]}',
                      style: _rotulo(color: _tinta, size: 11),
                    ),
                  ),
                  Text(
                    '${entregas.length} ${entregas.length == 1 ? 'ENTREGA' : 'ENTREGAS'}',
                    style: _rotulo(size: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!compacta) _encabezadoTabla(margen),
        const Divider(height: 1, color: _linea),
        Expanded(
          child: entregas.isEmpty
              ? _vacio()
              : ListView.separated(
                  itemCount: entregas.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: _linea),
                  itemBuilder: (_, i) => _fila(entregas[i], compacta, margen),
                ),
        ),
      ],
    );
  }

  Widget _encabezadoTabla(double margen) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margen, 0, margen, 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('PEDIDO', style: _rotulo(size: 9))),
          Expanded(flex: 3, child: Text('FECHA', style: _rotulo(size: 9))),
          Expanded(flex: 3, child: Text('PAGO', style: _rotulo(size: 9))),
          SizedBox(
            width: 52,
            child: Text('KM', textAlign: TextAlign.right, style: _rotulo(size: 9)),
          ),
          SizedBox(
            width: 72,
            child: Text('ENVÍO', textAlign: TextAlign.right, style: _rotulo(size: 9)),
          ),
        ],
      ),
    );
  }

  Widget _vacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.two_wheeler, size: 36, color: _barraSuave),
            const SizedBox(height: 10),
            Text('SIN ENTREGAS EN ESTE PERIODO', style: _rotulo(color: _tinta)),
            const SizedBox(height: 4),
            Text(
              'Cuando entregues un pedido, aparece aquí.',
              textAlign: TextAlign.center,
              style: AppTypography.body(color: AppColors.hint, size: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// Una línea por entrega.
  Widget _fila(_Entrega e, bool compacta, double margen) {
    final pago = e.esEfectivo ? 'Efectivo' : 'Mercado Pago';
    final icono = e.esEfectivo ? Icons.payments_outlined : Icons.credit_card;
    final estiloGris = AppTypography.body(color: AppColors.hint, size: 12);

    final envio = SizedBox(
      width: 72,
      child: Text(
        '+${dinero(e.envio)}',
        textAlign: TextAlign.right,
        style: _cifra(size: 14),
      ),
    );

    if (compacta) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: margen, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.restaurante,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(weight: FontWeight.w700, size: 14),
                  ),
                  Text('#${e.id} · ${_fechaCorta(e.fecha)} · $pago', style: estiloGris),
                ],
              ),
            ),
            envio,
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Text('#${e.id}', style: estiloGris),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.restaurante,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(weight: FontWeight.w700, size: 14),
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(_fechaCorta(e.fecha), style: estiloGris)),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icono, size: 14, color: AppColors.hint),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    pago,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estiloGris,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              e.km.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: estiloGris,
            ),
          ),
          envio,
        ],
      ),
    );
  }
}
