import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/profile_service.dart';
class ThemeColorOption {
  final String id;
  final String name;
  final Color primary;
  final Color light;
  final bool isRainbow;

  const ThemeColorOption({
    required this.id,
    required this.name,
    required this.primary,
    required this.light,
    this.isRainbow = false,
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
  final bool isRainbow;
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
    this.isRainbow = false,
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
      defaultAccentId: 'crimson',
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
      defaultAccentId: 'gold',
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
      id: 'rainbow',
      name: 'Prism Rainbow',
      description: 'Luminous rainbow accents and buttons with deep nebula atmosphere',
      icon: Icons.looks_rounded,
      background: Color(0xFF090514),
      surface: Color(0xFF130A24),
      surfaceLight: Color(0xFF1C1034),
      card: Color(0xFF180D2E),
      cardBorder: Color(0xFF381F66),
      cardFocused: Color(0xFF241445),
      defaultAccentId: 'rainbow',
      isRainbow: true,
      previewGradient: [
        Color(0xFFFF007A),
        Color(0xFF7928CA),
        Color(0xFF0070F3),
        Color(0xFF00E676),
        Color(0xFFFFB300),
      ],
    ),
    ThemePresetOption(
      id: 'sakura',
      name: 'Sakura Blossom',
      description: 'Ethereal midnight with blooming cherry petal pink and soft magenta undertones',
      icon: Icons.local_florist_rounded,
      background: Color(0xFF0F060E),
      surface: Color(0xFF1A0A19),
      surfaceLight: Color(0xFF261025),
      card: Color(0xFF200D1F),
      cardBorder: Color(0xFF4C1848),
      cardFocused: Color(0xFF2E132D),
      defaultAccentId: 'fuchsia',
      previewGradient: [Color(0xFF0F060E), Color(0xFF2B0A28), Color(0xFFFF69B4)],
    ),
    ThemePresetOption(
      id: 'glacier',
      name: 'Glacier Titanium',
      description: 'Crisp arctic permafrost with cool brushed titanium and crystalline silver-blue slate',
      icon: Icons.terrain_rounded,
      background: Color(0xFF080D12),
      surface: Color(0xFF101720),
      surfaceLight: Color(0xFF182330),
      card: Color(0xFF141D28),
      cardBorder: Color(0xFF2A3C52),
      cardFocused: Color(0xFF1C2838),
      defaultAccentId: 'frost',
      previewGradient: [Color(0xFF080D12), Color(0xFF162536), Color(0xFFB0C4DE)],
    ),
    ThemePresetOption(
      id: 'eclipse',
      name: 'Crimson Eclipse',
      description: 'Ominous lunar shadow with charred obsidian and incandescent scarlet aura',
      icon: Icons.brightness_3_rounded,
      background: Color(0xFF0E0406),
      surface: Color(0xFF17080A),
      surfaceLight: Color(0xFF240D10),
      card: Color(0xFF1E0B0D),
      cardBorder: Color(0xFF4A141A),
      cardFocused: Color(0xFF2B1013),
      defaultAccentId: 'crimson',
      previewGradient: [Color(0xFF0E0406), Color(0xFF33090F), Color(0xFFFF1744)],
    ),
    ThemePresetOption(
      id: 'horizon',
      name: 'Golden Horizon',
      description: 'Sunset savannah twilight with warm espresso obsidian and radiant champagne gold',
      icon: Icons.wb_sunny_rounded,
      background: Color(0xFF0E0B07),
      surface: Color(0xFF19130D),
      surfaceLight: Color(0xFF261D14),
      card: Color(0xFF211810),
      cardBorder: Color(0xFF4D3824),
      cardFocused: Color(0xFF2E2217),
      defaultAccentId: 'gold',
      previewGradient: [Color(0xFF0E0B07), Color(0xFF2E1F10), Color(0xFFFFD700)],
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
      name: 'Orange',
      primary: Color(0xFFE55B13),
      light: Color(0xFFFF7A2F),
    ),
    ThemeColorOption(
      id: 'gold',
      name: 'Gold',
      primary: Color(0xFFE5A00D),
      light: Color(0xFFF5B82E),
    ),
    ThemeColorOption(
      id: 'crimson',
      name: 'Crimson',
      primary: Color(0xFFE53935),
      light: Color(0xFFEF5350),
    ),
    ThemeColorOption(
      id: 'ruby',
      name: 'Ruby',
      primary: Color(0xFFC2185B),
      light: Color(0xFFE91E63),
    ),
    ThemeColorOption(
      id: 'fuchsia',
      name: 'Fuchsia',
      primary: Color(0xFFFF1493),
      light: Color(0xFFFF69B4),
    ),
    ThemeColorOption(
      id: 'amethyst',
      name: 'Amethyst',
      primary: Color(0xFF7928CA),
      light: Color(0xFFB800FF),
    ),
    ThemeColorOption(
      id: 'indigo',
      name: 'Indigo',
      primary: Color(0xFF3F51B5),
      light: Color(0xFF7986CB),
    ),
    ThemeColorOption(
      id: 'blue',
      name: 'Blue',
      primary: Color(0xFF2979FF),
      light: Color(0xFF82B1FF),
    ),
    ThemeColorOption(
      id: 'cyan',
      name: 'Cyan',
      primary: Color(0xFF00E5FF),
      light: Color(0xFF84FFFF),
    ),
    ThemeColorOption(
      id: 'frost',
      name: 'Frost',
      primary: Color(0xFF88C0D0),
      light: Color(0xFFD8DEE9),
    ),
    ThemeColorOption(
      id: 'teal',
      name: 'Teal',
      primary: Color(0xFF00897B),
      light: Color(0xFF26A69A),
    ),
    ThemeColorOption(
      id: 'mint',
      name: 'Mint',
      primary: Color(0xFF00E676),
      light: Color(0xFF69F0AE),
    ),
    ThemeColorOption(
      id: 'green',
      name: 'Green',
      primary: Color(0xFF00FF00),
      light: Color(0xFF66FF66),
    ),
    ThemeColorOption(
      id: 'platinum',
      name: 'Platinum',
      primary: Color(0xFFE2E8F0),
      light: Color(0xFFFFFFFF),
    ),
    ThemeColorOption(
      id: 'rainbow',
      name: 'Rainbow',
      primary: Color(0xFFFFFFFF),
      light: Color(0xFF00E676),
      isRainbow: true,
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
  static bool get isRainbow => currentPreset.value.isRainbow;

  /// Background decoration respecting themes
  static BoxDecoration get backgroundDecoration => BoxDecoration(color: background);

  /// Vibrant rainbow gradient used for focused cursor outlines, active highlights, and vivid swatches
  static const LinearGradient vividRainbowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF007A), // vivid rose/pink
      Color(0xFF9D4EDD), // vivid violet
      Color(0xFF0070F3), // electric blue
      Color(0xFF00E676), // bright neon green
      Color(0xFFFFB300), // amber gold
    ],
  );

  /// Standard rainbow gradient for accent swatches
  static const LinearGradient rainbowAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFD81B60),
      Color(0xFF7B1FA2),
      Color(0xFF1976D2),
      Color(0xFF00897B),
      Color(0xFFF57F17),
    ],
  );

  /// Darker, more subtle rainbow gradient used for buttons when the Prism Rainbow theme is active
  static const LinearGradient rainbowButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF5A1032), // dark subtle rose
      Color(0xFF32134D), // deep subtle violet
      Color(0xFF102446), // deep midnight blue
      Color(0xFF0D3B24), // deep forest emerald
      Color(0xFF4D3308), // dark subtle amber bronze
    ],
  );

  /// Button transparency alpha for level 1 (barely transparent) to 5 (crystal clear)
  static int get glassButtonAlpha {
    final lvl = glassSidebarLevel.value.clamp(1, 5);
    const alphaMap = <int, int>{
      1: 0xF0, // Level 1 (barely transparent, ~94% opaque)
      2: 0xC0, // Level 2 (~75% opaque)
      3: 0x88, // Level 3 (~53% opaque)
      4: 0x50, // Level 4 (~31% opaque)
      5: 0x22, // Level 5 (~13% opaque, crystal clear)
    };
    return alphaMap[lvl] ?? 0x50;
  }

  /// Global toggle for semi-transparent translucent liquid glass left navigation sidebar
  static final ValueNotifier<bool> glassSidebar = ValueNotifier<bool>(true);
  static bool get isGlassSidebar => glassSidebar.value;

  /// Toggle for background frosted blur on the translucent liquid glass sidebar (5% to 40% blur)
  static final ValueNotifier<bool> glassSidebarBlur = ValueNotifier<bool>(true);
  static bool get isGlassSidebarBlur => glassSidebarBlur.value;

  /// Blur level for the glass sidebar: 1 (5%), 2 (10%), 3 (20%), 4 (30%), 5 (40%). Default is 2 (10%).
  static final ValueNotifier<int> glassSidebarBlurLevel = ValueNotifier<int>(2);
  static int get isGlassSidebarBlurLevel => glassSidebarBlurLevel.value;

  static const Map<int, int> _blurPercentMap = {
    1: 5,
    2: 10,
    3: 20,
    4: 30,
    5: 40,
  };

  static const Map<int, double> _blurSigmaMap = {
    1: 1.25,
    2: 2.5,
    3: 5.0,
    4: 7.5,
    5: 10.0,
  };

  static int get glassSidebarBlurPercent =>
      _blurPercentMap[glassSidebarBlurLevel.value.clamp(1, 5)] ?? 10;

  static double get glassSidebarBlurSigma =>
      _blurSigmaMap[glassSidebarBlurLevel.value.clamp(1, 5)] ?? 2.5;

  /// Transparency level for the glass sidebar and profile menu: 1 (barely transparent/opaque) to 5 (crystal clear/transparent). Default is 4.
  static final ValueNotifier<int> glassSidebarLevel = ValueNotifier<int>(4);
  static int get isGlassSidebarLevel => glassSidebarLevel.value;

  static Future<void> setGlassSidebar(bool enabled) async {
    glassSidebar.value = enabled;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileService.key('app_theme_glass_sidebar'), enabled);
    } catch (_) {}
  }

  static Future<void> setGlassSidebarBlur(bool enabled) async {
    glassSidebarBlur.value = enabled;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ProfileService.key('app_theme_glass_sidebar_blur'), enabled);
    } catch (_) {}
  }

  static Future<void> setGlassSidebarBlurLevel(int level) async {
    final clamped = level.clamp(1, 5);
    glassSidebarBlurLevel.value = clamped;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(ProfileService.key('app_theme_glass_sidebar_blur_level'), clamped);
    } catch (_) {}
  }

  static Future<void> setGlassSidebarLevel(int level) async {
    final clamped = level.clamp(1, 5);
    glassSidebarLevel.value = clamped;
    themeRevision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(ProfileService.key('app_theme_glass_sidebar_level'), clamped);
    } catch (_) {}
  }

  /// Linear gradient with transparency tailored by [glassSidebarLevel] (1 = barely transparent, 5 = crystal clear)
  /// Retains the active theme preset's atmosphere color while applying glass transparency.
  static LinearGradient glassSidebarGradient([int? levelOverride, ThemePresetOption? presetOverride]) {
    final lvl = (levelOverride ?? glassSidebarLevel.value).clamp(1, 5);
    final preset = presetOverride ?? currentPreset.value;

    Color base1;
    Color base2;
    Color base3;

    if (preset.id == 'glass') {
      base1 = const Color(0xFF1A2942);
      base2 = const Color(0xFF101B2E);
      base3 = const Color(0xFF0A121F);
    } else if (preset.isOLED) {
      base1 = const Color(0xFF080808);
      base2 = const Color(0xFF000000);
      base3 = const Color(0xFF000000);
    } else if (preset.isRainbow) {
      base1 = const Color(0xFF1C1034);
      base2 = const Color(0xFF130A24);
      base3 = const Color(0xFF090514);
    } else {
      // Retain the active theme's surface/background atmosphere colors
      base1 = (preset.id == 'custom' ? surfaceLight : preset.surfaceLight).withAlpha(0xFF);
      base2 = (preset.id == 'custom' ? surface : preset.surface).withAlpha(0xFF);
      base3 = (preset.id == 'custom' ? background : preset.background).withAlpha(0xFF);
    }

    // Alpha levels: Level 1 (~95% opaque / barely transparent) to Level 5 (~10% opaque / crystal clear)
    const alphaLevels = <int, List<int>>{
      1: [0xF4, 0xEC, 0xE4],
      2: [0xC4, 0xB4, 0xA4],
      3: [0x8C, 0x78, 0x64],
      4: [0x50, 0x40, 0x30],
      5: [0x20, 0x14, 0x08],
    };

    final alphas = alphaLevels[lvl] ?? alphaLevels[3]!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base1.withAlpha(alphas[0]),
        base2.withAlpha(alphas[1]),
        base3.withAlpha(alphas[2]),
      ],
    );
  }

  static Color get plexGold => currentThemeOption.value.primary;
  static Color get plexGoldLight => currentThemeOption.value.light;
  static Color get focusHighlight => currentThemeOption.value.primary;

  static bool get isRainbowAccent =>
      currentThemeOption.value.id == 'rainbow' || currentThemeOption.value.isRainbow;
  static bool get isRainbowBorder => isRainbowAccent || isRainbow;

  /// Returns a rainbow gradient border when [isRainbowBorder] is active and item [isHighlighted],
  /// otherwise returns standard [Border.all].
  static BoxBorder outlineBorder({
    required bool isHighlighted,
    Color? highlightColor,
    Color? unhighlightColor,
    double highlightWidth = 2.0,
    double unhighlightWidth = 1.2,
  }) {
    if (isHighlighted && isRainbowBorder) {
      return GradientBoxBorder(
        gradient: vividRainbowGradient,
        width: highlightWidth,
      );
    }
    return Border.all(
      color: isHighlighted
          ? (highlightColor ?? plexGold)
          : (unhighlightColor ?? cardBorder),
      width: isHighlighted ? highlightWidth : unhighlightWidth,
    );
  }

  /// Convenience method for a guaranteed rainbow border
  static BoxBorder rainbowOutlineBorder({double width = 2.0}) {
    return GradientBoxBorder(
      gradient: vividRainbowGradient,
      width: width,
    );
  }

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9EA2A8);
  static const Color textMuted = Color(0xFF6B7280);

  /// Generates Apple Liquid Glass decoration without left specular fade smear
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
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isHighlighted
            ? [
                Colors.white.withOpacity(0.22),
                effectiveAccent.withOpacity(0.15),
                Colors.white.withOpacity(0.08),
              ]
            : [
                Colors.white.withOpacity(0.12),
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
      ),
      border: (isHighlighted && isRainbowBorder)
          ? GradientBoxBorder(
              gradient: vividRainbowGradient,
              width: borderWidth + 0.6,
            )
          : Border.all(
              color: isHighlighted
                  ? Colors.white.withOpacity(0.92)
                  : Colors.white.withOpacity(0.32),
              width: isHighlighted ? borderWidth + 0.6 : borderWidth,
            ),
      boxShadow: [
        BoxShadow(
          color: isHighlighted
              ? (isRainbowBorder ? Colors.transparent : effectiveAccent.withOpacity(0.35))
              : Colors.black.withOpacity(0.20),
          blurRadius: isHighlighted ? 12 : 6,
          spreadRadius: isHighlighted ? 1.0 : 0,
          offset: isHighlighted ? Offset.zero : const Offset(0, 2),
        ),
      ],
    );
  }

  /// Apple-style specular gloss reflection sweep layer (disabled to prevent fade smear)
  static Widget buildGlassReflectionLayer({BorderRadius? borderRadius}) {
    return const SizedBox.shrink();
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
      if (savedPresetId == 'royal') {
        // Migrate existing users on old Imperial Amethyst to Cosmic Nebula
        final nebulaPreset = presetOptions.firstWhere((p) => p.id == 'nebula');
        currentPreset.value = nebulaPreset;
        await prefs.setString(pKeyPreset, 'nebula');
      } else if (savedPresetId != null) {
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
        } else if (savedColorId == 'sunset') {
          final crimson = colorOptions.firstWhere((opt) => opt.id == 'crimson');
          currentThemeOption.value = crimson;
          await prefs.setString(ProfileService.key('app_theme_color_id'), 'crimson');
        } else if (savedColorId == 'amber') {
          final gold = colorOptions.firstWhere((opt) => opt.id == 'gold');
          currentThemeOption.value = gold;
          await prefs.setString(ProfileService.key('app_theme_color_id'), 'gold');
        } else if (savedColorId == 'violet') {
          final rainbow = colorOptions.firstWhere((opt) => opt.id == 'rainbow');
          currentThemeOption.value = rainbow;
          await prefs.setString(ProfileService.key('app_theme_color_id'), 'rainbow');
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

      // Migration check: When update goes out to existing users, transparent sidebar and blur enabled,
      // transparency set to 4, blur set to 2 (20%).
      final migrationKey = ProfileService.key('app_theme_v185_defaults_migrated');
      final hasMigrated = prefs.getBool(migrationKey) ?? false;

      if (!hasMigrated) {
        glassSidebar.value = true;
        glassSidebarBlur.value = true;
        glassSidebarLevel.value = 4;
        glassSidebarBlurLevel.value = 2;
        await prefs.setBool(ProfileService.key('app_theme_glass_sidebar'), true);
        await prefs.setBool(ProfileService.key('app_theme_glass_sidebar_blur'), true);
        await prefs.setInt(ProfileService.key('app_theme_glass_sidebar_level'), 4);
        await prefs.setInt(ProfileService.key('app_theme_glass_sidebar_blur_level'), 2);
        await prefs.setBool(migrationKey, true);
      } else {
        glassSidebar.value = prefs.getBool(ProfileService.key('app_theme_glass_sidebar')) ?? true;
        glassSidebarBlur.value = prefs.getBool(ProfileService.key('app_theme_glass_sidebar_blur')) ?? true;
        glassSidebarLevel.value = prefs.getInt(ProfileService.key('app_theme_glass_sidebar_level')) ?? 4;
        glassSidebarBlurLevel.value = prefs.getInt(ProfileService.key('app_theme_glass_sidebar_blur_level')) ?? 2;
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
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      cardColor: crd,
    );
  }
}

/// A [Border] that renders a continuous stroke using a [Gradient].
/// Extends [Border] with 4 identical sides so that [isUniform] is always true.
/// This guarantees that [BoxBorder.lerp] and [AnimatedContainer] interpolate
/// smoothly with [borderRadius] as a rounded rectangle at every frame,
/// never falling back to non-uniform mitered square borders.
class GradientBoxBorder extends Border {
  final Gradient gradient;
  final double width;

  GradientBoxBorder({
    required this.gradient,
    this.width = 2.0,
    Color sideColor = Colors.transparent,
  }) : super(
          top: BorderSide(color: sideColor, width: width),
          right: BorderSide(color: sideColor, width: width),
          bottom: BorderSide(color: sideColor, width: width),
          left: BorderSide(color: sideColor, width: width),
        );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  bool get isUniform => true;

  static final Paint _borderPaint = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    if (rect.isEmpty || rect.width <= 0 || rect.height <= 0 || width <= 0) return;
    _borderPaint
      ..shader = gradient.createShader(rect)
      ..strokeWidth = width;

    if (shape == BoxShape.circle) {
      final radius = (rect.width - width) / 2;
      if (radius > 0) {
        canvas.drawCircle(rect.center, radius, _borderPaint);
      }
    } else if (borderRadius != null && borderRadius != BorderRadius.zero) {
      final rrect = borderRadius.toRRect(rect).deflate(width / 2);
      canvas.drawRRect(rrect, _borderPaint);
    } else {
      canvas.drawRect(rect.deflate(width / 2), _borderPaint);
    }
  }

  @override
  GradientBoxBorder scale(double t) {
    return GradientBoxBorder(gradient: gradient, width: width * t);
  }
}
