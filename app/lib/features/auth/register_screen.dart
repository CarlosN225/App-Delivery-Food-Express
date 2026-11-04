
import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import 'auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  final _nombreFocus = FocusNode();
  final _correoFocus = FocusNode();
  final _contrasenaFocus = FocusNode();

  final _authService = AuthService();

  String _rol = 'cliente';
  bool _cargando = false;
  bool _ocultarContrasena = true;

  static const Color _verdeOscuro = Color(0xFF005457);
  static const Color _turquesa = Color(0xFF00A99D);
  static const Color _textoSecundario = Color(0xFF536E79);
  static const Color _placeholder = Color(0xFFA2A9B0);

  // ==================================================
  // REGISTRO
  // ==================================================

  Future<void> _registrar() async {
    if (_cargando) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _cargando = true);

    try {
      await _authService.registrar(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
        rol: _rol,
      );

      if (!mounted) return;

      showAppSnackBar(
        context,
        'Cuenta creada. Ya puedes iniciar sesión.',
        isError: false,
      );

      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.mensaje);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo conectar con el servidor.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _volver() {
    if (_cargando) return;

    Navigator.of(context).pop();
  }

  // ==================================================
  // CAMPOS
  // ==================================================

  InputDecoration _decoracionCampo({
    required String placeholder,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: placeholder,
      hintStyle: const TextStyle(
        color: _placeholder,
        fontSize: 16,
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: _verdeOscuro,
          width: 1.2,
        ),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: _turquesa,
          width: 2,
        ),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: Colors.redAccent,
        ),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: Colors.redAccent,
          width: 2,
        ),
      ),
    );
  }

  Widget _campo({
    required String titulo,
    required String placeholder,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    bool obscureText = false,
    Widget? suffix,
    Iterable<String>? autofillHints,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 2),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          obscureText: obscureText,
          autofillHints: autofillHints,
          style: const TextStyle(
            color: _verdeOscuro,
            fontSize: 16,
          ),
          decoration: _decoracionCampo(
            placeholder: placeholder,
            suffix: suffix,
          ),
          validator: validator,
        ),
      ],
    );
  }

  // ==================================================
  // TIPO DE CUENTA
  // ==================================================

  Widget _opcionRol({
    required String valor,
    required String titulo,
    required IconData icono,
  }) {
    final seleccionado = _rol == valor;

    return InkWell(
      onTap: _cargando
          ? null
          : () {
              setState(() => _rol = valor);
            },
      child: Container(
        padding: const EdgeInsets.only(
          left: 6,
          right: 12,
          top: 8,
          bottom: 9,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: seleccionado
                  ? _turquesa
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icono,
              size: 25,
              color: seleccionado
                  ? _turquesa
                  : _textoSecundario,
            ),
            const SizedBox(width: 9),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 17,
                fontWeight: seleccionado
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: seleccionado
                    ? _turquesa
                    : _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectorRol() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de cuenta',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 35,
          runSpacing: 6,
          children: [
            _opcionRol(
              valor: 'cliente',
              titulo: 'Cliente',
              icono: Icons.person,
            ),
            _opcionRol(
              valor: 'repartidor',
              titulo: 'Repartidor',
              icono: Icons.delivery_dining,
            ),
          ],
        ),
      ],
    );
  }

  // ==================================================
  // BOTÓN VOLVER EN LA ESQUINA SUPERIOR DERECHA
  // ==================================================

  Widget _botonVolver() {
    return Material(
      color: const Color(0xCC004B50),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _cargando ? null : _volver,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 21,
              ),
              SizedBox(width: 8),
              Text(
                'Volver',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================================================
  // FORMULARIO IZQUIERDO
  // ==================================================

  Widget _formulario({
    required bool compacto,
    required double alturaDisponible,
  }) {
    final bool bajo = alturaDisponible < 900;
    final bool muyBajo = alturaDisponible < 680;

    final double logoAlto = muyBajo
        ? 78
        : bajo
            ? 92
            : 115;

    final double tituloTamano = muyBajo
        ? 33
        : bajo
            ? 41
            : 52;

    final double espacioGrande = muyBajo
        ? 12
        : bajo
            ? 18
            : 28;

    final double espacioCampos = muyBajo
        ? 10
        : bajo
            ? 15
            : 22;

    final double altoBoton = muyBajo
        ? 46
        : bajo
            ? 52
            : 62;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 26 : 48,
          vertical: muyBajo
              ? 8
              : bajo
                  ? 12
                  : 26,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 555,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LOGO
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/images/logo-food-express.png',
                    height: logoAlto,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return const Text(
                        'FOOD EXPRESS',
                        style: TextStyle(
                          fontSize: 27,
                          color: _verdeOscuro,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(height: espacioGrande),

                // TÍTULO
                Text(
                  'Crea tu cuenta',
                  style: TextStyle(
                    color: _verdeOscuro,
                    fontSize: tituloTamano,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    height: 1.08,
                  ),
                ),

                SizedBox(height: espacioGrande),

                // CLIENTE / REPARTIDOR
                _selectorRol(),

                SizedBox(height: espacioGrande),

                // NOMBRE
                _campo(
                  titulo: 'Nombre completo',
                  placeholder: 'Tu nombre y apellido',
                  controller: _nombreController,
                  focusNode: _nombreFocus,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.name,
                  ],
                  onSubmitted: (_) {
                    _correoFocus.requestFocus();
                  },
                  validator: (valor) {
                    if (valor == null ||
                        valor.trim().length < 2) {
                      return 'Ingresa tu nombre completo';
                    }
                    return null;
                  },
                ),

                SizedBox(height: espacioCampos),

                // CORREO
                _campo(
                  titulo: 'Correo electrónico',
                  placeholder: 'nombre@correo.com',
                  controller: _correoController,
                  focusNode: _correoFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.email,
                  ],
                  onSubmitted: (_) {
                    _contrasenaFocus.requestFocus();
                  },
                  validator: (valor) {
                    if (valor == null ||
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(valor.trim())) {
                      return 'Ingresa un correo válido';
                    }
                    return null;
                  },
                ),

                SizedBox(height: espacioCampos),

                // CONTRASEÑA
                _campo(
                  titulo: 'Contraseña',
                  placeholder: '••••••••',
                  controller: _contrasenaController,
                  focusNode: _contrasenaFocus,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [
                    AutofillHints.newPassword,
                  ],
                  obscureText: _ocultarContrasena,
                  onSubmitted: (_) => _registrar(),
                  validator: (valor) {
                    if (valor == null || valor.length < 6) {
                      return 'Mínimo 6 caracteres';
                    }
                    return null;
                  },
                  suffix: IconButton(
                    tooltip: _ocultarContrasena
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    icon: Icon(
                      _ocultarContrasena
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 24,
                      color: _turquesa,
                    ),
                    onPressed: () {
                      setState(() {
                        _ocultarContrasena =
                            !_ocultarContrasena;
                      });
                    },
                  ),
                ),

                SizedBox(height: espacioGrande),

                // BOTÓN REGISTRARME
                SizedBox(
                  height: altoBoton,
                  child: ElevatedButton(
                    onPressed:
                        _cargando ? null : _registrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _turquesa,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          _turquesa.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: _cargando
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Registrarme',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),

                SizedBox(
                  height: muyBajo ? 6 : 12,
                ),

                // ENLACE INICIA SESIÓN
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment:
                      WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    const Text(
                      '¿Ya tienes cuenta?',
                      style: TextStyle(
                        fontSize: 16,
                        color: _textoSecundario,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _cargando ? null : _volver,
                      style: TextButton.styleFrom(
                        foregroundColor: _turquesa,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                      ),
                      child: const Text(
                        'Inicia sesión',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          decoration:
                              TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================================================
  // DISEÑO RESPONSIVO
  // ==================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final alto = constraints.maxHeight;

          if (ancho < 850) {
            // En móvil, el botón Volver queda arriba
            // a la derecha sobre fondo verde.
            return SafeArea(
              child: Stack(
                children: [
                  _formulario(
                    compacto: true,
                    alturaDisponible: alto,
                  ),
                  Positioned(
                    top: 12,
                    right: 16,
                    child: _botonVolver(),
                  ),
                ],
              ),
            );
          }

          // Escritorio: formulario izquierda,
          // ilustración derecha.
          return Row(
            children: [
              Expanded(
                flex: 44,
                child: Container(
                  color: Colors.white,
                  child: _formulario(
                    compacto: false,
                    alturaDisponible: alto,
                  ),
                ),
              ),
              Expanded(
                flex: 56,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/seccion-derecha.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),

                    // Botón flotante en la esquina
                    // superior derecha de la pantalla.
                    Positioned(
                      top: 22,
                      right: 24,
                      child: _botonVolver(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();

    _nombreFocus.dispose();
    _correoFocus.dispose();
    _contrasenaFocus.dispose();

    super.dispose();
  }
}
