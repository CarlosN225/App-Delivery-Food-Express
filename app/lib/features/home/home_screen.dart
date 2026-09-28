import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';

class HomeScreen extends StatelessWidget {
  final UsuarioAutenticado usuario;

  const HomeScreen({super.key, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Food Express', style: AppTypography.barTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppColors.mint, size: 72),
              const SizedBox(height: 16),
              Text(
                '¡Bienvenido, ${usuario.nombre}!',
                textAlign: TextAlign.center,
                style: AppTypography.title(size: 24),
              ),
              const SizedBox(height: 8),
              Text('Correo: ${usuario.correo}', style: AppTypography.body()),
              const SizedBox(height: 4),
              Text('Rol: ${usuario.rol}', style: AppTypography.body()),
              const SizedBox(height: 24),
              Text(
                'Sesión iniciada correctamente. El flujo de cliente y repartidor '
                'se construye a partir del Sprint 2.',
                textAlign: TextAlign.center,
                style: AppTypography.body(color: AppColors.hint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}