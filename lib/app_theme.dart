import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeColorOption {
  final String id;
  final String name;
  final Color primary;
  final Color light;

  const ThemeColorOption({
    required this.id,
    required this.name,
    required this.primary,
    required this.light,
  });
}

class PlixTheme {
  static const List<ThemeColorOption> colorOptions = [
    ThemeColorOption(
      id: 'orange',
      name: 'Jman100 Orange',
      primary: Color(0xFFE55B13),
      light: Color(0xFFFF7A2F),
    ),
    ThemeColorOption(
      id: 'gold',
      name: 'Classic Gold',
      primary: Color(0xFFE5A00D),
      light: Color(0xFFF5B82E),
    ),
    ThemeColorOption(
      id: 'amber',
      name: 'Warm Amber',
      primary: Color(0xFFFFB300),
      light: Color(0xFFFFCA28),
    ),
    ThemeColorOption(
      id: 'sunset',
      name: 'Sunset Orange',
      primary: Color(0xFFFF6D00),
      light: Color(0xFFFF9E40),
    ),
    ThemeColorOption(
      id: 'crimson',
      name: 'Crimson Red',
      primary: Color(0xFFE53935),
      light: Color(0xFFEF5350),
    ),
    ThemeColorOption(
      id: 'ruby',
      name: 'Deep Ruby',
      primary: Color(0xFFC2185B),
      light: Color(0xFFE91E63),
    ),
    ThemeColorOption(
      id: 'pink',
      name: 'Vibrant Pink',
      primary: Color(0xFFEC407A),
      light: Color(0xFFF48FB1),
    ),
    ThemeColorOption(
      id: 'purple',
      name: 'Neon Purple',
      primary: Color(0xFF8E24AA),
      light: Color(0xFFAB47BC),
    ),
    ThemeColorOption(
      id: 'deep_purple',
      name: 'Royal Violet',
      primary: Color(0xFF673AB7),
      light: Color(0xFF9575CD),
    ),
    ThemeColorOption(
      id: 'indigo',
      name: 'Electric Indigo',
      primary: Color(0xFF3F51B5),
      light: Color(0xFF7986CB),
    ),
    ThemeColorOption(
      id: 'blue',
      name: 'Electric Blue',
      primary: Color(0xFF1E88E5),
      light: Color(0xFF42A5F5),
    ),
    ThemeColorOption(
      id: 'cyan',
      name: 'Vivid Cyan',
      primary: Color(0xFF00ACC1),
      light: Color(0xFF26C6DA),
    ),
    ThemeColorOption(
      id: 'teal',
      name: 'Seafoam Teal',
      primary: Color(0xFF00897B),
      light: Color(0xFF26A69A),
    ),
    ThemeColorOption(
      id: 'green',
      name: 'Emerald Green',
      primary: Color(0xFF43A047),
      light: Color(0xFF66BB6A),
    ),
    ThemeColorOption(
      id: 'lime',
      name: 'Lime Glow',
      primary: Color(0xFF7CB342),
      light: Color(0xFF9CCC65),
    ),
  ];

  static final ValueNotifier<ThemeColorOption> currentThemeOption =
      ValueNotifier<ThemeColorOption>(colorOptions[0]);

  static Color get plexGold => currentThemeOption.value.primary;
  static Color get plexGoldLight => currentThemeOption.value.light;
  static Color get focusHighlight => currentThemeOption.value.primary;

  static const Color background = Color(0xFF141518);
  static const Color surface = Color(0xFF1F2326);
  static const Color surfaceLight = Color(0xFF2B3035);
  static const Color card = Color(0xFF282A2D);
  static const Color cardBorder = Color(0xFF383C40);
  static const Color cardFocused = Color(0xFF3A3D42);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9EA2A8);
  static const Color textMuted = Color(0xFF6B7280);

  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('app_theme_color_id');
      if (savedId != null) {
        final match = colorOptions.firstWhere(
          (opt) => opt.id == savedId,
          orElse: () => colorOptions[0],
        );
        currentThemeOption.value = match;
      }
    } catch (_) {}
  }

  static Future<void> setTheme(ThemeColorOption option) async {
    currentThemeOption.value = option;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_color_id', option.id);
    } catch (_) {}
  }

  static ThemeData get themeData {
    final primary = currentThemeOption.value.primary;
    final secondary = currentThemeOption.value.light;

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onPrimary: Colors.black,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      focusColor: primary.withOpacity(0.35),
      cardTheme: CardTheme(
        color: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
