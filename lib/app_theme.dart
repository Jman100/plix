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

class ThemePresetOption {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color card;
  final Color cardBorder;
  final Color cardFocused;
  final bool isGlass;
  final bool isOLED;
  final List<Color> previewGradient;

  const ThemePresetOption({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.card,
    required this.cardBorder,
    required this.cardFocused,
    this.isGlass = false,
    this.isOLED = false,
    required this.previewGradient,
  });
}

class PlixTheme {
  // --- BASE THEME PRESETS ---
  static const List<ThemePresetOption> presetOptions = [
    ThemePresetOption(
      id: 'modern',
      name: 'Plix Modern',
      description: 'Deep obsidian with slate cards and balanced dark contrast',
      icon: Icons.dark_mode_rounded,
      background: Color(0xFF141518),
      surface: Color(0xFF1F2326),
      surfaceLight: Color(0xFF2B3035),
      card: Color(0xFF282A2D),
      cardBorder: Color(0xFF383C40),
      cardFocused: Color(0xFF3A3D42),
      previewGradient: [Color(0xFF141518), Color(0xFF282A2D)],
    ),
    ThemePresetOption(
      id: 'glass',
      name: 'Aero Glass',
      description: 'Translucent frosted glass surfaces with luminous bright edges',
      icon: Icons.blur_on_rounded,
      background: Color(0xFF0D1117),
      surface: Color(0xE6161B26),
      surfaceLight: Color(0xCC212838),
      card: Color(0xDD1B2232),
      cardBorder: Color(0x4DFFFFFF),
      cardFocused: Color(0xF228334C),
      isGlass: true,
      previewGradient: [Color(0xFF0D1117), Color(0xFF20293D), Color(0x66FFFFFF)],
    ),
    ThemePresetOption(
      id: 'oled',
      name: 'OLED Midnight',
      description: 'Pure #000000 true black optimized for OLED displays & contrast',
      icon: Icons.nightlight_round,
      background: Color(0xFF000000),
      surface: Color(0xFF0C0C0D),
      surfaceLight: Color(0xFF161618),
      card: Color(0xFF121214),
      cardBorder: Color(0xFF26262A),
      cardFocused: Color(0xFF202024),
      isOLED: true,
      previewGradient: [Color(0xFF000000), Color(0xFF151518)],
    ),
    ThemePresetOption(
      id: 'cyberpunk',
      name: 'Cyberpunk Neon',
      description: 'High-tech midnight navy with futuristic electric atmosphere',
      icon: Icons.bolt_rounded,
      background: Color(0xFF070A12),
      surface: Color(0xFF0E1322),
      surfaceLight: Color(0xFF161E34),
      card: Color(0xFF12182B),
      cardBorder: Color(0xFF243356),
      cardFocused: Color(0xFF1D2847),
      previewGradient: [Color(0xFF070A12), Color(0xFF18223D)],
    ),
    ThemePresetOption(
      id: 'nord',
      name: 'Nordic Frost',
      description: 'Calming arctic slate inspired by minimalist Scandinavian design',
      icon: Icons.ac_unit_rounded,
      background: Color(0xFF181B20),
      surface: Color(0xFF21252C),
      surfaceLight: Color(0xFF2B313A),
      card: Color(0xFF252B34),
      cardBorder: Color(0xFF38414E),
      cardFocused: Color(0xFF323A46),
      previewGradient: [Color(0xFF181B20), Color(0xFF282F3B)],
    ),
    ThemePresetOption(
      id: 'cinema',
      name: 'Cinema Velvet',
      description: 'Luxurious deep warm wine and velvet undertones of a premier theater',
      icon: Icons.movie_filter_rounded,
      background: Color(0xFF120B10),
      surface: Color(0xFF1B1118),
      surfaceLight: Color(0xFF281924),
      card: Color(0xFF22151F),
      cardBorder: Color(0xFF3B2536),
      cardFocused: Color(0xFF321F2D),
      previewGradient: [Color(0xFF120B10), Color(0xFF291825)],
    ),
  ];

  // --- ACCENT COLOR CHOICES ---
  static const List<ThemeColorOption> colorOptions = [
    ThemeColorOption(
      id: 'orange',
      name: 'Plix Orange',
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
      name: 'Sunset Ember',
      primary: Color(0xFFFF5722),
      light: Color(0xFFFF8A65),
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
      id: 'fuchsia',
      name: 'Hot Fuchsia',
      primary: Color(0xFFFF1493),
      light: Color(0xFFFF69B4),
    ),
    ThemeColorOption(
      id: 'violet',
      name: 'Electric Violet',
      primary: Color(0xFF9D4EDD),
      light: Color(0xFFC77DFF),
    ),
    ThemeColorOption(
      id: 'amethyst',
      name: 'Royal Amethyst',
      primary: Color(0xFF7928CA),
      light: Color(0xFFB800FF),
    ),
    ThemeColorOption(
      id: 'indigo',
      name: 'Electric Indigo',
      primary: Color(0xFF3F51B5),
      light: Color(0xFF7986CB),
    ),
    ThemeColorOption(
      id: 'blue',
      name: 'Sapphire Blue',
      primary: Color(0xFF2979FF),
      light: Color(0xFF82B1FF),
    ),
    ThemeColorOption(
      id: 'cyan',
      name: 'Cyber Cyan',
      primary: Color(0xFF00E5FF),
      light: Color(0xFF84FFFF),
    ),
    ThemeColorOption(
      id: 'frost',
      name: 'Arctic Frost',
      primary: Color(0xFF88C0D0),
      light: Color(0xFFD8DEE9),
    ),
    ThemeColorOption(
      id: 'teal',
      name: 'Seafoam Teal',
      primary: Color(0xFF00897B),
      light: Color(0xFF26A69A),
    ),
    ThemeColorOption(
      id: 'mint',
      name: 'Emerald Mint',
      primary: Color(0xFF00E676),
      light: Color(0xFF69F0AE),
    ),
    ThemeColorOption(
      id: 'platinum',
      name: 'Minimal Platinum',
      primary: Color(0xFFE2E8F0),
      light: Color(0xFFFFFFFF),
    ),
  ];

  static final ValueNotifier<ThemePresetOption> currentPreset =
      ValueNotifier<ThemePresetOption>(presetOptions[0]);

  static final ValueNotifier<ThemeColorOption> currentThemeOption =
      ValueNotifier<ThemeColorOption>(colorOptions[0]);

  static final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);

  // Dynamic Theme Colors
  static Color get background => currentPreset.value.background;
  static Color get surface => currentPreset.value.surface;
  static Color get surfaceLight => currentPreset.value.surfaceLight;
  static Color get card => currentPreset.value.card;
  static Color get cardBorder => currentPreset.value.cardBorder;
  static Color get cardFocused => currentPreset.value.cardFocused;
  static bool get isGlass => currentPreset.value.isGlass;
  static bool get isOLED => currentPreset.value.isOLED;

  static Color get plexGold => currentThemeOption.value.primary;
  static Color get plexGoldLight => currentThemeOption.value.light;
  static Color get focusHighlight => currentThemeOption.value.primary;

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9EA2A8);
  static const Color textMuted = Color(0xFF6B7280);

  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load Base Preset
      final savedPresetId = prefs.getString('app_theme_preset_id');
      if (savedPresetId != null) {
        final matchPreset = presetOptions.firstWhere(
          (p) => p.id == savedPresetId,
          orElse: () => presetOptions[0],
        );
        currentPreset.value = matchPreset;
      }

      // Load Accent Color
      final savedColorId = prefs.getString('app_theme_color_id');
      if (savedColorId != null) {
        if (savedColorId.startsWith('custom_')) {
          final customVal = prefs.getInt('app_theme_custom_color_val');
          if (customVal != null) {
            final col = Color(customVal);
            currentThemeOption.value = ThemeColorOption(
              id: savedColorId,
              name: 'Custom',
              primary: col,
              light: Color.lerp(col, Colors.white, 0.25) ?? col,
            );
          }
        } else {
          final match = colorOptions.firstWhere(
            (opt) => opt.id == savedColorId,
            orElse: () => colorOptions[0],
          );
          currentThemeOption.value = match;
        }
      }
      themeRevision.value++;
    } catch (_) {}
  }

  static Future<void> setPreset(ThemePresetOption preset) async {
    currentPreset.value = preset;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_preset_id', preset.id);
    } catch (_) {}
  }

  static Future<void> setTheme(ThemeColorOption option) async {
    currentThemeOption.value = option;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_color_id', option.id);
    } catch (_) {}
  }

  static Future<void> setCustomColor(Color color, String name) async {
    final customOpt = ThemeColorOption(
      id: 'custom_${color.value.toRadixString(16)}',
      name: name,
      primary: color,
      light: Color.lerp(color, Colors.white, 0.25) ?? color,
    );
    currentThemeOption.value = customOpt;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_color_id', customOpt.id);
      await prefs.setInt('app_theme_custom_color_val', color.value);
    } catch (_) {}
  }

  static ThemeData get themeData {
    final primary = currentThemeOption.value.primary;
    final secondary = currentThemeOption.value.light;
    final bg = background;
    final surf = surface;
    final crd = card;

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surf,
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
      cardColor: crd,
    );
  }
}
