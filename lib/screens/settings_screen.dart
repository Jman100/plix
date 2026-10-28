import '../widgets/brand_logo.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/update_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_bottom_nav.dart';
import '../services/plix_device_helper.dart';
import '../services/native_player_service.dart';

class SettingsScreen extends StatefulWidget {
  final PlexServer? server;
  final String clientId;

  const SettingsScreen({
    super.key,
    this.server,
    required this.clientId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, FocusNode> _presetFocusNodes = {};
  final Map<String, FocusNode> _colorFocusNodes = {};
  final FocusNode _customColorFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _homeButtonFocusNode = FocusNode();

  // Playback settings state
  bool _autoplayNextEpisode = true;
  bool _autoSkipIntro = false;
  bool _playTvThemes = true;
  bool _continuePlaybackScreenOff = false;
  final FocusNode _skipIntroFocusNode = FocusNode();
  final FocusNode _themeFocusNode = FocusNode();
  final FocusNode _screenOffFocusNode = FocusNode();
  int _quickRewindSeconds = 10;
  int _skipAheadSeconds = 30;

  // Update settings state
  bool _autoCheckUpdates = true;
  bool _isCheckingUpdate = false;
  final FocusNode _autoUpdateFocusNode = FocusNode();
  final FocusNode _checkUpdateBtnFocusNode = FocusNode();

  final FocusNode _autoplayFocusNode = FocusNode();
  final FocusNode _rewindFocusNode = FocusNode();
  final FocusNode _skipFocusNode = FocusNode();
  final FocusNode _aboutServerFocusNode = FocusNode();
  final FocusNode _aboutClientFocusNode = FocusNode();
  final FocusNode _aboutVersionFocusNode = FocusNode();
  final FocusNode _aboutWebsiteFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  void _scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0.0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    PlixTheme.themeRevision.addListener(_onThemeChanged);
    for (final preset in PlixTheme.presetOptions) {
      _presetFocusNodes[preset.id] = FocusNode();
    }
    for (final opt in PlixTheme.colorOptions) {
      _colorFocusNodes[opt.id] = FocusNode();
    }
    _loadSettings();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final autoCheck = await UpdateService.isAutoCheckEnabled();
    if (mounted) {
      setState(() {
        _autoCheckUpdates = autoCheck;
        _autoplayNextEpisode = prefs.getBool('autoplay_next_episode') ?? true;
        _autoSkipIntro = prefs.getBool('auto_skip_intro') ?? false;
        _playTvThemes = prefs.getBool('play_tv_show_themes') ?? true;
        _continuePlaybackScreenOff = prefs.getBool('continue_playback_screen_off') ?? false;
        _quickRewindSeconds = prefs.getInt('quick_rewind_seconds') ?? 10;
        _skipAheadSeconds = prefs.getInt('skip_ahead_seconds') ?? 30;
      });
    }
  }

  Future<void> _toggleAutoUpdate() async {
    final newVal = !_autoCheckUpdates;
    setState(() => _autoCheckUpdates = newVal);
    await UpdateService.setAutoCheckEnabled(newVal);
  }

  Future<void> _openWebsite(String url) async {
    try {
      if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isAndroid) {
        const channel = MethodChannel('com.plix.plix/updater');
        await channel.invokeMethod('openUrl', {'url': url});
      }
    } catch (_) {}
    try {
      Clipboard.setData(ClipboardData(text: url));
      _showToast('Opening $url');
    } catch (_) {
      _showToast(url);
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        width: 320,
        backgroundColor: PlixTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.5)),
        ),
      ),
    );
  }

  Future<void> _manualCheckForUpdates() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    _showToast('Checking for updates...');
    final updateInfo = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() => _isCheckingUpdate = false);
      if (updateInfo != null && updateInfo.hasUpdate) {
        UpdateService.showUpdateDialog(context, updateInfo);
      } else if (updateInfo != null) {
        _showToast("You're on the latest version (v${UpdateService.currentVersion})");
      } else {
        _showToast('Unable to reach update server.');
      }
    }
  }

  Future<void> _toggleAutoplay() async {
    final newVal = !_autoplayNextEpisode;
    setState(() => _autoplayNextEpisode = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoplay_next_episode', newVal);
  }

  Future<void> _toggleAutoSkipIntro() async {
    final newVal = !_autoSkipIntro;
    setState(() => _autoSkipIntro = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_skip_intro', newVal);
  }

  Future<void> _togglePlayTvThemes() async {
    final newVal = !_playTvThemes;
    setState(() => _playTvThemes = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('play_tv_show_themes', newVal);
  }

  Future<void> _toggleContinuePlaybackScreenOff() async {
    final newVal = !_continuePlaybackScreenOff;
    setState(() => _continuePlaybackScreenOff = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('continue_playback_screen_off', newVal);
    try {
      await NativePlayerService().setScreenOffPlayback(newVal);
    } catch (_) {}
  }

  Future<void> _cycleRewind() async {
    const options = [5, 10, 15, 20, 30];
    final currentIdx = options.indexOf(_quickRewindSeconds);
    final nextVal = options[(currentIdx + 1) % options.length];
    setState(() => _quickRewindSeconds = nextVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quick_rewind_seconds', nextVal);
  }

  Future<void> _cycleSkip() async {
    const options = [10, 15, 30, 45, 60];
    final currentIdx = options.indexOf(_skipAheadSeconds);
    final nextVal = options[(currentIdx + 1) % options.length];
    setState(() => _skipAheadSeconds = nextVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skip_ahead_seconds', nextVal);
  }

  @override
  void dispose() {
    PlixTheme.themeRevision.removeListener(_onThemeChanged);
    _scrollController.dispose();
    _backButtonFocusNode.dispose();
    _homeButtonFocusNode.dispose();
    _autoplayFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _themeFocusNode.dispose();
    _screenOffFocusNode.dispose();
    _rewindFocusNode.dispose();
    _skipFocusNode.dispose();
    _autoUpdateFocusNode.dispose();
    _checkUpdateBtnFocusNode.dispose();
    _aboutServerFocusNode.dispose();
    _aboutClientFocusNode.dispose();
    _aboutVersionFocusNode.dispose();
    _aboutWebsiteFocusNode.dispose();
    for (final node in _presetFocusNodes.values) {
      node.dispose();
    }
    _customColorFocusNode.dispose();
    for (final node in _colorFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _showCustomColorDialog() {
    final customPalette = [
      const Color(0xFFE55B13), const Color(0xFFE5A00D), const Color(0xFFFFB300),
      const Color(0xFFFF5722), const Color(0xFFE53935), const Color(0xFFD81B60),
      const Color(0xFFFF1493), const Color(0xFF8E24AA), const Color(0xFF673AB7),
      const Color(0xFF3F51B5), const Color(0xFF1E88E5), const Color(0xFF00E5FF),
      const Color(0xFF00B0FF), const Color(0xFF00897B), const Color(0xFF00E676),
      const Color(0xFF43A047), const Color(0xFF7CB342), const Color(0xFFC0CA33),
      const Color(0xFFFFD54F), const Color(0xFF88C0D0), const Color(0xFF90CAF9),
      const Color(0xFFCE93D8), const Color(0xFFE2E8F0), const Color(0xFFFFFFFF),
    ];

    final textController = TextEditingController(
      text: PlixTheme.plexGold.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: PlixTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: PlixTheme.cardBorder, width: 1.5),
          ),
          title: Row(
            children: [
              Icon(Icons.palette_rounded, color: PlixTheme.plexGold, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Custom Accent Color',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a hue from the palette or enter a 6-digit hex code:',
                  style: TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final col in customPalette)
                      InkWell(
                        onTap: () {
                          PlixTheme.setCustomColor(col, 'Custom');
                          Navigator.of(ctx).pop();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: PlixTheme.plexGold.value == col.value
                                  ? Colors.white
                                  : Colors.black26,
                              width: PlixTheme.plexGold.value == col.value ? 2.5 : 1,
                            ),
                          ),
                          child: PlixTheme.plexGold.value == col.value
                              ? const Icon(Icons.check, size: 18, color: Colors.black)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text('#', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: textController,
                        maxLength: 6,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'RRGGBB',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: PlixTheme.card,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PlixTheme.cardBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PlixTheme.plexGold, width: 2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PlixTheme.plexGold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        final hex = textController.text.trim().replaceAll('#', '');
                        if (hex.length == 6) {
                          final val = int.tryParse('FF$hex', radix: 16);
                          if (val != null) {
                            PlixTheme.setCustomColor(Color(val), 'Custom (#$hex)');
                            Navigator.of(ctx).pop();
                          }
                        }
                      },
                      child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: PlixTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;
    final isMobile = !isTv && !Platform.isWindows;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      bottomNavigationBar: (isCompact && !isTv && widget.server != null)
          ? PlixBottomNav(
              currentIndex: 4,
              server: widget.server!,
              clientId: widget.clientId,
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: isCompact ? 12 : 20),
              child: Row(
                children: [
                  PlixBackButton(
                    focusNode: _backButtonFocusNode,
                    autofocus: false,
                    onRight: () => _homeButtonFocusNode.requestFocus(),
                    onDown: () {
                      _presetFocusNodes[PlixTheme.presetOptions.first.id]?.requestFocus();
                      if (PlixDeviceHelper.isTelevision) _scrollToTop();
                    },
                  ),
                  const SizedBox(width: 10),
                  PlixHomeButton(
                    focusNode: _homeButtonFocusNode,
                    onLeft: () => _backButtonFocusNode.requestFocus(),
                    onDown: () {
                      _presetFocusNodes[PlixTheme.presetOptions.first.id]?.requestFocus();
                      if (PlixDeviceHelper.isTelevision) _scrollToTop();
                    },
                  ),
                  const SizedBox(width: 20),
                  Icon(
                    Icons.settings_rounded,
                    color: PlixTheme.plexGold,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 36, vertical: 12),
                children: [
                  // Section 1: Appearance & Visual Themes
                  Row(
                    children: [
                      Icon(Icons.palette_rounded, color: PlixTheme.plexGold, size: 24),
                      const SizedBox(width: 10),
                      const Text(
                        'Appearance & Visual Style',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Customize your theme aesthetic, surface translucency, and accent highlight colors.',
                    style: TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Live Preview Card
                  _LiveThemePreviewCard(),
                  const SizedBox(height: 24),

                  // Theme Presets Header
                  Row(
                    children: [
                      Icon(Icons.style_rounded, color: PlixTheme.plexGold, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Theme Style Presets',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose a base visual style for backgrounds, cards, and overall atmosphere.',
                    style: TextStyle(color: PlixTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Presets Grid
                  ValueListenableBuilder<ThemePresetOption>(
                    valueListenable: PlixTheme.currentPreset,
                    builder: (context, activePreset, _) {
                      final cols = isCompact ? 2 : 3;
                      final rows = (PlixTheme.presetOptions.length / cols).ceil();
                      return Column(
                        children: [
                          for (int row = 0; row < rows; row++) ...[
                            Row(
                              children: [
                                for (int col = 0; col < cols; col++) ...[
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final index = row * cols + col;
                                        if (index >= PlixTheme.presetOptions.length) {
                                          return const SizedBox();
                                        }
                                        final preset = PlixTheme.presetOptions[index];
                                        return _ThemePresetTile(
                                          preset: preset,
                                          isSelected: preset.id == activePreset.id,
                                          focusNode: _presetFocusNodes[preset.id]!,
                                          onSelect: () => PlixTheme.setPreset(preset),
                                          onLeft: index > 0
                                              ? () => _presetFocusNodes[PlixTheme.presetOptions[index - 1].id]?.requestFocus()
                                              : null,
                                          onRight: index < PlixTheme.presetOptions.length - 1
                                              ? () => _presetFocusNodes[PlixTheme.presetOptions[index + 1].id]?.requestFocus()
                                              : null,
                                          onUp: row == 0
                                              ? () => _backButtonFocusNode.requestFocus()
                                              : () => _presetFocusNodes[PlixTheme.presetOptions[index - cols].id]?.requestFocus(),
                                          onDown: row == rows - 1
                                              ? () => _colorFocusNodes[PlixTheme.colorOptions[col.clamp(0, PlixTheme.colorOptions.length - 1)].id]?.requestFocus()
                                              : () => _presetFocusNodes[PlixTheme.presetOptions[(index + cols).clamp(0, PlixTheme.presetOptions.length - 1)].id]?.requestFocus(),
                                        );
                                      },
                                    ),
                                  ),
                                  if (col < cols - 1) const SizedBox(width: 10),
                                ],
                              ],
                            ),
                            if (row < rows - 1) const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // Accent Colors Header
                  Row(
                    children: [
                      Icon(Icons.color_lens_rounded, color: PlixTheme.plexGold, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Accent Highlight Color',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pick your preferred highlight color used on focus rings, badges, and primary buttons.',
                    style: TextStyle(color: PlixTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Colors Grid + Custom Color Option
                  ValueListenableBuilder<ThemeColorOption>(
                    valueListenable: PlixTheme.currentThemeOption,
                    builder: (context, currentOption, _) {
                      final cols = isCompact ? 3 : 5;
                      final totalItems = PlixTheme.colorOptions.length + 1; // +1 for Custom Color
                      final rows = (totalItems / cols).ceil();
                      final isCustomActive = currentOption.id.startsWith('custom_');

                      return Column(
                        children: [
                          for (int row = 0; row < rows; row++) ...[
                            Row(
                              children: [
                                for (int col = 0; col < cols; col++) ...[
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final index = row * cols + col;
                                        if (index >= totalItems) {
                                          return const SizedBox();
                                        }

                                        FocusNode nodeFor(int idx) {
                                          if (idx == totalItems - 1) return _customColorFocusNode;
                                          return _colorFocusNodes[PlixTheme.colorOptions[idx].id]!;
                                        }

                                        final onLeft = index > 0 ? () => nodeFor(index - 1).requestFocus() : null;
                                        final onRight = index < totalItems - 1 ? () => nodeFor(index + 1).requestFocus() : null;
                                        final onUp = row == 0
                                            ? () => _presetFocusNodes[PlixTheme.presetOptions[col.clamp(0, PlixTheme.presetOptions.length - 1)].id]?.requestFocus()
                                            : () => nodeFor(index - cols).requestFocus();
                                        final onDown = (row == rows - 1 || index + cols >= totalItems)
                                            ? () => _autoplayFocusNode.requestFocus()
                                            : () => nodeFor(index + cols).requestFocus();

                                        // Custom Color Tile
                                        if (index == totalItems - 1) {
                                          return _CustomColorTile(
                                            isSelected: isCustomActive,
                                            activeColor: isCustomActive ? currentOption.primary : null,
                                            focusNode: _customColorFocusNode,
                                            onSelect: _showCustomColorDialog,
                                            onLeft: onLeft,
                                            onRight: onRight,
                                            onUp: onUp,
                                            onDown: onDown,
                                          );
                                        }

                                        final opt = PlixTheme.colorOptions[index];
                                        return _ThemeColorTile(
                                          option: opt,
                                          isSelected: !isCustomActive && opt.id == currentOption.id,
                                          focusNode: _colorFocusNodes[opt.id]!,
                                          onSelect: () => PlixTheme.setTheme(opt),
                                          onLeft: onLeft,
                                          onRight: onRight,
                                          onUp: onUp,
                                          onDown: onDown,
                                        );
                                      },
                                    ),
                                  ),
                                  if (col < cols - 1) const SizedBox(width: 10),
                                ],
                              ],
                            ),
                            if (row < rows - 1) const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 36),
                  Divider(color: PlixTheme.cardBorder),
                  const SizedBox(height: 20),

                  // Section 2: Playback Settings
                  Row(
                    children: [
                      Icon(Icons.play_circle_outline_rounded, color: PlixTheme.plexGold, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Playback & Streaming',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _SettingsActionTile(
                    focusNode: _autoplayFocusNode,
                    onUp: () {
                      _colorFocusNodes[PlixTheme.colorOptions.first.id]?.requestFocus();
                    },
                    onDown: () => _skipIntroFocusNode.requestFocus(),
                    title: 'Autoplay Next Episode',
                    subtitle: 'Automatically start the next episode with countdown when an episode finishes',
                    trailing: _autoplayNextEpisode ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _toggleAutoplay,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _skipIntroFocusNode,
                    onUp: () => _autoplayFocusNode.requestFocus(),
                    onDown: () => _themeFocusNode.requestFocus(),
                    title: 'Auto Skip Intro',
                    subtitle: 'Automatically skip intro markers when playing TV episodes',
                    trailing: _autoSkipIntro ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _toggleAutoSkipIntro,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _themeFocusNode,
                    onUp: () => _skipIntroFocusNode.requestFocus(),
                    onDown: () => _rewindFocusNode.requestFocus(),
                    title: 'Play TV Show Themes',
                    subtitle: 'Play background theme music when viewing TV show details',
                    trailing: _playTvThemes ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _togglePlayTvThemes,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _rewindFocusNode,
                    onUp: () => _themeFocusNode.requestFocus(),
                    onDown: () => _skipFocusNode.requestFocus(),
                    title: 'Quick Rewind Duration',
                    subtitle: 'Seconds rewound when pressing D-pad Left or Rewind on remote',
                    trailing: '${_quickRewindSeconds}s',
                    isInteractive: true,
                    onTap: _cycleRewind,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _skipFocusNode,
                    onUp: () => _rewindFocusNode.requestFocus(),
                    onDown: () => isMobile ? _screenOffFocusNode.requestFocus() : _autoUpdateFocusNode.requestFocus(),
                    title: 'Skip Ahead Duration',
                    subtitle: 'Seconds skipped forward when pressing D-pad Right or Fast Forward on remote',
                    trailing: '${_skipAheadSeconds}s',
                    isInteractive: true,
                    onTap: _cycleSkip,
                  ),
                  if (isMobile) ...[
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      focusNode: _screenOffFocusNode,
                      onUp: () => _skipFocusNode.requestFocus(),
                      onDown: () => _autoUpdateFocusNode.requestFocus(),
                      title: 'Continue playback with screen off',
                      subtitle: 'Keep playing audio in the background when your screen is turned off',
                      trailing: _continuePlaybackScreenOff ? 'Enabled' : 'Disabled',
                      isInteractive: true,
                      onTap: _toggleContinuePlaybackScreenOff,
                    ),
                  ],

                  const SizedBox(height: 36),
                  Divider(color: PlixTheme.cardBorder),
                  const SizedBox(height: 20),

                  // Section: App Updates
                  Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: PlixTheme.plexGold, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'App Updates',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _SettingsActionTile(
                    focusNode: _autoUpdateFocusNode,
                    onUp: () => isMobile ? _screenOffFocusNode.requestFocus() : _skipFocusNode.requestFocus(),
                    onDown: () => _checkUpdateBtnFocusNode.requestFocus(),
                    title: 'Automatically Check for Updates',
                    subtitle: 'Check for new versions when Plix launches or resumes from standby',
                    trailing: _autoCheckUpdates ? 'ON' : 'OFF',
                    isInteractive: true,
                    onTap: _toggleAutoUpdate,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _checkUpdateBtnFocusNode,
                    onUp: () => _autoUpdateFocusNode.requestFocus(),
                    onDown: () {
                      if (widget.server != null) {
                        _aboutServerFocusNode.requestFocus();
                      } else {
                        _aboutClientFocusNode.requestFocus();
                      }
                    },
                    title: 'Check for Updates',
                    subtitle: 'Check for an updated version from update server',
                    trailing: _isCheckingUpdate ? 'Checking...' : 'Check Now',
                    isLoading: _isCheckingUpdate,
                    isInteractive: true,
                    onTap: _manualCheckForUpdates,
                  ),

                  const SizedBox(height: 36),
                  Divider(color: PlixTheme.cardBorder),
                  const SizedBox(height: 20),

                  // Section 3: About
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: PlixTheme.plexGold, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'About Plix',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (widget.server != null) ...[
                    _SettingsActionTile(
                      focusNode: _aboutServerFocusNode,
                      onUp: () => _checkUpdateBtnFocusNode.requestFocus(),
                      onDown: () => _aboutClientFocusNode.requestFocus(),
                      title: 'Connected Server',
                      subtitle: widget.server!.name,
                      trailing: widget.server!.activeConnectionUri ??
                          (widget.server!.connections.isNotEmpty
                              ? widget.server!.connections.first.address
                              : 'Connected'),
                      trailingBelow: isCompact,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SettingsActionTile(
                    focusNode: _aboutClientFocusNode,
                    onUp: () => widget.server != null
                        ? _aboutServerFocusNode.requestFocus()
                        : _checkUpdateBtnFocusNode.requestFocus(),
                    onDown: () => _aboutVersionFocusNode.requestFocus(),
                    title: 'Client Identifier',
                    subtitle: widget.clientId,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _aboutVersionFocusNode,
                    onUp: () => _aboutClientFocusNode.requestFocus(),
                    onDown: () => _aboutWebsiteFocusNode.requestFocus(),
                    title: 'App Version',
                    subtitle: Platform.isWindows
                        ? 'Plix for Windows (MediaKit mpv)'
                        : (PlixDeviceHelper.isTelevision
                            ? 'Plix for Android TV (Media3 ExoPlayer)'
                            : 'Plix for Android (Media3 ExoPlayer)'),
                    trailing: 'v${UpdateService.currentVersion}',
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _aboutWebsiteFocusNode,
                    onUp: () => _aboutVersionFocusNode.requestFocus(),
                    title: 'Official Website',
                    subtitle: 'Visit plix.jman100.com for downloads & updates',
                    trailing: 'https://plix.jman100.com',
                    trailingBelow: isCompact,
                    isInteractive: true,
                    onTap: () => _openWebsite('https://plix.jman100.com'),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorTile extends StatefulWidget {
  final ThemeColorOption option;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ThemeColorTile({
    required this.option,
    required this.isSelected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_ThemeColorTile> createState() => _ThemeColorTileState();
}

class _ThemeColorTileState extends State<_ThemeColorTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
      if (widget.focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final borderColor = isHighlighted
        ? widget.option.primary
        : (widget.isSelected ? widget.option.primary.withOpacity(0.85) : Colors.transparent);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows) {
            setState(() {
              _isHovered = hovered;
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: 2.5,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: widget.option.primary.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.option.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.option.primary.withOpacity(0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.option.name,
                    maxLines: 1,
                    style: TextStyle(
                      color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                      fontSize: 10,
                      fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsActionTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? trailing;
  final FocusNode? focusNode;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onTap;
  final bool isInteractive;
  final bool isLoading;
  final bool trailingBelow;

  const _SettingsActionTile({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.focusNode,
    this.onUp,
    this.onDown,
    this.onTap,
    this.isInteractive = false,
    this.isLoading = false,
    this.trailingBelow = false,
  });

  @override
  State<_SettingsActionTile> createState() => _SettingsActionTileState();
}

class _SettingsActionTileState extends State<_SettingsActionTile> {
  late FocusNode _node;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() {
        _isFocused = _node.hasFocus;
      });
      if (_isFocused && PlixDeviceHelper.isTelevision) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocus);
    if (widget.focusNode == null) {
      _node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _node,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            if (widget.onTap != null) {
              widget.onTap!();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onTap,
        onHover: (hovered) {
          if (Platform.isWindows && widget.isInteractive) {
            setState(() => _isHovered = hovered);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHighlighted ? PlixTheme.plexGold : PlixTheme.cardBorder,
              width: isHighlighted ? 2.0 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: PlixTheme.plexGold.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Builder(
            builder: (ctx) {
              final showBelow = widget.trailingBelow || (PlixDeviceHelper.isCompact(ctx) && (widget.trailing?.length ?? 0) > 16);
              Widget? trailingWidget;
              if (widget.trailing != null && widget.trailing!.isNotEmpty) {
                trailingWidget = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.isInteractive && isHighlighted
                        ? PlixTheme.plexGold.withOpacity(0.25)
                        : PlixTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isHighlighted ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isLoading) ...[
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.trailing!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.isInteractive) ...[
                        const SizedBox(width: 6),
                        Icon(
                          widget.trailing!.startsWith('http') ? Icons.open_in_new_rounded : Icons.swap_horiz_rounded,
                          size: 15,
                          color: PlixTheme.plexGold.withOpacity(0.8),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (showBelow && trailingWidget != null) ...[
                          const SizedBox(height: 8),
                          trailingWidget,
                        ],
                      ],
                    ),
                  ),
                  if (!showBelow && trailingWidget != null) ...[
                    const SizedBox(width: 12),
                    trailingWidget,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Real-time live theme preview mockup
class _LiveThemePreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preset = PlixTheme.currentPreset.value;
    final accent = PlixTheme.plexGold;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: preset.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: preset.isGlass ? Colors.white.withOpacity(0.18) : preset.cardBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PlixAppLogo(size: 28, showWordmark: false, borderRadius: 7),
              const SizedBox(width: 10),
              const Text(
                'Live Theme Preview',
                style: TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withOpacity(0.6), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${preset.name} • ${PlixTheme.currentThemeOption.value.name}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Sample card
              Container(
                width: 90,
                height: 52,
                decoration: BoxDecoration(
                  color: preset.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent, width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(Icons.play_circle_filled_rounded, color: accent, size: 28),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atmosphere: ${preset.description}',
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Watch Now',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: preset.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: preset.cardBorder),
                          ),
                          child: const Text(
                            'Details',
                            style: TextStyle(
                              color: PlixTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Base visual theme style card
class _ThemePresetTile extends StatefulWidget {
  final ThemePresetOption preset;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ThemePresetTile({
    required this.preset,
    required this.isSelected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_ThemePresetTile> createState() => _ThemePresetTileState();
}

class _ThemePresetTileState extends State<_ThemePresetTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      if (widget.focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.25,
          duration: const Duration(milliseconds: 180),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final accent = PlixTheme.plexGold;

    final borderColor = isHighlighted
        ? accent
        : (widget.isSelected ? accent.withOpacity(0.8) : PlixTheme.cardBorder);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 106,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isHighlighted ? 2.5 : 1.5),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 14,
                      spreadRadius: 1.5,
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.preset.previewGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: Icon(widget.preset.icon, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.isSelected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.black),
                    ),
                ],
              ),
              Text(
                widget.preset.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PlixTheme.textMuted,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.preset.background,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white30, width: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.preset.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white30, width: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.preset.card,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white30, width: 0.8),
                    ),
                  ),
                  if (widget.preset.isGlass) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('GLASS', style: TextStyle(color: Colors.white70, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                  ] else if (widget.preset.isOLED) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('OLED', style: TextStyle(color: Colors.white70, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom color option tile
class _CustomColorTile extends StatefulWidget {
  final bool isSelected;
  final Color? activeColor;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _CustomColorTile({
    required this.isSelected,
    this.activeColor,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_CustomColorTile> createState() => _CustomColorTileState();
}

class _CustomColorTileState extends State<_CustomColorTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      if (widget.focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final accent = widget.activeColor ?? PlixTheme.plexGold;

    final borderColor = isHighlighted
        ? accent
        : (widget.isSelected ? accent.withOpacity(0.85) : Colors.transparent);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onSelect,
        onHover: (hovered) {
          if (Platform.isWindows) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 2.5),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: const SweepGradient(
                    colors: [
                      Colors.red, Colors.orange, Colors.yellow,
                      Colors.green, Colors.cyan, Colors.blue,
                      Colors.purple, Colors.red,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom...',
                      maxLines: 1,
                      style: TextStyle(
                        color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.isSelected ? 'Active' : 'Choose hue',
                      maxLines: 1,
                      style: const TextStyle(
                        color: PlixTheme.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
