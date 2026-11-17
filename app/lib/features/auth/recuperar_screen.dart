import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import 'firebase_auth_service.dart';

/// Recuperación de contraseña con Firebase Authentication (nube).
///
/// La persona escribe su correo, Firebase le manda un enlace para elegir una
/// contraseña nueva y después inicia sesión normalmente con ella.
class RecuperarScreen extends StatefulWidget {
  final String correoInicial;

  const RecuperarScreen({super.key, this.correoInicial = ''});

  @override
  State<RecuperarScreen> createState() => _RecuperarScreenState();
}

class _RecuperarScreenState extends State<RecuperarScreen> {
  static const Color _verdeOscuro = Color(0xFF005457);
  static const Color _turquesa = Color(0xFF00A99D);
  static const Color _textoSecundario = Color(0xFF536E79);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _correo =
      TextEditingController(text: widget.correoInicial);

  bool _enviando = false;
  String? _enviadoA;

  @override
  void dispose() {
    _correo.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _enviando = true);

    final correo = _correo.text.trim();
    try {
      await FirebaseAuthService.enviarCorreoRecuperacion(correo);
      if (!mounted) return;
      setState(() => _enviadoA = correo);
    } on FirebaseAuthException catch (e) {
      if (mounted) showAppSnackBar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  InputDecoration _decoracion() {
    return const InputDecoration(
      hintText: 'nombre@correo.com',
      hintStyle: TextStyle(color: Color(0xFFA2A9B0), fontSize: 17),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 13),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: _verdeOscuro, width: 1.2),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: _turquesa, width: 2),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  Widget _boton(String texto, VoidCallback? alPulsar, {bool cargando = false}) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: alPulsar,
        style: ElevatedButton.styleFrom(
          backgroundColor: _turquesa,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _turquesa.withValues(alpha: 0.6),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        child: cargando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                texto,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Recupera tu contraseña',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: _verdeOscuro,
              letterSpacing: -1.2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Escribe el correo de tu cuenta y te mandamos un enlace para '
            'elegir una contraseña nueva.',
            style: TextStyle(fontSize: 16, color: _textoSecundario, height: 1.4),
          ),
          const SizedBox(height: 28),
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
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontSize: 17, color: _verdeOscuro),
            decoration: _decoracion(),
            onFieldSubmitted: (_) => _enviar(),
            validator: (valor) {
              if (valor == null ||
                  valor.trim().isEmpty ||
                  !valor.contains('@')) {
                return 'Ingresa un correo válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 30),
          _boton('Enviar enlace', _enviando ? null : _enviar,
              cargando: _enviando),
        ],
      ),
    );
  }

  Widget _confirmacion(String correo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 56, color: _turquesa),
        const SizedBox(height: 18),
        const Text(
          'Revisa tu correo',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            color: _verdeOscuro,
            letterSpacing: -1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Si $correo tiene cuenta, te llegará un enlace de Firebase. Ábrelo, '
          'elige tu contraseña nueva y regresa a iniciar sesión con ella.',
          style: const TextStyle(
            fontSize: 16,
            color: _textoSecundario,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si no lo ves, revisa la carpeta de spam.',
          style: TextStyle(fontSize: 14, color: _textoSecundario),
        ),
        const SizedBox(height: 30),
        _boton('Volver a iniciar sesión', () => Navigator.of(context).pop()),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() => _enviadoA = null),
          style: TextButton.styleFrom(foregroundColor: _turquesa),
          child: const Text(
            'Usar otro correo',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _verdeOscuro),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _enviadoA == null ? _formulario() : _confirmacion(_enviadoA!),
            ),
          ),
        ),
      ),
    );
  }
}
