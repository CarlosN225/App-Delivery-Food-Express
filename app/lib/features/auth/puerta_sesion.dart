import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../delivery/repartidor_screen.dart';
import '../home/home_screen.dart';
import 'auth_service.dart';
import 'login_screen.dart';

/// Pantalla que corresponde a cada rol al entrar:
/// el repartidor va a su panel; el cliente y el administrador, al inicio.
Widget pantallaInicialPara(UsuarioAutenticado usuario) {
  return usuario.rol == 'repartidor'
      ? RepartidorScreen(usuario: usuario)
      : HomeScreen(usuario: usuario);
}

/// Puerta de entrada de la app. Si hay una sesión guardada y el servidor
/// la acepta, abre directo la pantalla del usuario; si no, muestra el login.
class PuertaSesion extends StatefulWidget {
  const PuertaSesion({super.key});

  @override
  State<PuertaSesion> createState() => _PuertaSesionState();
}

class _PuertaSesionState extends State<PuertaSesion> {
  late final Future<UsuarioAutenticado?> _sesion;

  @override
  void initState() {
    super.initState();
    _sesion = AuthService().restaurarSesion();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsuarioAutenticado?>(
      future: _sesion,
      builder: (context, estado) {
        if (estado.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo-food-express.png',
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final usuario = estado.data;
        if (usuario == null) return const LoginScreen();
        return pantallaInicialPara(usuario);
      },
    );
  }
}
