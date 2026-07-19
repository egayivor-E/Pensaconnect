// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_style.dart';

class ThemeProvider extends ChangeNotifier {
  static const _themeModeKey = 'theme_mode';

  // Default to system theme
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    // Load any previously saved preference on startup instead of
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

  // Resolves whether dark mode is actually active right now, accounting
  // for ThemeMode.system.
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  // Build ThemeData dynamically based on brightness, using the
  // PensaConnect "golden hour fellowship" brand tokens.
  ThemeData getThemeData(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // ⚠️ IMPORTANT: M3 surface-container roles are NOT auto-derived from
    // `surface` the way you might expect from a tonal palette — when left
    // unset, ColorScheme's getter falls straight back to `surface` itself:
    //   Color get surfaceContainerHighest => _surfaceContainerHighest ?? surface;
    // Since light-mode `surface` here is plain `Colors.white`, leaving
    // `surfaceContainerHighest` unset made it resolve to white too. Every
    // "no avatar" / "avatar failed to load" placeholder in the app (see
    // widgets/user_avatar.dart) paints a white person-icon on top of that
    // color, so in light mode it rendered as a blank white-on-white circle
    // — avatars looked broken/missing even though the widget itself was
    // working fine. Setting these explicitly, distinct from `surface`,
    // fixes every screen that reads them in one place.
    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.emberGold,
            onPrimary: AppColors.deepDusk,
            secondary: AppColors.verdantSage,
            onSecondary: Colors.white,
            tertiary: AppColors.roseQuartz,
            onTertiary: AppColors.deepDusk,
            surface: Color(0xFF2A2340),
            onSurface: AppColors.warmLinen,
            surfaceContainerHighest: Color(0xFF332A4D),
            onSurfaceVariant: AppColors.warmLinen,
            error: Color(0xFFE5726A),
            onError: Colors.white,
          )
        : const ColorScheme.light(
            primary: AppColors.emberGold,
            onPrimary: Colors.white,
            secondary: AppColors.verdantSage,
            onSecondary: Colors.white,
            tertiary: AppColors.roseQuartz,
            onTertiary: AppColors.inkDusk,
            surface: Colors.white,
            onSurface: AppColors.inkDusk,
            surfaceContainerHighest: AppColors.warmLinen,
            onSurfaceVariant: AppColors.inkDusk,
            error: Color(0xFFC94C40),
            onError: Colors.white,
          );

    final baseTextTheme = isDark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    // Fraunces (warm display serif) for headings, Manrope (clean
    // geometric sans) for body/UI text.
    final textTheme = GoogleFonts.manropeTextTheme(baseTextTheme).copyWith(
      displayLarge: GoogleFonts.fraunces(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        height: 1.1,
      ),
      displayMedium: GoogleFonts.fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        height: 1.15,
      ),
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineSmall: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 16,
        color: colorScheme.onSurface,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        color: colorScheme.onSurface,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.deepDusk
          : AppColors.warmLinen,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF2A2340) : Colors.white,
        margin: const EdgeInsets.all(8),
        shape: AppShapes.archBorder(),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 2,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        shape: AppShapes.pill,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: AppShapes.pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.secondary,
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF332A4D) : AppColors.warmLinen,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: GoogleFonts.manrope(
          color: colorScheme.onSurface.withOpacity(0.65),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF332A4D) : AppColors.warmLinen,
        labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
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
