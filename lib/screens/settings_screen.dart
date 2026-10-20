import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/update_service.dart';
import '../widgets/plix_back_button.dart';

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
  final Map<String, FocusNode> _colorFocusNodes = {};
  final FocusNode _backButtonFocusNode = FocusNode();

  // Playback settings state
  bool _autoplayNextEpisode = true;
  bool _autoSkipIntro = false;
  bool _playTvThemes = true;
  final FocusNode _skipIntroFocusNode = FocusNode();
  final FocusNode _themeFocusNode = FocusNode();
  int _quickRewindSeconds = 10;
  int _skipAheadSeconds = 30;

  // Update settings state
  bool _autoCheckUpdates = false;
  bool _isCheckingUpdate = false;
  final FocusNode _autoUpdateFocusNode = FocusNode();
  final FocusNode _checkUpdateBtnFocusNode = FocusNode();

  final FocusNode _autoplayFocusNode = FocusNode();
  final FocusNode _rewindFocusNode = FocusNode();
  final FocusNode _skipFocusNode = FocusNode();
  final FocusNode _aboutServerFocusNode = FocusNode();
  final FocusNode _aboutClientFocusNode = FocusNode();
  final FocusNode _aboutVersionFocusNode = FocusNode();
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
    for (final opt in PlixTheme.colorOptions) {
      _colorFocusNodes[opt.id] = FocusNode();
    }
    _loadSettings();
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
    _scrollController.dispose();
    _backButtonFocusNode.dispose();
    _autoplayFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _themeFocusNode.dispose();
    _rewindFocusNode.dispose();
    _skipFocusNode.dispose();
    _autoUpdateFocusNode.dispose();
    _checkUpdateBtnFocusNode.dispose();
    _aboutServerFocusNode.dispose();
    _aboutClientFocusNode.dispose();
    _aboutVersionFocusNode.dispose();
    for (final node in _colorFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              child: Row(
                children: [
                  PlixBackButton(
                    focusNode: _backButtonFocusNode,
                    autofocus: false,
                    onDown: () {
                      _colorFocusNodes[PlixTheme.colorOptions.first.id]?.requestFocus();
                      _scrollToTop();
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
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                children: [
                  // Section 1: Theme Color
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: PlixTheme.plexGold, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Theme Accent Color',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select your preferred accent highlight color used throughout Plix.',
                    style: TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  ValueListenableBuilder<ThemeColorOption>(
                    valueListenable: PlixTheme.currentThemeOption,
                    builder: (context, currentOption, _) {
                      // 3 rows of 5 colors each (15 total)
                      return Column(
                        children: [
                          for (int row = 0; row < 3; row++) ...[
                            Row(
                              children: [
                                for (int col = 0; col < 5; col++) ...[
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final index = row * 5 + col;
                                        if (index >= PlixTheme.colorOptions.length) {
                                          return const SizedBox();
                                        }
                                        final opt = PlixTheme.colorOptions[index];
                                        return _ThemeColorTile(
                                          option: opt,
                                          isSelected: opt.id == currentOption.id,
                                          focusNode: _colorFocusNodes[opt.id]!,
                                          autofocus: !Platform.isWindows && index == 0,
                                          onSelect: () => PlixTheme.setTheme(opt),
                                          onFocusChange: (focused) {
                                            if (focused && !Platform.isWindows) _scrollToTop();
                                          },
                                          onUp: row == 0
                                              ? () => _backButtonFocusNode.requestFocus()
                                              : () {
                                                  final prevOpt = PlixTheme.colorOptions[(row - 1) * 5 + col];
                                                  _colorFocusNodes[prevOpt.id]?.requestFocus();
                                                },
                                          onDown: row == 2
                                              ? () => _autoplayFocusNode.requestFocus()
                                              : () {
                                                  final nextOpt = PlixTheme.colorOptions[(row + 1) * 5 + col];
                                                  _colorFocusNodes[nextOpt.id]?.requestFocus();
                                                },
                                        );
                                      },
                                    ),
                                  ),
                                  if (col < 4) const SizedBox(width: 12),
                                ],
                              ],
                            ),
                            if (row < 2) const SizedBox(height: 12),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 36),
                  const Divider(color: PlixTheme.cardBorder),
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
                      _colorFocusNodes[PlixTheme.colorOptions[10].id]?.requestFocus();
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
                    onDown: () => _autoUpdateFocusNode.requestFocus(),
                    title: 'Skip Ahead Duration',
                    subtitle: 'Seconds skipped forward when pressing D-pad Right or Fast Forward on remote',
                    trailing: '${_skipAheadSeconds}s',
                    isInteractive: true,
                    onTap: _cycleSkip,
                  ),

                  const SizedBox(height: 36),
                  const Divider(color: PlixTheme.cardBorder),
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
                    onUp: () => _skipFocusNode.requestFocus(),
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
                  const Divider(color: PlixTheme.cardBorder),
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
                    title: 'App Version',
                    subtitle: Platform.isWindows
                        ? 'Plix for Windows (MediaKit mpv)'
                        : 'Plix for Android TV (Media3 ExoPlayer)',
                    trailing: 'v${UpdateService.currentVersion}',
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
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final ValueChanged<bool>? onFocusChange;

  const _ThemeColorTile({
    required this.option,
    required this.isSelected,
    required this.focusNode,
    this.autofocus = false,
    required this.onSelect,
    this.onUp,
    this.onDown,
    this.onFocusChange,
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
      widget.onFocusChange?.call(_isFocused);
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
      autofocus: widget.autofocus,
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
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
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
                child: Text(
                  widget.option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
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
      if (_isFocused && !Platform.isWindows) {
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
          child: Row(
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
                  ],
                ),
              ),
              if (widget.trailing != null && widget.trailing!.isNotEmpty) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      Text(
                        widget.trailing!,
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.isInteractive) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: PlixTheme.plexGold.withOpacity(0.8),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}