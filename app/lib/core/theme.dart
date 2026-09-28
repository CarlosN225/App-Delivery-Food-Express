import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad visual de Food Express, tomada del logo y de los wireframes.
class AppColors {
  static const primary = Color(0xFF0AA89A); // verde azulado principal
  static const primaryDark = Color(0xFF085858); // teal oscuro (texto y marcos)
  static const mint = Color(0xFF68D888); // verde menta (acentos)
  static const background = Color(0xFFE8F8F8); // blanco hielo
  static const border = Color(0xFFBFE3DE); // bordes de campos y tarjetas
  static const hint = Color(0xFF5E8F8B); // texto de ayuda en campos
  static const error = Color(0xFFD1495B);
}

class AppTypography {
  static TextStyle title({double size = 32}) => GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryDark,
        height: 1.1,
      );

  static TextStyle subtitle() => GoogleFonts.poppins(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: AppColors.primaryDark,
      );

  static TextStyle body({
    Color color = AppColors.primaryDark,
    FontWeight weight = FontWeight.w500,
    double size = 15,
  }) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

  static TextStyle button() => GoogleFonts.poppins(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  static TextStyle barTitle() => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );
}

ThemeData buildFoodExpressTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.mint,
      error: AppColors.error,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: AppColors.primaryDark,
      displayColor: AppColors.primaryDark,
    ),
  );
}