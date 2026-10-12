import 'package:flutter/material.dart';

const bg = Color(0xFF111214);
const surface = Color(0xFF1A1D21);
const surface2 = Color(0xFF252930);
const line = Color(0xFF343A40);
const lime = Color(0xFFD9FF78);
const ink = Color(0xFFF4F5F0);
const muted = Color(0xFFA1A7AE);
const sky = Color(0xFF8FCDEE);
const lavender = Color(0xFFC1B2F8);
const coral = Color(0xFFF4AB8C);

ThemeData pulseTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: bg,
  colorScheme: const ColorScheme.dark(
    primary: lime,
    onPrimary: bg,
    surface: surface,
    onSurface: ink,
    secondary: sky,
    outline: line,
  ),
  fontFamily: 'NotoSansSC',
  useMaterial3: true,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      height: 1.2,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
    ),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, height: 1.5),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5),
    bodySmall: TextStyle(fontSize: 11, height: 1.45, color: muted),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: bg,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  dividerColor: line,
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: lime,
    contentTextStyle: TextStyle(color: bg),
    behavior: SnackBarBehavior.floating,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: surface2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: lime),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: const TextStyle(color: muted, fontSize: 13),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: lime,
      foregroundColor: bg,
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      side: const BorderSide(color: line),
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: lime),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: surface,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  ),
);
