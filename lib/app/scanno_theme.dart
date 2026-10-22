import 'package:flutter/material.dart';

final scannoTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF285B4B),
    surface: const Color(0xFFF8FAF8),
  ),
  scaffoldBackgroundColor: const Color(0xFFF8FAF8),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF8FAF8),
    surfaceTintColor: Colors.transparent,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE3EAE5)),
    ),
  ),
);
