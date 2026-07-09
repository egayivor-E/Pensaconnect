// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _themeModeKey = 'theme_mode';

  // Default to system theme
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    // ✅ FIX: load any previously saved preference on startup instead of
    // always resetting to ThemeMode.system.
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeModeKey);
      if (saved != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == saved,
          orElse: () => ThemeMode.system,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ThemeProvider: failed to load saved theme mode: $e');
      // Fall back silently to ThemeMode.system - not worth surfacing to the user.
    }
  }

  Future<void> _persistThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (e) {
      debugPrint('ThemeProvider: failed to persist theme mode: $e');
    }
  }

  // Set a specific theme mode
  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    // ✅ FIX: persist so the choice survives app restarts.
    _persistThemeMode(mode);
  }

  // Toggle dark mode on/off
  void toggleDarkMode(bool isDark) {
    setTheme(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  // Alias for SettingsScreen compatibility
  void toggleTheme(bool isDark) {
    toggleDarkMode(isDark);
  }

  // ✅ FIX: resolves whether dark mode is actually active right now,
  // accounting for ThemeMode.system - checking `themeMode == ThemeMode.dark`
  // alone reports "off" even when the system is in dark mode and the app
  // is visibly rendering dark.
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
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
