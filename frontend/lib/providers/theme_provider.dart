// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  // Default to system theme
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  // Set a specific theme mode
  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  // Toggle dark mode on/off
  void toggleDarkMode(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  // Alias for SettingsScreen compatibility
  void toggleTheme(bool isDark) {
    toggleDarkMode(isDark);
  }

  // Build ThemeData dynamically based on brightness
  ThemeData getThemeData(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primaryColor = isDark ? Colors.deepPurple[300]! : Colors.deepPurple;
    final secondaryColor = isDark ? Colors.teal[200]! : Colors.teal;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        primary: primaryColor,
        secondary: secondaryColor,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        margin: const EdgeInsets.all(8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: MaterialStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
