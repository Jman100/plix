import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/profile_service.dart';
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
  final String defaultAccentId;
  final bool isGlass;
  final bool isOLED;
  final bool isCyberpunk;
  final bool isMatrix;
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
    required this.defaultAccentId,
    this.isGlass = false,
    this.isOLED = false,
    this.isCyberpunk = false,
    this.isMatrix = false,
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
      background: Color(0xFF121316),
      surface: Color(0xFF1B1D22),
      surfaceLight: Color(0xFF262930),
      card: Color(0xFF22252C),
      cardBorder: Color(0xFF333742),
      cardFocused: Color(0xFF2F3440),
      defaultAccentId: 'gold',
      previewGradient: [Color(0xFF121316), Color(0xFF22252C)],
    ),
    ThemePresetOption(
      id: 'glass',
      name: 'Liquid Glass',
      description: 'Ultra-clear crystal glass with specular sheen and luminous refractive edges',
      icon: Icons.blur_on_rounded,
      background: Color(0xFF070B14),
      surface: Color(0x18FFFFFF),
      surfaceLight: Color(0x28FFFFFF),
      card: Color(0x15FFFFFF),
      cardBorder: Color(0x3DFFFFFF),
      cardFocused: Color(0x35FFFFFF),
      defaultAccentId: 'frost',
      isGlass: true,
      previewGradient: [Color(0xFF091120), Color(0x30FFFFFF), Color(0x80FFFFFF)],
    ),
    ThemePresetOption(
      id: 'oled',
      name: 'OLED Midnight',
      description: 'True #000000 pure black on all surfaces, sidebar, buttons, and cards',
      icon: Icons.nightlight_round,
      background: Color(0xFF000000),
      surface: Color(0xFF000000),
      surfaceLight: Color(0xFF080808),
      card: Color(0xFF000000),
      cardBorder: Color(0xFF242428),
      cardFocused: Color(0xFF141418),
      defaultAccentId: 'gold',
      isOLED: true,
      previewGradient: [Color(0xFF000000), Color(0xFF101014)],
    ),
    ThemePresetOption(
      id: 'cyberpunk',
      name: 'Cyberpunk Neon',
      description: 'Electric synthwave void with vivid neon magenta and cyan atmosphere',
      icon: Icons.bolt_rounded,
      background: Color(0xFF070312),
      surface: Color(0xFF0F0624),
      surfaceLight: Color(0xFF180A38),
      card: Color(0xFF160830),
      cardBorder: Color(0x80FF007F),
      cardFocused: Color(0xFF240E4A),
      defaultAccentId: 'cyan',
      isCyberpunk: true,
      previewGradient: [Color(0xFF070312), Color(0xFF28084A), Color(0xFFFF007F)],
    ),
    ThemePresetOption(
      id: 'matrix',
      name: 'Emerald Matrix',
      description: 'Deep cyber terminal with vibrant phosphor matrix emerald accents',
      icon: Icons.terminal_rounded,
      background: Color(0xFF020B05),
      surface: Color(0xFF05170B),
      surfaceLight: Color(0xFF0A2613),
      card: Color(0xFF081E0F),
      cardBorder: Color(0x6600FF66),
      cardFocused: Color(0xFF0E3018),
      defaultAccentId: 'mint',
      isMatrix: true,
      previewGradient: [Color(0xFF020B05), Color(0xFF082E14), Color(0xFF00FF66)],
    ),
    ThemePresetOption(
      id: 'nord',
      name: 'Nordic Frost',
      description: 'Arctic fjord slate with cool ice blue tones and Scandinavian minimalism',
      icon: Icons.ac_unit_rounded,
      background: Color(0xFF0D1219),
      surface: Color(0xFF151D28),
      surfaceLight: Color(0xFF1D2838),
      card: Color(0xFF192330),
      cardBorder: Color(0xFF2E3E54),
      cardFocused: Color(0xFF223044),
      defaultAccentId: 'frost',
      previewGradient: [Color(0xFF0D1219), Color(0xFF1E2E44)],
    ),
    ThemePresetOption(
      id: 'cinema',
      name: 'Cinema Velvet',
      description: 'Luxurious royal cabernet theater with deep warm wine undertones',
      icon: Icons.movie_filter_rounded,
      background: Color(0xFF100308),
      surface: Color(0xFF1A060E),
      surfaceLight: Color(0xFF270A16),
      card: Color(0xFF220813),
      cardBorder: Color(0xFF421226),
      cardFocused: Color(0xFF2E0C1B),
      defaultAccentId: 'crimson',
      previewGradient: [Color(0xFF100308), Color(0xFF2D0A1B)],
    ),
    ThemePresetOption(
      id: 'vaporwave',
      name: 'Sunset Vaporwave',
      description: '80s dusk twilight with warm sunset ember and retro synth aesthetics',
      icon: Icons.wb_twilight_rounded,
      background: Color(0xFF12061C),
      surface: Color(0xFF1D0B2E),
      surfaceLight: Color(0xFF2A1142),
      card: Color(0xFF250E3A),
      cardBorder: Color(0xFF4C1D74),
      cardFocused: Color(0xFF331450),
      defaultAccentId: 'sunset',
      previewGradient: [Color(0xFF12061C), Color(0xFF33104E), Color(0xFFFF5722)],
    ),
    ThemePresetOption(
      id: 'nebula',
      name: 'Cosmic Nebula',
      description: 'Galactic interstellar deep space with celestial violet and star-cluster glow',
      icon: Icons.auto_awesome_rounded,
      background: Color(0xFF090514),
      surface: Color(0xFF130A24),
      surfaceLight: Color(0xFF1C1034),
      card: Color(0xFF180D2E),
      cardBorder: Color(0xFF381F66),
      cardFocused: Color(0xFF241445),
      defaultAccentId: 'amethyst',
      previewGradient: [Color(0xFF090514), Color(0xFF261047), Color(0xFF9C27B0)],
    ),
    ThemePresetOption(
      id: 'solar',
      name: 'Solar Flare',
      description: 'Volcanic magma obsidian with radiant stellar plasma and warm ember glow',
      icon: Icons.local_fire_department_rounded,
      background: Color(0xFF120702),
      surface: Color(0xFF1F0C04),
      surfaceLight: Color(0xFF2D1307),
      card: Color(0xFF281005),
      cardBorder: Color(0xFF5A240A),
      cardFocused: Color(0xFF3B1808),
      defaultAccentId: 'amber',
      previewGradient: [Color(0xFF120702), Color(0xFF3B1405), Color(0xFFFF9800)],
    ),
    ThemePresetOption(
      id: 'tokyo',
      name: 'Tokyo Midnight',
      description: 'Rain-slicked asphalt metropolis with electric cherry blossom and neon city glow',
      icon: Icons.nightlife_rounded,
      background: Color(0xFF080C14),
      surface: Color(0xFF0E1624),
      surfaceLight: Color(0xFF162136),
      card: Color(0xFF121B2C),
      cardBorder: Color(0xFF253757),
      cardFocused: Color(0xFF1A273F),
      defaultAccentId: 'fuchsia',
      previewGradient: [Color(0xFF080C14), Color(0xFF1A1A36), Color(0xFFE91E63)],
    ),
    ThemePresetOption(
      id: 'abyss',
      name: 'Abyssal Depth',
      description: 'Midnight oceanic trench with luminous sapphire and deep bioluminescent cyan photophores',
      icon: Icons.waves_rounded,
      background: Color(0xFF030813),
      surface: Color(0xFF061324),
      surfaceLight: Color(0xFF0C1E36),
      card: Color(0xFF08182D),
      cardBorder: Color(0xFF13365E),
      cardFocused: Color(0xFF0F2648),
      defaultAccentId: 'cyan',
      previewGradient: [Color(0xFF030813), Color(0xFF072140), Color(0xFF00E5FF)],
    ),
    ThemePresetOption(
      id: 'aurora',
      name: 'Borealis Aurora',
      description: 'Arctic night sky illuminated by dancing emerald and ultraviolet solar ribbons',
      icon: Icons.filter_vintage_rounded,
      background: Color(0xFF040A0C),
      surface: Color(0xFF081519),
      surfaceLight: Color(0xFF0E2228),
      card: Color(0xFF0B1C22),
      cardBorder: Color(0xFF1A444E),
      cardFocused: Color(0xFF13323C),
      defaultAccentId: 'mint',
      previewGradient: [Color(0xFF040A0C), Color(0xFF0A2B24), Color(0xFF00FFA3)],
    ),
    ThemePresetOption(
      id: 'dune',
      name: 'Desert Mirage',
      description: 'Starlit dunes with warm spiced saffron, sun-baked obsidian, and golden bronze sands',
      icon: Icons.landscape_rounded,
      background: Color(0xFF110B06),
      surface: Color(0xFF1C130A),
      surfaceLight: Color(0xFF2B1D10),
      card: Color(0xFF24180E),
      cardBorder: Color(0xFF54381E),
      cardFocused: Color(0xFF382515),
      defaultAccentId: 'gold',
      previewGradient: [Color(0xFF110B06), Color(0xFF35200C), Color(0xFFE5A00D)],
    ),
    ThemePresetOption(
      id: 'royal',
      name: 'Imperial Amethyst',
      description: 'Opulent Byzantine obsidian with deep regal jewel-toned velvet and royal amethyst',
      icon: Icons.diamond_rounded,
      background: Color(0xFF0A0512),
      surface: Color(0xFF140A22),
      surfaceLight: Color(0xFF1E1033),
      card: Color(0xFF190D2C),
      cardBorder: Color(0xFF40206D),
      cardFocused: Color(0xFF281446),
      defaultAccentId: 'amethyst',
      previewGradient: [Color(0xFF0A0512), Color(0xFF260E3F), Color(0xFFBA68C8)],
    ),
    ThemePresetOption(
      id: 'custom',
      name: 'Custom Theme',
      description: 'Fully personalized colors: customize background, sidebar, cards, and border',
      icon: Icons.tune_rounded,
      background: Color(0xFF121316),
      surface: Color(0xFF1B1D22),
      surfaceLight: Color(0xFF262930),
      card: Color(0xFF22252C),
      cardBorder: Color(0xFF333742),
      cardFocused: Color(0xFF2F3440),
      defaultAccentId: 'gold',
      previewGradient: [Color(0xFF1B1D22), Color(0xFF333742), Color(0xFFE5A00D)],
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
      ValueNotifier<ThemeColorOption>(colorOptions[1]); // Classic Gold

  static final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);

  // Custom theme user-configured colors
  static Color _customBackground = const Color(0xFF121316);
  static Color _customSurface = const Color(0xFF1B1D22);
  static Color _customCard = const Color(0xFF22252C);
  static Color _customBorder = const Color(0xFF333742);

  static Color get customBackground => _customBackground;
  static Color get customSurface => _customSurface;
  static Color get customCard => _customCard;
  static Color get customBorder => _customBorder;

  // Dynamic Theme Colors
  static Color get background => currentPreset.value.id == 'custom'
      ? _customBackground
      : currentPreset.value.background;

  static Color get surface => currentPreset.value.id == 'custom'
      ? _customSurface
      : currentPreset.value.surface;

  static Color get surfaceLight => currentPreset.value.id == 'custom'
      ? Color.lerp(_customSurface, Colors.white, 0.1) ?? _customSurface
      : currentPreset.value.surfaceLight;

  static Color get card => currentPreset.value.id == 'custom'
      ? _customCard
      : currentPreset.value.card;

  static Color get cardBorder => currentPreset.value.id == 'custom'
      ? _customBorder
      : currentPreset.value.cardBorder;

  static Color get cardFocused => currentPreset.value.id == 'custom'
      ? Color.lerp(_customCard, Colors.white, 0.15) ?? _customCard
      : currentPreset.value.cardFocused;

  static bool get isGlass => currentPreset.value.isGlass;
  static bool get isOLED => currentPreset.value.isOLED;
  static bool get isCyberpunk => currentPreset.value.isCyberpunk;
  static bool get isMatrix => currentPreset.value.isMatrix;

  static Color get plexGold => currentThemeOption.value.primary;
  static Color get plexGoldLight => currentThemeOption.value.light;
  static Color get focusHighlight => currentThemeOption.value.primary;

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9EA2A8);
  static const Color textMuted = Color(0xFF6B7280);

  /// Generates Apple Liquid Glass decoration with specular highlights and reflections
  static BoxDecoration glassBoxDecoration({
    BorderRadius? borderRadius,
    bool isHighlighted = false,
    Color? accent,
    double borderWidth = 1.2,
  }) {
    final effectiveAccent = accent ?? plexGold;
    return BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(10),
      gradient: LinearGradient(
        begin: const Alignment(-0.8, -1.0),
        end: const Alignment(0.8, 1.0),
        colors: isHighlighted
            ? [
                Colors.white.withOpacity(0.24),
                effectiveAccent.withOpacity(0.18),
                Colors.white.withOpacity(0.08),
              ]
            : [
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
      ),
      border: Border.all(
        color: isHighlighted
            ? Colors.white.withOpacity(0.92)
            : Colors.white.withOpacity(0.32),
        width: isHighlighted ? borderWidth + 0.6 : borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: isHighlighted
              ? effectiveAccent.withOpacity(0.40)
              : Colors.black.withOpacity(0.25),
          blurRadius: isHighlighted ? 16 : 8,
          spreadRadius: isHighlighted ? 1.0 : 0,
          offset: isHighlighted ? Offset.zero : const Offset(0, 2),
        ),
        if (isHighlighted)
          BoxShadow(
            color: Colors.white.withOpacity(0.30),
            blurRadius: 8,
            spreadRadius: -1,
          ),
      ],
    );
  }

  /// Apple-style specular gloss reflection sweep layer
  static Widget buildGlassReflectionLayer({BorderRadius? borderRadius}) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: const Alignment(-0.85, -1.0),
              end: const Alignment(0.85, 1.0),
              stops: const [0.0, 0.32, 0.33, 1.0],
              colors: [
                Colors.white.withOpacity(0.20),
                Colors.white.withOpacity(0.04),
                Colors.transparent,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void resetToDefaultModern() {
    currentPreset.value = presetOptions[0]; // Plix Modern
    currentThemeOption.value = colorOptions[1]; // Classic Gold
    _customBackground = const Color(0xFF121316);
    _customSurface = const Color(0xFF1B1D22);
    _customCard = const Color(0xFF22252C);
    _customBorder = const Color(0xFF333742);
    themeRevision.value++;
  }

  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final pKeyPreset = ProfileService.key('app_theme_preset_id');
      final savedPresetId = prefs.getString(pKeyPreset);
      if (savedPresetId != null) {
        final matchPreset = presetOptions.firstWhere(
          (p) => p.id == savedPresetId,
          orElse: () => presetOptions[0],
        );
        currentPreset.value = matchPreset;
      } else {
        currentPreset.value = presetOptions[0]; // Plix Modern
      }

      // Load Custom Theme Colors
      final customBgVal = prefs.getInt(ProfileService.key('app_theme_custom_bg'));
      if (customBgVal != null) _customBackground = Color(customBgVal);
      final customSurfVal = prefs.getInt(ProfileService.key('app_theme_custom_surf'));
      if (customSurfVal != null) _customSurface = Color(customSurfVal);
      final customCardVal = prefs.getInt(ProfileService.key('app_theme_custom_card'));
      if (customCardVal != null) _customCard = Color(customCardVal);
      final customBorderVal = prefs.getInt(ProfileService.key('app_theme_custom_border'));
      if (customBorderVal != null) _customBorder = Color(customBorderVal);

      // Load Accent Color
      final savedColorId = prefs.getString(ProfileService.key('app_theme_color_id'));
      if (savedColorId != null) {
        if (savedColorId.startsWith('custom_')) {
          final customVal = prefs.getInt(ProfileService.key('app_theme_custom_color_val'));
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
            orElse: () => colorOptions[1], // Classic Gold default
          );
          currentThemeOption.value = match;
        }
      } else {
        currentThemeOption.value = colorOptions[1]; // Classic Gold default
      }
      themeRevision.value++;
    } catch (_) {}
  }

  static Future<void> setPreset(ThemePresetOption preset, {bool updateDefaultAccent = true}) async {
    currentPreset.value = preset;
    
    // Automatically default to an appropriate accent highlight color for that theme
    if (updateDefaultAccent) {
      final defaultAccent = colorOptions.firstWhere(
        (c) => c.id == preset.defaultAccentId,
        orElse: () => colorOptions[1],
      );
      currentThemeOption.value = defaultAccent;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(ProfileService.key('app_theme_color_id'), defaultAccent.id);
      } catch (_) {}
    }

    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ProfileService.key('app_theme_preset_id'), preset.id);
    } catch (_) {}
  }

  static Future<void> updateCustomTheme({
    Color? background,
    Color? surface,
    Color? card,
    Color? border,
  }) async {
    if (background != null) _customBackground = background;
    if (surface != null) _customSurface = surface;
    if (card != null) _customCard = card;
    if (border != null) _customBorder = border;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (background != null) await prefs.setInt(ProfileService.key('app_theme_custom_bg'), background.value);
      if (surface != null) await prefs.setInt(ProfileService.key('app_theme_custom_surf'), surface.value);
      if (card != null) await prefs.setInt(ProfileService.key('app_theme_custom_card'), card.value);
      if (border != null) await prefs.setInt(ProfileService.key('app_theme_custom_border'), border.value);
    } catch (_) {}

    // Ensure Custom Preset is active
    final customPreset = presetOptions.firstWhere((p) => p.id == 'custom');
    if (currentPreset.value.id != 'custom') {
      await setPreset(customPreset, updateDefaultAccent: false);
    } else {
      themeRevision.value++;
    }
  }

  static Future<void> setTheme(ThemeColorOption option) async {
    currentThemeOption.value = option;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ProfileService.key('app_theme_color_id'), option.id);
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
      await prefs.setString(ProfileService.key('app_theme_color_id'), customOpt.id);
      await prefs.setInt(ProfileService.key('app_theme_custom_color_val'), color.value);
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
