import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/imagenes.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../delivery/pedido_model.dart';
import '../delivery/pedido_service.dart';
import 'carrito_service.dart';
import 'checkout_screen.dart';

/// Pantalla 1 del wireframe del Sprint 3: "Mi carrito".
///
/// Mismo diseño que el menú: esquinas rectas, líneas finas, Poppins y rótulos
/// pequeños en mayúsculas. En pantalla ancha, los productos van a la izquierda
/// y el resumen con el botón de confirmar a la derecha; en celular, el resumen
/// va debajo y el total con el botón quedan fijos abajo.
class CarritoScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;

  const CarritoScreen({super.key, required this.usuario});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  // Colores y medidas (los mismos del menú).
  static const Color verdeOscuro = AppColors.primaryDark;
  static const Color turquesa = AppColors.primary;
  static const Color grisTexto = AppColors.hint;
  static const Color grisBorde = Color(0xFFD3E2DF);
  static const Color fondo = Color(0xFFF2FAF9);
  static const Color menta = Color(0xFFE5F5F3);
  static const Color gris = Color(0xFF7FA9A9);

  static const double _anchoMaximo = 1080;
  static const double _anchoConColumnas = 940;
  static const double _anchoResumen = 380;

  final CarritoService carrito = CarritoService.instance;

  Position? posicion;
  Cotizacion? cotizacion;
  bool cargandoEnvio = true;
  String? errorEnvio;

  @override
  void initState() {
    super.initState();
    _calcularEnvio();
  }

  /// El envío depende de la distancia restaurante -> ubicación del cliente.
  Future<void> _calcularEnvio() async {
    final restaurante = carrito.restaurante;
    if (carrito.vacio || restaurante == null) return;

    setState(() {
      cargandoEnvio = true;
      errorEnvio = null;
    });

    try {
      final pos = await LocationService.obtenerUbicacionActual();
      if (pos == null) {
        throw ApiException(
          'No pudimos obtener tu ubicación. Activa el GPS y da permiso a la app.',
        );
      }
      final resultado = await PedidoService.cotizar(
        widget.usuario.token,
        restauranteId: restaurante.id,
        items: carrito.itemsParaApi,
        latitud: pos.latitude,
        longitud: pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        posicion = pos;
        cotizacion = resultado;
        cargandoEnvio = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        errorEnvio = e.mensaje;
        cargandoEnvio = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorEnvio = 'No pudimos calcular el envío. Intenta de nuevo.';
        cargandoEnvio = false;
      });
    }
  }

  void _confirmar() {
    final pos = posicion;
    final cot = cotizacion;
    if (pos == null || cot == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          usuario: widget.usuario,
          latitud: pos.latitude,
          longitud: pos.longitude,
          costoEnvio: cot.costoEnvio,
        ),
      ),
    );
  }

  Future<void> _vaciar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        title: Text('¿Vaciar el carrito?', style: AppTypography.title(size: 20)),
        content: Text(
          'Se quitarán todos los productos de tu pedido.',
          style: AppTypography.body(color: grisTexto, size: 14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              foregroundColor: verdeOscuro,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              'Cancelar',
              style: AppTypography.body(weight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: verdeOscuro,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              'Vaciar',
              style: AppTypography.body(
                color: Colors.white,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (seguro == true) carrito.vaciar();
  }

  // =====================================================
  // TEXTOS Y PIEZAS SUELTAS
  // =====================================================

  TextStyle _rotulo({Color color = grisTexto, double size = 10}) {
    return AppTypography.body(
      color: color,
      weight: FontWeight.w700,
      size: size,
    ).copyWith(letterSpacing: 1.5);
  }

  Widget _botonCuadrado({
    required IconData icono,
    required VoidCallback onTap,
    required String tooltip,
    double lado = 38,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: lado,
            height: lado,
            child: Icon(icono, color: verdeOscuro, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _botonSolido({
    required String texto,
    required VoidCallback? onTap,
    IconData? icono,
    bool cargando = false,
    bool contorno = false,
  }) {
    final apagado = onTap == null && !cargando;
    final colorTexto = contorno ? verdeOscuro : Colors.white;

    return Material(
      color: contorno
          ? Colors.white
          : (apagado ? gris : verdeOscuro),
      child: InkWell(
        onTap: cargando ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: contorno
              ? BoxDecoration(border: Border.all(color: verdeOscuro, width: 1.5))
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (cargando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              else ...[
                Text(
                  texto.toUpperCase(),
                  style: AppTypography.body(
                    color: colorTexto,
                    weight: FontWeight.w700,
                    size: 13,
                  ).copyWith(letterSpacing: 1.3),
                ),
                if (icono != null) ...[
                  const SizedBox(width: 10),
                  Icon(icono, color: colorTexto, size: 19),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _nota(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 17, color: turquesa),
          const SizedBox(width: 9),
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
            child: Text('Mi carrito', style: AppTypography.title(size: 20)),
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

  // =====================================================
  // PRODUCTOS DEL CARRITO
  // =====================================================

  Widget _encabezado({required bool compacto, required bool corto}) {
    final r = carrito.restaurante;
    final piezas = carrito.totalPiezas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TU PEDIDO EN', style: _rotulo(size: 10)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                r?.nombre ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title(size: compacto ? 22 : 30),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: menta,
              child: Text(
                piezas == 1 ? '1 pieza' : '$piezas piezas',
                style: AppTypography.body(weight: FontWeight.w600, size: 12.5),
              ),
            ),
          ],
        ),
        if (!compacto && !corto) ...[
          const SizedBox(height: 6),
          Text(
            'Revisa lo que llevas. Cambia cantidades o quita lo que no '
            'quieras antes de confirmar.',
            style: AppTypography.body(
              color: grisTexto,
              weight: FontWeight.w400,
              size: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepper(LineaCarrito l, {double lado = 38}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: verdeOscuro, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonCuadrado(
            icono: l.cantidad == 1 ? Icons.delete_outline : Icons.remove,
            tooltip: 'Quitar uno',
            lado: lado,
            onTap: () => carrito.quitarUno(l.producto.id),
          ),
          SizedBox(
            width: lado,
            child: Text(
              '${l.cantidad}',
              textAlign: TextAlign.center,
              style: AppTypography.body(weight: FontWeight.w700, size: 15.5),
            ),
          ),
          Tooltip(
            message: 'Agregar otro',
            child: Material(
              color: verdeOscuro,
              child: InkWell(
                onTap: () => carrito.agregar(carrito.restaurante!, l.producto),
                child: SizedBox(
                  width: lado,
                  height: lado,
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonEliminar(LineaCarrito l, {required bool conTexto}) {
    return Tooltip(
      message: 'Quitar del carrito',
      child: InkWell(
        onTap: () => carrito.eliminar(l.producto.id),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.delete_outline, size: 19, color: grisTexto),
              if (conTexto) ...[
                const SizedBox(width: 4),
                Text(
                  'Eliminar',
                  style: AppTypography.body(
                    color: grisTexto,
                    weight: FontWeight.w600,
                    size: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Una línea del carrito con alto fijo [alto]. Según el alto y el ancho
  /// disponibles cambia de forma para que todo quepa sin hacer scroll:
  ///   - alta: foto vertical grande, nombre, precio, descripción y controles;
  ///   - media: lo mismo sin descripción;
  ///   - fila: todo en una sola línea (cuando hay muchos productos).
  Widget _tarjetaLinea(LineaCarrito l, double alto, double ancho) {
    final fila = ancho >= 600 && alto < 136;
    final conDescripcion = !fila && alto >= 172 && ancho >= 560;
    final descripcion = (l.producto.descripcion ?? '').trim();
    final anchoFoto = (alto * 0.78).clamp(62.0, 150.0).toDouble();
    final ladoStepper = alto >= 136 ? 38.0 : 32.0;
    final relleno = alto >= 136 ? 18.0 : 12.0;

    final foto = SizedBox(
      width: anchoFoto,
      child: Stack(
        children: [
          Positioned.fill(
            child: Imagenes.fotoDeProducto(
              l.producto,
              tamanoIcono: anchoFoto * 0.38,
            ),
          ),
        ],
      ),
    );

    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.producto.nombre,
          maxLines: fila || alto < 136 ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(
            weight: FontWeight.w700,
            size: alto >= 136 ? 17.5 : 15.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${dinero(l.producto.precio)} c/u',
          style: AppTypography.body(
            color: grisTexto,
            weight: FontWeight.w500,
            size: 13,
          ),
        ),
        if (conDescripcion && descripcion.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            descripcion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              color: grisTexto,
              weight: FontWeight.w400,
              size: 12.5,
            ),
          ),
        ],
      ],
    );

    final importe = Text(
      dinero(l.importe),
      style: AppTypography.title(size: alto >= 136 ? 22 : 18),
    );

    final Widget contenido;
    if (fila) {
      contenido = Padding(
        padding: EdgeInsets.symmetric(horizontal: relleno + 2),
        child: Row(
          children: [
            Expanded(child: nombre),
            const SizedBox(width: 12),
            _stepper(l, lado: ladoStepper),
            SizedBox(
              width: 104,
              child: Align(alignment: Alignment.centerRight, child: importe),
            ),
            const SizedBox(width: 6),
            _botonEliminar(l, conTexto: false),
          ],
        ),
      );
    } else {
      contenido = Padding(
        padding: EdgeInsets.all(relleno),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: nombre),
                _botonEliminar(l, conTexto: ancho >= 560 && alto >= 136),
              ],
            ),
            Row(
              children: [
                _stepper(l, lado: ladoStepper),
                const Spacer(),
                importe,
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      height: alto,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [foto, Expanded(child: contenido)],
      ),
    );
  }

  /// Los productos reparten el alto que haya: pocos productos = tarjetas
  /// grandes con foto; muchos = filas compactas. Así todo cabe en la pantalla
  /// sin hacer scroll (solo si hubiera una cantidad enorme de productos, la
  /// lista se desplaza dentro de su propio espacio).
  Widget _regionLineas() {
    return LayoutBuilder(
      builder: (context, c) {
        final lineas = carrito.lineas;
        final n = lineas.length;
        const hueco = 12.0;
        final minAlto = c.maxWidth >= 600 ? 72.0 : 100.0;
        final maxAlto = c.maxWidth >= 600 ? 190.0 : 128.0;

        final cada = (c.maxHeight - hueco * (n - 1)) / n;
        final cabe = cada >= minAlto;
        final alto = cada.clamp(minAlto, maxAlto).toDouble();

        final tarjetas = [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(height: hueco),
            _tarjetaLinea(lineas[i], alto, c.maxWidth),
          ],
        ];

        if (cabe) {
          return Align(
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: tarjetas),
          );
        }
        return SingleChildScrollView(child: Column(children: tarjetas));
      },
    );
  }

  Widget _enlaces() {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 18, color: turquesa),
                const SizedBox(width: 6),
                Text(
                  'Seguir agregando',
                  style: AppTypography.body(
                    color: turquesa,
                    weight: FontWeight.w700,
                    size: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: _vaciar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Text(
              'Vaciar carrito',
              style: AppTypography.body(
                color: grisTexto,
                weight: FontWeight.w600,
                size: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Columna de productos: encabezado, productos y enlaces, todo dentro de
  /// la altura de la pantalla.
  Widget _columnaProductos({required bool compacto, required bool corto}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezado(compacto: compacto, corto: corto),
        SizedBox(height: corto ? 12 : 18),
        Expanded(child: _regionLineas()),
        const SizedBox(height: 4),
        _enlaces(),
      ],
    );
  }

  // =====================================================
  // RESUMEN
  // =====================================================

  Widget _filaMonto(
    String etiqueta,
    String valor, {
    String? detalle,
    Color? colorValor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: AppTypography.body(
                  weight: FontWeight.w600,
                  size: 15,
                ),
              ),
              if (detalle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detalle,
                    style: AppTypography.body(
                      color: grisTexto,
                      weight: FontWeight.w400,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          valor,
          style: AppTypography.body(
            weight: FontWeight.w700,
            size: 15,
            color: colorValor ?? verdeOscuro,
          ),
        ),
      ],
    );
  }

  Widget _resumen({required bool conBoton, bool conNotas = true}) {
    final subtotal = carrito.subtotal;
    final envio = cotizacion?.costoEnvio;
    final total = envio == null ? null : subtotal + envio;
    final km = cotizacion?.distanciaKm;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: grisBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESUMEN', style: _rotulo(size: 10)),
          const SizedBox(height: 4),
          Text('Tu cuenta', style: AppTypography.title(size: 22)),
          const SizedBox(height: 18),
          _filaMonto(
            'Subtotal',
            dinero(subtotal),
            detalle: carrito.totalPiezas == 1
                ? '1 pieza'
                : '${carrito.totalPiezas} piezas',
          ),
          const SizedBox(height: 12),
          _filaMonto(
            'Envío',
            cargandoEnvio ? 'Calculando…' : (envio == null ? '—' : dinero(envio)),
            detalle: km != null
                ? 'Calculado con tu ubicación · ${km.toStringAsFixed(1)} km'
                : 'Se calcula con tu ubicación',
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: grisBorde),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('TOTAL', style: _rotulo(size: 11.5)),
              Text(
                total == null ? '—' : dinero(total),
                style: AppTypography.title(size: 32),
              ),
            ],
          ),
          if (errorEnvio != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFBE9EC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorEnvio!,
                    style: AppTypography.body(
                      color: AppColors.error,
                      weight: FontWeight.w500,
                      size: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _calcularEnvio,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'REINTENTAR',
                        style: _rotulo(color: AppColors.error, size: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (conBoton) ...[
            const SizedBox(height: 18),
            _botonSolido(
              texto: 'Confirmar pedido',
              icono: Icons.arrow_forward,
              cargando: cargandoEnvio,
              onTap: cotizacion == null ? null : _confirmar,
            ),
          ],
          if (conNotas) ...[
            const SizedBox(height: 6),
            _nota(
              Icons.place_outlined,
              'En el siguiente paso marcas tu dirección en el mapa.',
            ),
            _nota(
              Icons.payments_outlined,
              'Paga en efectivo al recibir o en línea con Mercado Pago.',
            ),
            _nota(
              Icons.route_outlined,
              'Después sigues a tu repartidor en tiempo real.',
            ),
          ],
        ],
      ),
    );
  }

  // Celular: subtotal y envío en dos renglones, arriba de la barra del total.
  Widget _resumenMini() {
    final envio = cotizacion?.costoEnvio;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: grisBorde)),
      ),
      child: Column(
        children: [
          _filaMonto('Subtotal', dinero(carrito.subtotal)),
          const SizedBox(height: 4),
          _filaMonto(
            'Envío',
            cargandoEnvio ? 'Calculando…' : (envio == null ? '—' : dinero(envio)),
          ),
          if (errorEnvio != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    errorEnvio!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      color: AppColors.error,
                      weight: FontWeight.w500,
                      size: 12,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _calcularEnvio,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      'REINTENTAR',
                      style: _rotulo(color: AppColors.error, size: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Celular: total y botón fijos abajo.
  Widget _barraInferior() {
    final envio = cotizacion?.costoEnvio;
    final total = envio == null ? null : carrito.subtotal + envio;

    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: grisBorde)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('TOTAL', style: _rotulo(size: 10)),
              Text(
                total == null ? '—' : dinero(total),
                style: AppTypography.title(size: 24),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _botonSolido(
              texto: 'Confirmar',
              icono: Icons.arrow_forward,
              cargando: cargandoEnvio,
              onTap: cotizacion == null ? null : _confirmar,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CARRITO VACÍO
  // =====================================================

  Widget _carritoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: grisBorde),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                color: menta,
                child: const Icon(
                  Icons.shopping_basket_outlined,
                  size: 36,
                  color: turquesa,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Tu carrito está vacío',
                textAlign: TextAlign.center,
                style: AppTypography.title(size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                'Entra a un restaurante y agrega lo que se te antoje. Aquí '
                'verás tu pedido y el total.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: grisTexto,
                  weight: FontWeight.w400,
                  size: 14,
                ),
              ),
              const SizedBox(height: 22),
              _botonSolido(
                texto: 'Ver restaurantes',
                icono: Icons.arrow_forward,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // PANTALLA COMPLETA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final alto = constraints.maxHeight;
          final compacto = ancho < 700;
          final columnas = ancho >= _anchoConColumnas;
          final corto = alto < 760;

          final margen = ancho > _anchoMaximo + 48
              ? (ancho - _anchoMaximo) / 2
              : (compacto ? 18.0 : 28.0);

          return Column(
            children: [
              _barraSuperior(margen),
              Expanded(
                child: ListenableBuilder(
                  listenable: carrito,
                  builder: (context, _) {
                    if (carrito.vacio) return _carritoVacio();

                    // Pantalla ancha: productos a la izquierda y resumen a la
                    // derecha, sin scroll de página.
                    if (columnas) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(margen, corto ? 18 : 26, margen, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _columnaProductos(
                                compacto: false,
                                corto: corto,
                              ),
                            ),
                            const SizedBox(width: 28),
                            SizedBox(
                              width: _anchoResumen,
                              child: SingleChildScrollView(
                                child: _resumen(
                                  conBoton: true,
                                  conNotas: !corto,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Celular o ventana angosta: productos que se acomodan al
                    // alto, y abajo el resumen corto con el total y el botón.
                    return Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(margen, 16, margen, 6),
                            child: _columnaProductos(
                              compacto: compacto,
                              corto: true,
                            ),
                          ),
                        ),
                        _resumenMini(),
                        _barraInferior(),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
