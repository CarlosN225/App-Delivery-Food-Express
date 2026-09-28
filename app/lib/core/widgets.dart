import 'package:flutter/material.dart';
import 'theme.dart';

/// Mensaje flotante reutilizable (error en rojo, éxito en verde oscuro).
void showAppSnackBar(BuildContext context, String message, {bool isError = true}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.error : AppColors.primaryDark,
      content: Text(message, style: AppTypography.body(color: Colors.white)),
    ),
  );
}

/// Barra superior verde de las pantallas de autenticación.
class AuthTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const AuthTopBar({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        18,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
          ],
          Text(title, style: AppTypography.barTitle()),
        ],
      ),
    );
  }
}

/// Logo de Food Express (imagen en assets/images).
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 130});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_food_express.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Campo de texto con ícono al inicio, como en los wireframes.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.suffix,
  });

  static OutlineInputBorder _border(Color color, {double width = 1.5}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: AppTypography.body(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body(color: AppColors.hint),
        prefixIcon: Icon(icon, color: AppColors.primaryDark),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.primary, width: 2),
        errorBorder: _border(AppColors.error),
        focusedErrorBorder: _border(AppColors.error, width: 2),
      ),
    );
  }
}

/// Botón principal (relleno verde), con estado de carga.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label, style: AppTypography.button()),
      ),
    );
  }
}

/// Tarjeta-botón secundaria: "¿Nuevo por aquí? / Crear cuenta".
class SecondaryCardButton extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback? onPressed;

  const SecondaryCardButton({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.primary, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(question, style: AppTypography.body()),
            Text(
              action,
              style: AppTypography.body(
                color: AppColors.primary,
                weight: FontWeight.w600,
              ).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de tipo de cuenta: Cliente | Repartidor.
class AccountTypeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const AccountTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Option(
            label: 'Cliente',
            icon: Icons.person,
            selected: value == 'cliente',
            isLeft: true,
            onTap: () => onChanged('cliente'),
          ),
        ),
        Expanded(
          child: _Option(
            label: 'Repartidor',
            icon: Icons.two_wheeler,
            selected: value == 'repartidor',
            isLeft: false,
            onTap: () => onChanged('repartidor'),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isLeft;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(12);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: selected ? AppColors.mint : Colors.white,
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.primary,
            width: 2,
          ),
          borderRadius: isLeft
              ? const BorderRadius.horizontal(left: radius)
              : const BorderRadius.horizontal(right: radius),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: AppColors.primaryDark),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.body(weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}