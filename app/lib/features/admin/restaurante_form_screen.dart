import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_service.dart';
import 'admin_service.dart';
import 'dialogo_confirmar.dart';

/// Formulario para crear o editar un restaurante (Sprint 4, historia #16).
/// Al guardar o eliminar con éxito, cierra la pantalla devolviendo `true`.
class RestauranteFormScreen extends StatefulWidget {
  final UsuarioAutenticado usuario;
  final RestauranteAdmin? restaurante;

  const RestauranteFormScreen({
    super.key,
    required this.usuario,
    this.restaurante,
  });

  @override
  State<RestauranteFormScreen> createState() => _RestauranteFormScreenState();
}

class _RestauranteFormScreenState extends State<RestauranteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _direccion;
  late final TextEditingController _categoria;
  late final TextEditingController _latitud;
  late final TextEditingController _longitud;
  bool _guardando = false;
  bool _ubicando = false;

  bool get _editando => widget.restaurante != null;

  @override
  void initState() {
    super.initState();
    final r = widget.restaurante;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _direccion = TextEditingController(text: r?.direccion ?? '');
    _categoria = TextEditingController(text: r?.categoria ?? '');
    _latitud = TextEditingController(text: r?.latitud?.toString() ?? '');
    _longitud = TextEditingController(text: r?.longitud?.toString() ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _direccion.dispose();
    _categoria.dispose();
    _latitud.dispose();
    _longitud.dispose();
    super.dispose();
  }

  double? _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));

  String? _textoOpcional(TextEditingController c) {
    final texto = c.text.trim();
    return texto.isEmpty ? null : texto;
  }

  String? _validarNombre(String? valor) {
    if (valor == null || valor.trim().length < 2) {
      return 'Escribe el nombre (mínimo 2 letras).';
    }
    return null;
  }

  String? _validarCoordenada(String? valor, {required bool esLatitud}) {
    final texto = (valor ?? '').trim();
    final otro = (esLatitud ? _longitud : _latitud).text.trim();
    final nombre = esLatitud ? 'latitud' : 'longitud';
    if (texto.isEmpty) {
      return otro.isEmpty ? null : 'Escribe también la $nombre.';
    }
    final numero = _numero(texto);
    if (numero == null) return 'Escribe un número, por ejemplo 19.6010.';
    final limite = esLatitud ? 90 : 180;
    if (numero < -limite || numero > limite) {
      return 'Debe estar entre -$limite y $limite.';
    }
    return null;
  }

  Future<void> _usarMiUbicacion() async {
    setState(() => _ubicando = true);
    try {
      final pos = await LocationService.obtenerUbicacionActual();
      if (!mounted) return;
      if (pos == null) {
        showAppSnackBar(
          context,
          'No se pudo obtener tu ubicación. Revisa los permisos del navegador.',
        );
        return;
      }
      setState(() {
        _latitud.text = pos.latitude.toStringAsFixed(6);
        _longitud.text = pos.longitude.toStringAsFixed(6);
      });
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final nombre = _nombre.text.trim();
      final direccion = _textoOpcional(_direccion);
      final categoria = _textoOpcional(_categoria);
      final latitud =
          _latitud.text.trim().isEmpty ? null : _numero(_latitud.text);
      final longitud =
          _longitud.text.trim().isEmpty ? null : _numero(_longitud.text);

      final token = widget.usuario.token;
      final original = widget.restaurante;
      if (original == null) {
        await AdminService.crearRestaurante(
          token,
          nombre: nombre,
          direccion: direccion,
          categoria: categoria,
          latitud: latitud,
          longitud: longitud,
        );
      } else {
        await AdminService.editarRestaurante(
          token,
          original.id,
          nombre: nombre,
          direccion: direccion,
          categoria: categoria,
          latitud: latitud,
          longitud: longitud,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final original = widget.restaurante;
    if (original == null || _guardando) return;
    final ok = await confirmarAccion(
      context,
      titulo: 'Eliminar restaurante',
      mensaje:
          '¿Eliminar "${original.nombre}" y sus ${original.totalProductos} productos? Esta acción no se puede deshacer.',
      textoConfirmar: 'Eliminar',
    );
    if (!ok || !mounted) return;

    setState(() => _guardando = true);
    try {
      await AdminService.eliminarRestaurante(widget.usuario.token, original.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  static const _borde = Color(0xFFD3E2DF);
  static const _menta = Color(0xFFE5F5F3);

  TextStyle _rotulo() {
    return AppTypography.body(
      color: AppColors.hint,
      weight: FontWeight.w700,
      size: 10,
    ).copyWith(letterSpacing: 1.5);
  }

  OutlineInputBorder _marco(Color color, {double ancho = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color, width: ancho),
    );
  }

  /// Campo de texto de esquinas rectas, igual que el resto de la app.
  Widget _campo({
    required TextEditingController controller,
    required String etiqueta,
    required String hint,
    TextInputType? teclado,
    String? Function(String?)? validar,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: _rotulo()),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: teclado,
          validator: validar,
          style: AppTypography.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.body(color: AppColors.hint, size: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: _marco(_borde),
            enabledBorder: _marco(_borde),
            focusedBorder: _marco(AppColors.primary, ancho: 1.6),
            errorBorder: _marco(AppColors.error),
            focusedErrorBorder: _marco(AppColors.error, ancho: 1.6),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final decimales = const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          BarraSuperiorFE(
            titulo: _editando ? 'Editar restaurante' : 'Nuevo restaurante',
          ),
          Expanded(
            child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _menta,
                border: Border.all(color: _borde),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ADMINISTRACIÓN', style: _rotulo()),
                    const SizedBox(height: 4),
                    Text(
                      _editando ? 'Editar restaurante' : 'Nuevo restaurante',
                      style: AppTypography.title(size: 26),
                    ),
                    const SizedBox(height: 22),
                    _campo(
                      controller: _nombre,
                      etiqueta: 'Nombre',
                      hint: 'Nombre del restaurante',
                      validar: _validarNombre,
                    ),
                    const SizedBox(height: 16),
                    _campo(
                      controller: _direccion,
                      etiqueta: 'Dirección',
                      hint: 'Calle, colonia y municipio',
                    ),
                    const SizedBox(height: 16),
                    _campo(
                      controller: _categoria,
                      etiqueta: 'Categoría',
                      hint: 'Ej. Pizzas',
                    ),
                    const SizedBox(height: 26),
                    Text('UBICACIÓN', style: _rotulo()),
                    const SizedBox(height: 6),
                    Text(
                      'Con coordenadas, los clientes lo encuentran en la búsqueda por cercanía.',
                      style: AppTypography.body(color: AppColors.hint, size: 13),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _campo(
                            controller: _latitud,
                            etiqueta: 'Latitud',
                            hint: 'Ej. 19.6010',
                            teclado: decimales,
                            validar: (v) =>
                                _validarCoordenada(v, esLatitud: true),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _campo(
                            controller: _longitud,
                            etiqueta: 'Longitud',
                            hint: 'Ej. -99.3085',
                            teclado: decimales,
                            validar: (v) =>
                                _validarCoordenada(v, esLatitud: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _ubicando ? null : _usarMiUbicacion,
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        _ubicando ? 'Buscando…' : 'Usar mi ubicación actual',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.primary),
                        shape: const RoundedRectangleBorder(),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _guardando ? null : _guardar,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primary,
                          disabledForegroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _editando
                                    ? 'Guardar cambios'
                                    : 'Crear restaurante',
                                style: AppTypography.button(),
                              ),
                      ),
                    ),
                    if (_editando) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _guardando ? null : _eliminar,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar restaurante'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          shape: const RoundedRectangleBorder(),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
        ],
      ),
    );
  }
}
