
import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import 'auth_service.dart';
import 'puerta_sesion.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  final _correoFocus = FocusNode();
  final _contrasenaFocus = FocusNode();

  final _authService = AuthService();

  bool _cargando = false;
  bool _ocultarContrasena = true;

  static const Color _verdeOscuro = Color(0xFF005457);
  static const Color _turquesa = Color(0xFF00A99D);
  static const Color _textoSecundario = Color(0xFF536E79);

  // ==================================================
  // AUTENTICACIÓN
  // ==================================================

  Future<void> _iniciarSesion() async {
    if (_cargando) return;

    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _cargando = true);

    try {
      final usuario = await _authService.iniciarSesion(
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          // El repartidor entra a su panel de entregas; el cliente (y el
          // administrador) al inicio con los restaurantes.
          builder: (_) => pantallaInicialPara(usuario),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.mensaje);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo conectar con el servidor. '
          'Revisa que el backend esté corriendo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _abrirRegistro() {
    if (_cargando) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegisterScreen(),
      ),
    );
  }

  void _mostrarRecuperacion() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La recuperación de contraseña estará '
          'disponible próximamente.',
        ),
      ),
    );
  }

  // ==================================================
  // DECORACIÓN DE CAMPOS
  // ==================================================

  InputDecoration _decoracionCampo({
    required String placeholder,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: placeholder,
      hintStyle: const TextStyle(
        color: Color(0xFFA2A9B0),
        fontSize: 17,
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 13,
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

  // ==================================================
  // CAMPO CORREO
  // ==================================================

  Widget _campoCorreo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correo electrónico',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: _correoController,
          focusNode: _correoFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(
            fontSize: 17,
            color: _verdeOscuro,
          ),
          decoration: _decoracionCampo(
            placeholder: 'nombre@correo.com',
          ),
          onFieldSubmitted: (_) {
            _contrasenaFocus.requestFocus();
          },
          validator: (valor) {
            if (valor == null ||
                valor.trim().isEmpty ||
                !valor.contains('@')) {
              return 'Ingresa un correo válido';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ==================================================
  // CAMPO CONTRASEÑA
  // ==================================================

  Widget _campoContrasena() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contraseña',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: _contrasenaController,
          focusNode: _contrasenaFocus,
          obscureText: _ocultarContrasena,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          style: const TextStyle(
            fontSize: 17,
            color: _verdeOscuro,
          ),
          decoration: _decoracionCampo(
            placeholder: '••••••••',
            suffix: IconButton(
              tooltip: _ocultarContrasena
                  ? 'Mostrar contraseña'
                  : 'Ocultar contraseña',
              icon: Icon(
                _ocultarContrasena
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _turquesa,
                size: 24,
              ),
              onPressed: () {
                setState(() {
                  _ocultarContrasena = !_ocultarContrasena;
                });
              },
            ),
          ),

          // ENTER = INICIAR SESIÓN
          onFieldSubmitted: (_) {
            _iniciarSesion();
          },

          validator: (valor) {
            if (valor == null || valor.length < 6) {
              return 'Mínimo 6 caracteres';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ==================================================
  // FORMULARIO DERECHO
  // ==================================================

  Widget _formulario({
    required bool compacto,
    required double alturaDisponible,
  }) {
    final bool alturaReducida = alturaDisponible < 760;
    final bool alturaMuyReducida = alturaDisponible < 610;

    // Los espacios se ajustan a la altura real.
    final double logoAlto = alturaMuyReducida
        ? 100
        : alturaReducida
            ? 125
            : 155;

    final double espacioLogoTitulo = alturaMuyReducida
        ? 16
        : alturaReducida
            ? 24
            : 42;

    final double espacioTituloCampos = alturaMuyReducida
        ? 16
        : alturaReducida
            ? 25
            : 38;

    final double espacioEntreCampos = alturaMuyReducida
        ? 15
        : alturaReducida
            ? 24
            : 32;

    final double espacioAntesBoton = alturaMuyReducida
        ? 12
        : alturaReducida
            ? 20
            : 30;

    final double espacioRegistro = alturaMuyReducida
        ? 10
        : alturaReducida
            ? 16
            : 24;

    final double tituloTamano = alturaMuyReducida
        ? 35
        : alturaReducida
            ? 42
            : 52;

    final double altoBoton = alturaMuyReducida
        ? 48
        : alturaReducida
            ? 54
            : 64;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? 26 : 56,
            vertical: alturaMuyReducida
                ? 12
                : alturaReducida
                    ? 20
                    : 30,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 560,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LOGO
                  Image.asset(
                    'assets/images/logo-food-express.png',
                    height: logoAlto,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return const Center(
                        child: Text(
                          'FOOD EXPRESS',
                          style: TextStyle(
                            color: _verdeOscuro,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: espacioLogoTitulo),

                  // TÍTULO
                  Text(
                    'Inicia sesión',
                    style: TextStyle(
                      fontSize: tituloTamano,
                      fontWeight: FontWeight.w900,
                      color: _verdeOscuro,
                      letterSpacing: -1.6,
                      height: 1.1,
                    ),
                  ),

                  SizedBox(height: espacioTituloCampos),

                  // CORREO
                  _campoCorreo(),

                  SizedBox(height: espacioEntreCampos),

                  // CONTRASEÑA
                  _campoContrasena(),

                  const SizedBox(height: 12),

                  // RECUPERACIÓN
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _mostrarRecuperacion,
                      style: TextButton.styleFrom(
                        foregroundColor: _turquesa,
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 0,
                        ),
                      ),
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: espacioAntesBoton),

                  // BOTÓN ENTRAR
                  SizedBox(
                    height: altoBoton,
                    child: ElevatedButton(
                      onPressed:
                          _cargando ? null : _iniciarSesion,
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
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Entrar',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),

                  SizedBox(height: espacioRegistro),

                  // CREAR CUENTA
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment:
                        WrapCrossAlignment.center,
                    spacing: 5,
                    children: [
                      const Text(
                        '¿Nuevo por aquí?',
                        style: TextStyle(
                          color: _textoSecundario,
                          fontSize: 16,
                        ),
                      ),
                      TextButton(
                        onPressed:
                            _cargando ? null : _abrirRegistro,
                        style: TextButton.styleFrom(
                          foregroundColor: _turquesa,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                        ),
                        child: const Text(
                          'Crear cuenta',
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
          final double ancho = constraints.maxWidth;
          final double alto = constraints.maxHeight;

          final bool compacto = ancho < 850;

          if (compacto) {
            return SafeArea(
              child: _formulario(
                compacto: true,
                alturaDisponible: alto,
              ),
            );
          }

          return Row(
            children: [
              // IMAGEN IZQUIERDA
              Expanded(
                flex: 56,
                child: ClipRect(
                  child: SizedBox.expand(
                    child: Image.asset(
                      'assets/images/seccion-izquierda.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // FORMULARIO DERECHO
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
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    _correoFocus.dispose();
    _contrasenaFocus.dispose();
    super.dispose();
  }
}
