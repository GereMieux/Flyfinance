import 'package:flutter/material.dart';

/// Couleurs des maquettes validées (thème sombre).
abstract final class Palette {
  static const ground = Color(0xFF111614);
  static const card = Color(0xFF1B2420);
  static const cardHigh = Color(0xFF222E29);
  static const line = Color(0xFF2E3D36);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFF9AA8A1);
  static const green = Color(0xFF1F6B4F);
  static const mint = Color(0xFF7FD3A8);
  static const amber = Color(0xFFF2B544);
  static const ink = Color(0xFF13201B);
  static const red = Color(0xFFF28B7A);
  static const blue = Color(0xFF8DB6F2);
  static const grey = Color(0xFF8A948F);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Palette.mint,
      onPrimary: Palette.ink,
      secondary: Palette.amber,
      onSecondary: Palette.ink,
      surface: Palette.card,
      onSurface: Palette.text,
      error: Palette.red,
    ),
    scaffoldBackgroundColor: Palette.ground,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.ground,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Palette.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: Palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.green,
        foregroundColor: Palette.text,
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Palette.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.mint, width: 2),
      ),
      hintStyle: const TextStyle(color: Palette.muted),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Palette.card,
      selectedColor: Palette.amber,
      side: BorderSide(color: Palette.line),
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: Palette.ink,
      ),
      showCheckmark: false,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.cardHigh,
      contentTextStyle: TextStyle(color: Palette.text, fontSize: 15),
    ),
  );
}
