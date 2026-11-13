import 'profiles_screen.dart';
import '../services/profile_service.dart';
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
import '../widgets/plix_button.dart';
import '../services/plix_device_helper.dart';
import '../services/native_player_service.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import 'appearance_screen.dart';
import 'favorite_libraries_screen.dart';
import 'server_select_screen.dart';

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

  // Profiles settings state
  bool _alwaysAskProfile = false;
  final FocusNode _alwaysAskProfileFocusNode = FocusNode();
  final FocusNode _editProfilesFocusNode = FocusNode();

  // Playback settings state
  bool _anonymousMode = false;
  final FocusNode _anonymousModeFocusNode = FocusNode();
  bool _autoplayNextEpisode = true;
  bool _autoSkipIntro = false;
  bool _playTvThemes = true;
  bool _continuePlaybackScreenOff = false;
  bool _showTvCastCrew = false; // Default false
  final FocusNode _tvCastCrewFocusNode = FocusNode();
  final FocusNode _skipIntroFocusNode = FocusNode();
  final FocusNode _themeFocusNode = FocusNode();
  final FocusNode _screenOffFocusNode = FocusNode();
  final FocusNode _hwdecFocusNode = FocusNode();
  String _hwdecMode = NativePlayerService.hwdecMode;
  int _quickRewindSeconds = 10;
  int _skipAheadSeconds = 30;

  // Update settings state
  bool _autoCheckUpdates = true;
  bool _isCheckingUpdate = false;
  final FocusNode _autoUpdateFocusNode = FocusNode();
  final FocusNode _checkUpdateBtnFocusNode = FocusNode();

  final FocusNode _autoplayFocusNode = FocusNode();
  final FocusNode _autoplayTriggerFocusNode = FocusNode();
  int _autoplayTriggerSeconds = 20;
  final FocusNode _rewindFocusNode = FocusNode();
  final FocusNode _skipFocusNode = FocusNode();
  final FocusNode _aboutServerFocusNode = FocusNode();
  final FocusNode _manageLibrariesFocusNode = FocusNode();
  final FocusNode _aboutClientFocusNode = FocusNode();
  final FocusNode _aboutVersionFocusNode = FocusNode();
  final FocusNode _aboutWebsiteFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    PlixTheme.themeRevision.addListener(_onThemeChanged);
    _loadSettings();
    _loadConnectedServers();

    // Default focus to the appearance tile for immediate accessibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _appearanceTileFocusNode.requestFocus();
    });
  }

  List<PlexServer> _allConnectedServers = [];

  Future<void> _loadConnectedServers() async {
    try {
      final authService = PlexAuthService();
      final serverService = PlexServerService(authService: authService);
      final token = await authService.getSavedToken() ?? '';
      final servers = await serverService.fetchServers(token);
      if (mounted) {
        setState(() {
          _allConnectedServers = servers;
        });
      }
    } catch (_) {}
  }

  String get _connectedServerTitle {
    if (_allConnectedServers.length > 1) {
      return 'Connected Servers (${_allConnectedServers.length})';
    }
    return 'Connected Server';
  }

  String get _connectedServerSubtitle {
    if (_allConnectedServers.isEmpty) {
      return widget.server?.name ?? 'Connected';
    }
    return _allConnectedServers.map((s) {
      final type = s.isJellyfin ? 'Jellyfin' : 'Plex';
      return '${s.name} ($type)';
    }).join(', ');
  }

  String? get _connectedServerTrailing {
    if (_allConnectedServers.isEmpty) {
      return widget.server?.activeConnectionUri ??
          (widget.server?.connections.isNotEmpty == true
              ? widget.server!.connections.first.address
              : 'Connected');
    }
    final plexCount = _allConnectedServers.where((s) => !s.isJellyfin).length;
    final jfCount = _allConnectedServers.where((s) => s.isJellyfin).length;

    if (plexCount > 0 && jfCount > 0) {
      return 'Plex & Jellyfin';
    } else if (jfCount > 0) {
      return '$jfCount Jellyfin server${jfCount > 1 ? 's' : ''}';
    } else if (plexCount > 0) {
      return '$plexCount Plex server${plexCount > 1 ? 's' : ''}';
    }
    return widget.server?.activeConnectionUri;
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
        _anonymousMode = prefs.getBool(ProfileService.key('anonymous_mode')) ?? prefs.getBool('anonymous_mode') ?? false;
        _autoplayNextEpisode = prefs.getBool(ProfileService.key('autoplay_next_episode')) ?? prefs.getBool('autoplay_next_episode') ?? true;
        _autoplayTriggerSeconds = prefs.getInt(ProfileService.key('autoplay_trigger_seconds')) ?? prefs.getInt('autoplay_trigger_seconds') ?? 20;
        _autoSkipIntro = prefs.getBool(ProfileService.key('auto_skip_intro')) ?? prefs.getBool('auto_skip_intro') ?? false;
        _playTvThemes = prefs.getBool(ProfileService.key('play_tv_show_themes')) ?? prefs.getBool('play_tv_show_themes') ?? true;
        _continuePlaybackScreenOff = prefs.getBool(ProfileService.key('continue_playback_screen_off')) ?? prefs.getBool('continue_playback_screen_off') ?? false;
        _showTvCastCrew = prefs.getBool(ProfileService.key('tv_player_cast_crew')) ?? prefs.getBool('tv_player_cast_crew') ?? false;
        _hwdecMode = prefs.getString('desktop_hwdec_mode') ?? NativePlayerService.hwdecMode;
        _quickRewindSeconds = prefs.getInt(ProfileService.key('quick_rewind_seconds')) ?? prefs.getInt('quick_rewind_seconds') ?? 10;
        _skipAheadSeconds = prefs.getInt(ProfileService.key('skip_ahead_seconds')) ?? prefs.getInt('skip_ahead_seconds') ?? 30;
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
    await prefs.setBool(ProfileService.key('play_tv_show_themes'), newVal);
  }

  String get _hwdecLabel {
    switch (_hwdecMode) {
      case 'no':
        return 'Software (Pure CPU - Recommended)';
      case 'auto-safe':
        return 'Auto-Safe (Copy-Back GPU)';
      case 'auto':
        return 'Auto (Direct GPU)';
      default:
        return Platform.isLinux
            ? 'Software (Pure CPU - Recommended)'
            : 'Auto-Safe (Copy-Back GPU)';
    }
  }

  Future<void> _cycleHwdecMode() async {
    String next;
    if (_hwdecMode == 'no') {
      next = 'auto-safe';
    } else if (_hwdecMode == 'auto-safe') {
      next = 'auto';
    } else {
      next = 'no';
    }
    setState(() => _hwdecMode = next);
    await NativePlayerService().setHwdecMode(next);
  }

  void _switchServer() async {
    final authService = PlexAuthService();
    final serverService = PlexServerService(authService: authService);
    final token = await authService.getSavedToken() ?? '';
    final servers = await serverService.fetchServers(token);
    if (!mounted) return;
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerSelectScreen(
          servers: servers,
          authService: authService,
          serverService: serverService,
          currentServer: widget.server,
        ),
      ),
    );
  }

  void _openFavoriteLibraries() async {
    final authService = PlexAuthService();
    final serverService = PlexServerService(authService: authService);
    final token = await authService.getSavedToken() ?? '';
    final servers = await serverService.fetchServers(token);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteLibrariesScreen(
          authService: authService,
          serverService: serverService,
          servers: servers,
          primaryServer: widget.server,
          isInitialSetup: false,
        ),
      ),
    );
  }

  Future<void> _openWebsite(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.plix.plix/updater');
        await channel.invokeMethod('openUrl', {'url': url});
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      }
      _showToast('Opening $url');
    } catch (_) {
      _showToast('URL copied to clipboard: $url');
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

  Future<void> _toggleAlwaysAskProfile() async {
    final newVal = !_alwaysAskProfile;
    setState(() => _alwaysAskProfile = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plix_always_ask_profile', newVal);
  }

  void _openProfilesScreen() {
    final authService = PlexAuthService();
    final serverService = PlexServerService(authService: authService);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilesScreen(
          authService: authService,
          serverService: serverService,
        ),
      ),
    );
  }

  Future<void> _toggleAnonymousMode() async {
    final newVal = !_anonymousMode;
    setState(() => _anonymousMode = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('anonymous_mode'), newVal);
  }

  Future<void> _toggleAutoplay() async {
    final newVal = !_autoplayNextEpisode;
    setState(() => _autoplayNextEpisode = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('autoplay_next_episode'), newVal);
  }

  Future<void> _cycleAutoplayTriggerSeconds() async {
    const options = [10, 15, 20, 30, 45, 60];
    final currentIdx = options.indexOf(_autoplayTriggerSeconds);
    final nextVal = currentIdx == -1 ? 20 : options[(currentIdx + 1) % options.length];
    setState(() => _autoplayTriggerSeconds = nextVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ProfileService.key('autoplay_trigger_seconds'), nextVal);
  }

  Future<void> _toggleAutoSkipIntro() async {
    final newVal = !_autoSkipIntro;
    setState(() => _autoSkipIntro = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('auto_skip_intro'), newVal);
  }

  Future<void> _toggleContinuePlaybackScreenOff() async {
    final newVal = !_continuePlaybackScreenOff;
    setState(() => _continuePlaybackScreenOff = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('continue_playback_screen_off'), newVal);
    try {
      await NativePlayerService().setScreenOffPlayback(newVal);
    } catch (_) {}
  }

  Future<void> _toggleShowTvCastCrew() async {
    final newVal = !_showTvCastCrew;
    setState(() => _showTvCastCrew = newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('tv_player_cast_crew'), newVal);
  }

  Future<void> _cycleRewind() async {
    const options = [5, 10, 15, 20, 30];
    final currentIdx = options.indexOf(_quickRewindSeconds);
    final nextVal = options[(currentIdx + 1) % options.length];
    setState(() => _quickRewindSeconds = nextVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ProfileService.key('quick_rewind_seconds'), nextVal);
  }

  Future<void> _cycleSkip() async {
    const options = [10, 15, 30, 45, 60];
    final currentIdx = options.indexOf(_skipAheadSeconds);
    final nextVal = options[(currentIdx + 1) % options.length];
    setState(() => _skipAheadSeconds = nextVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ProfileService.key('skip_ahead_seconds'), nextVal);
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
    _alwaysAskProfileFocusNode.dispose();
    _editProfilesFocusNode.dispose();
    _anonymousModeFocusNode.dispose();
    _autoplayFocusNode.dispose();
    _autoplayTriggerFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _themeFocusNode.dispose();
    _screenOffFocusNode.dispose();
    _tvCastCrewFocusNode.dispose();
    _hwdecFocusNode.dispose();
    _rewindFocusNode.dispose();
    _skipFocusNode.dispose();
    _autoUpdateFocusNode.dispose();
    _checkUpdateBtnFocusNode.dispose();
    _aboutServerFocusNode.dispose();
    _manageLibrariesFocusNode.dispose();
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
                  if (!Platform.isAndroid || PlixDeviceHelper.isTelevision || MediaQuery.of(context).orientation == Orientation.landscape) ...[
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
                  ],
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
                    onDown: () => _alwaysAskProfileFocusNode.requestFocus(),
                    onSelect: _openAppearanceScreen,
                  ),

                  const SizedBox(height: 28),
                  Divider(color: PlixTheme.cardBorder),
                  const SizedBox(height: 20),

                  // Section: Profiles
                  Row(
                    children: [
                      Icon(Icons.manage_accounts_rounded, color: PlixTheme.plexGold, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Profiles',
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
                    focusNode: _alwaysAskProfileFocusNode,
                    onUp: () => _appearanceTileFocusNode.requestFocus(),
                    onDown: () => _editProfilesFocusNode.requestFocus(),
                    title: "Always ask who's watching on app open",
                    subtitle: "Show the profile selection screen whenever Plix starts",
                    trailing: _alwaysAskProfile ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _toggleAlwaysAskProfile,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _editProfilesFocusNode,
                    onUp: () => _alwaysAskProfileFocusNode.requestFocus(),
                    onDown: () => _anonymousModeFocusNode.requestFocus(),
                    title: 'Edit Profiles',
                    subtitle: "Open Who's Watching to switch profiles, edit names, or customize PINs",
                    trailing: 'Manage',
                    isInteractive: true,
                    onTap: _openProfilesScreen,
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
                    focusNode: _anonymousModeFocusNode,
                    onUp: () => _editProfilesFocusNode.requestFocus(),
                    onDown: () => _autoplayFocusNode.requestFocus(),
                    title: 'Anonymous Mode',
                    subtitle: 'Stream content without reporting progress, updating continue watching, or adding to watch history',
                    trailing: _anonymousMode ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _toggleAnonymousMode,
                  ),
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _autoplayFocusNode,
                    onUp: () => _anonymousModeFocusNode.requestFocus(),
                    onDown: () => _autoplayNextEpisode
                        ? _autoplayTriggerFocusNode.requestFocus()
                        : _skipIntroFocusNode.requestFocus(),
                    title: 'Autoplay Next Episode',
                    subtitle: 'Automatically start the next episode with countdown when an episode finishes',
                    trailing: _autoplayNextEpisode ? 'Enabled' : 'Disabled',
                    isInteractive: true,
                    onTap: _toggleAutoplay,
                  ),
                  if (_autoplayNextEpisode) ...[
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      focusNode: _autoplayTriggerFocusNode,
                      onUp: () => _autoplayFocusNode.requestFocus(),
                      onDown: () => _skipIntroFocusNode.requestFocus(),
                      title: 'Autoplay Prompt Timing',
                      subtitle: 'How many seconds before the end of an episode the autoplay countdown appears',
                      trailing: '${_autoplayTriggerSeconds}s',
                      isInteractive: true,
                      onTap: _cycleAutoplayTriggerSeconds,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _SettingsActionTile(
                    focusNode: _skipIntroFocusNode,
                    onUp: () => _autoplayNextEpisode
                        ? _autoplayTriggerFocusNode.requestFocus()
                        : _autoplayFocusNode.requestFocus(),
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
                    onDown: () => isMobile
                        ? _screenOffFocusNode.requestFocus()
                        : (PlixDeviceHelper.isDesktop
                            ? _hwdecFocusNode.requestFocus()
                            : (PlixDeviceHelper.isTelevision
                                ? _tvCastCrewFocusNode.requestFocus()
                                : _autoUpdateFocusNode.requestFocus())),
                    title: 'Skip Ahead Duration',
                    subtitle: 'Seconds skipped forward when pressing D-pad Right or Fast Forward on remote',
                    trailing: '${_skipAheadSeconds}s',
                    isInteractive: true,
                    onTap: _cycleSkip,
                  ),
                  if (PlixDeviceHelper.isTelevision) ...[
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      focusNode: _tvCastCrewFocusNode,
                      onUp: () => _skipFocusNode.requestFocus(),
                      onDown: () => _autoUpdateFocusNode.requestFocus(),
                      title: 'Cast & Crew in Player',
                      subtitle: 'Display cast & crew quick view row below playback controls on TV',
                      trailing: _showTvCastCrew ? 'Enabled' : 'Disabled',
                      isInteractive: true,
                      onTap: _toggleShowTvCastCrew,
                    ),
                  ],
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
                  ] else if (PlixDeviceHelper.isDesktop) ...[
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      focusNode: _hwdecFocusNode,
                      onUp: () => _skipFocusNode.requestFocus(),
                      onDown: () => _autoUpdateFocusNode.requestFocus(),
                      title: 'Hardware Video Decoding',
                      subtitle: 'Video decoding engine (Software pure CPU recommended on Linux to match official Plex app and eliminate driver pixelation)',
                      trailing: _hwdecLabel,
                      isInteractive: true,
                      onTap: _cycleHwdecMode,
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
                    onUp: () => isMobile
                        ? _screenOffFocusNode.requestFocus()
                        : (PlixDeviceHelper.isDesktop
                            ? _hwdecFocusNode.requestFocus()
                            : (PlixDeviceHelper.isTelevision
                                ? _tvCastCrewFocusNode.requestFocus()
                                : _skipFocusNode.requestFocus())),
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

                  if (widget.server != null || _allConnectedServers.isNotEmpty) ...[
                    _SettingsActionTile(
                      focusNode: _aboutServerFocusNode,
                      onUp: () => _checkUpdateBtnFocusNode.requestFocus(),
                      onDown: () => _manageLibrariesFocusNode.requestFocus(),
                      title: _connectedServerTitle,
                      subtitle: _connectedServerSubtitle,
                      trailing: _connectedServerTrailing,
                      trailingWidget: PlixButton(
                        isPrimary: false,
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: 'Customize Servers',
                        onPressed: _switchServer,
                      ),
                      isInteractive: true,
                      onTap: _switchServer,
                      trailingBelow: isCompact,
                    ),
                    const SizedBox(height: 10),
                    _SettingsActionTile(
                      focusNode: _manageLibrariesFocusNode,
                      onUp: () => _aboutServerFocusNode.requestFocus(),
                      onDown: () => _aboutClientFocusNode.requestFocus(),
                      title: 'Favorite Libraries',
                      subtitle: 'Choose which libraries appear on Home and Navigation',
                      trailingWidget: PlixButton(
                        isPrimary: false,
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        icon: const Icon(Icons.favorite_rounded, size: 16),
                        label: 'Manage Libraries',
                        onPressed: _openFavoriteLibraries,
                      ),
                      isInteractive: true,
                      onTap: _openFavoriteLibraries,
                      trailingBelow: isCompact,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SettingsActionTile(
                    focusNode: _aboutClientFocusNode,
                    onUp: () => widget.server != null
                        ? _manageLibrariesFocusNode.requestFocus()
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
                        : (Platform.isLinux
                            ? 'Plix for Linux (MediaKit mpv)'
                            : (PlixDeviceHelper.isTelevision
                                ? 'Plix for Android TV (Media3 ExoPlayer)'
                                : 'Plix for Android (Media3 ExoPlayer)')),
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
        final scrollable = Scrollable.maybeOf(context);
        if (scrollable != null && scrollable.position.hasContentDimensions) {
          if (scrollable.position.pixels > 0) {
            scrollable.position.animateTo(
              0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
            );
          }
        }
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
              Builder(
                builder: (context) {
                  final isCompact = PlixDeviceHelper.isCompact(context);
                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: preset.previewGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                              child: Icon(preset.icon, size: 24, color: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    style: TextStyle(
                                      color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
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
                            ),
                            Icon(Icons.chevron_right_rounded, color: isHighlighted ? accent : Colors.white38, size: 22),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          preset.description,
                          maxLines: 2,
                          style: TextStyle(
                            color: isHighlighted ? Colors.white70 : PlixTheme.textSecondary,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isHighlighted ? accent : PlixTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isHighlighted ? accent : PlixTheme.cardBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 15,
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
                    );
                  }

                  return Row(
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
                  );
                },
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
  final Widget? trailingWidget;
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
    this.trailingWidget,
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            if (widget.trailingWidget != null) ...[
                              const SizedBox(width: 10),
                              widget.trailingWidget!,
                            ],
                          ],
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
                        if (widget.trailingWidget != null) ...[
                          const SizedBox(width: 14),
                          widget.trailingWidget!,
                        ] else if (widget.isLoading) ...[
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
