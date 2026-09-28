import 'package:flutter/material.dart';
import '../../core/theme.dart';
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
  final _authService = AuthService();

  String _rol = 'cliente';
  bool _cargando = false;
  bool _ocultarContrasena = true;

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);
    try {
      await _authService.registrar(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
        rol: _rol,
      );

      if (!mounted) return;
      showAppSnackBar(context, 'Cuenta creada. Ya puedes iniciar sesión.', isError: false);
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'No se pudo conectar con el servidor.');
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
          AuthTopBar(
            title: 'Crear cuenta',
            onBack: () => Navigator.of(context).pop(),
          ),
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
                        AppTextField(
                          controller: _nombreController,
                          hint: 'Nombre completo',
                          icon: Icons.person_outline,
                          validator: (valor) =>
                              (valor == null || valor.trim().length < 2)
                                  ? 'Ingresa tu nombre'
                                  : null,
                        ),
                        const SizedBox(height: 14),
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
                        Text(
                          'Tipo de cuenta',
                          style: AppTypography.body(weight: FontWeight.w600, size: 17),
                        ),
                        const SizedBox(height: 10),
                        AccountTypeSelector(
                          value: _rol,
                          onChanged: (valor) => setState(() => _rol = valor),
                        ),
                        const SizedBox(height: 26),
                        PrimaryButton(
                          label: 'Registrarme',
                          loading: _cargando,
                          onPressed: _registrar,
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
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }
}