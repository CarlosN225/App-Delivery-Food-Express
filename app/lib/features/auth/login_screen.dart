import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../home/home_screen.dart';
import 'auth_service.dart';
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
  final _authService = AuthService();

  bool _cargando = false;
  bool _ocultarContrasena = true;

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);
    try {
      final usuario = await _authService.iniciarSesion(
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(usuario: usuario)),
      );
    } on AuthException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo conectar con el servidor. Revisa que el backend esté corriendo.',
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AuthTopBar(title: 'Inicio de sesión'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppLogo(size: 130)),
                        const SizedBox(height: 12),
                        Text(
                          'Food Express',
                          textAlign: TextAlign.center,
                          style: AppTypography.title(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tu antojo, en camino',
                          textAlign: TextAlign.center,
                          style: AppTypography.subtitle(),
                        ),
                        const SizedBox(height: 28),
                        AppTextField(
                          controller: _correoController,
                          hint: 'Correo',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (valor) =>
                              (valor == null || !valor.contains('@'))
                                  ? 'Ingresa un correo válido'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _contrasenaController,
                          hint: 'Contraseña',
                          icon: Icons.lock_outline,
                          obscure: _ocultarContrasena,
                          validator: (valor) =>
                              (valor == null || valor.length < 6)
                                  ? 'Mínimo 6 caracteres'
                                  : null,
                          suffix: IconButton(
                            icon: Icon(
                              _ocultarContrasena
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.primaryDark,
                            ),
                            onPressed: () => setState(
                              () => _ocultarContrasena = !_ocultarContrasena,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        PrimaryButton(
                          label: 'Entrar',
                          loading: _cargando,
                          onPressed: _iniciarSesion,
                        ),
                        const SizedBox(height: 14),
                        SecondaryCardButton(
                          question: '¿Nuevo por aquí?',
                          action: 'Crear cuenta',
                          onPressed: _cargando
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  );
                                },
                        ),
                      ],
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

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }
}