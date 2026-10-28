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
import 'appearance_screen.dart';

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
  final FocusNode _appearanceTileFocusNode = FocusNode();
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

  @override
  void initState() {
    super.initState();
    PlixTheme.themeRevision.addListener(_onThemeChanged);
    _loadSettings();

    // Default focus to the appearance tile for immediate accessibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _appearanceTileFocusNode.requestFocus();
    });
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

  Future<void> _togglePlayTvThemes() async {
    final newVal = !_playTvThemes;
    setState(() => _playTvThemes = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('play_tv_show_themes', newVal);
  }

  Future<void> _openWebsite(String url) async {
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

  void _openAppearanceScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppearanceScreen(
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    PlixTheme.themeRevision.removeListener(_onThemeChanged);
    _scrollController.dispose();
    _appearanceTileFocusNode.dispose();
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
    super.dispose();
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
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: isCompact ? 10 : 16),
              child: Row(
                children: [
                  PlixBackButton(
                    focusNode: _backButtonFocusNode,
                    autofocus: false,
                    onRight: () => _homeButtonFocusNode.requestFocus(),
                    onDown: () => _appearanceTileFocusNode.requestFocus(),
                  ),
                  const SizedBox(width: 10),
                  PlixHomeButton(
                    focusNode: _homeButtonFocusNode,
                    onLeft: () => _backButtonFocusNode.requestFocus(),
                    onDown: () => _appearanceTileFocusNode.requestFocus(),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.settings_rounded,
                    color: PlixTheme.plexGold,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 24,
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
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 8),
                children: [
                  // Section 1: Appearance & Visual Themes
                  Row(
                    children: [
                      Icon(Icons.palette_rounded, color: PlixTheme.plexGold, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Appearance & Visual Style',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dedicated Appearance & Themes Navigation Tile
                  _AppearanceHeroTile(
                    focusNode: _appearanceTileFocusNode,
                    onUp: () => _backButtonFocusNode.requestFocus(),
                    onDown: () => _autoplayFocusNode.requestFocus(),
                    onSelect: _openAppearanceScreen,
                  ),

                  const SizedBox(height: 28),
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
                    onUp: () => _appearanceTileFocusNode.requestFocus(),
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

                  const SizedBox(height: 28),
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

                  const SizedBox(height: 28),
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

/// Dedicated Interactive Hero Tile that leads to AppearanceScreen
class _AppearanceHeroTile extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onSelect;

  const _AppearanceHeroTile({
    required this.focusNode,
    this.onUp,
    this.onDown,
    required this.onSelect,
  });

  @override
  State<_AppearanceHeroTile> createState() => _AppearanceHeroTileState();
}

class _AppearanceHeroTileState extends State<_AppearanceHeroTile> {
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
          alignment: 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
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
    final preset = PlixTheme.currentPreset.value;
    final accent = PlixTheme.plexGold;
    final isGlass = preset.isGlass;

    return Focus(
      focusNode: widget.focusNode,
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
                  key == LogicalKeyboardKey.gameButtonSelect ||
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
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: isGlass
              ? PlixTheme.glassBoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  isHighlighted: isHighlighted,
                  accent: accent,
                  borderWidth: isHighlighted ? 2.0 : 1.2,
                )
              : BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.cardFocused
                      : (preset.isOLED ? const Color(0xFF000000) : PlixTheme.card),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isHighlighted ? accent : PlixTheme.cardBorder,
                    width: isHighlighted ? 2.0 : 1.2,
                  ),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
          child: Stack(
            children: [
              if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(14)),
              Row(
                children: [
                  // Atmosphere Theme icon badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: preset.previewGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: Icon(preset.icon, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  // Title and Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              preset.name,
                              style: TextStyle(
                                color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Current Accent Chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                    PlixTheme.currentThemeOption.value.name,
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
                        const SizedBox(height: 4),
                        Text(
                          preset.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isHighlighted ? Colors.white : PlixTheme.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Edit Appearance & Themes Action Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isHighlighted ? accent : PlixTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isHighlighted ? accent : PlixTheme.cardBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: isHighlighted ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Edit Appearance & Themes',
                          style: TextStyle(
                            color: isHighlighted ? Colors.black : Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      setState(() => _isFocused = _node.hasFocus);
      if (_node.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final accent = PlixTheme.plexGold;
    final isGlass = PlixTheme.isGlass;

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
                  key == LogicalKeyboardKey.gameButtonSelect ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            if (widget.isInteractive && widget.onTap != null) {
              widget.onTap!();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.isInteractive ? widget.onTap : null,
        onHover: (hovered) {
          if (Platform.isWindows) setState(() => _isHovered = hovered);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: isGlass
              ? PlixTheme.glassBoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  isHighlighted: isHighlighted,
                  accent: accent,
                  borderWidth: isHighlighted ? 1.8 : 1.0,
                )
              : BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.cardFocused
                      : (PlixTheme.isOLED ? const Color(0xFF000000) : PlixTheme.card),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isHighlighted ? accent : PlixTheme.cardBorder,
                    width: isHighlighted ? 2.0 : 1.2,
                  ),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
          child: Stack(
            children: [
              if (isGlass) PlixTheme.buildGlassReflectionLayer(borderRadius: BorderRadius.circular(10)),
              widget.trailingBelow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        if (widget.trailing != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.trailing!,
                            style: TextStyle(
                              color: accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: const TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.isLoading) ...[
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(accent),
                            ),
                          ),
                        ] else if (widget.trailing != null) ...[
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isHighlighted ? accent : PlixTheme.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isHighlighted ? accent : PlixTheme.cardBorder,
                              ),
                            ),
                            child: Text(
                              widget.trailing!,
                              style: TextStyle(
                                color: isHighlighted ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
