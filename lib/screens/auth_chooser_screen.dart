import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/plix_back_button.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/profile_service.dart';
import 'home_screen.dart';
import 'jellyfin_connect_screen.dart';
import 'login_screen.dart';
import '../services/plix_device_helper.dart';

class AuthChooserScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;
  final bool isCreatingProfile;
  final String? draftProfileId;
  final String? previousProfileId;

  const AuthChooserScreen({
    super.key,
    required this.authService,
    required this.serverService,
    this.isCreatingProfile = false,
    this.draftProfileId,
    this.previousProfileId,
  });

  @override
  State<AuthChooserScreen> createState() => _AuthChooserScreenState();
}

class _AuthChooserScreenState extends State<AuthChooserScreen> {
  final FocusNode _plexFocusNode = FocusNode();
  final FocusNode _jellyfinFocusNode = FocusNode();
  final FocusNode _backFocusNode = FocusNode();
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    PlixTheme.resetToDefaultModern();
  }

  @override
  void dispose() {
    _plexFocusNode.dispose();
    _jellyfinFocusNode.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  Future<void> _cancelCreation() async {
    if (widget.draftProfileId != null) {
      await ProfileService.instance.cancelProfileCreation(
        widget.draftProfileId!,
        restoreProfileId: widget.previousProfileId,
      );
    } else if (widget.previousProfileId != null) {
      await ProfileService.instance.setActiveProfile(widget.previousProfileId!);
    }
    widget.authService.clearCache();
    HomeScreen.clearMemoryCaches();
    await PlixTheme.loadSavedTheme();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  void _choosePlex() async {
    if (_isNavigating) return;
    _isNavigating = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          isCreatingProfile: widget.isCreatingProfile,
          draftProfileId: widget.draftProfileId,
          previousProfileId: widget.previousProfileId,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  void _chooseJellyfin() async {
    if (_isNavigating) return;
    _isNavigating = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JellyfinConnectScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          isCreatingProfile: widget.isCreatingProfile,
          draftProfileId: widget.draftProfileId,
          previousProfileId: widget.previousProfileId,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    return PopScope(
      canPop: !widget.isCreatingProfile,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _cancelCreation();
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        body: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: isCompact ? 20 : 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PlixAppLogo(
                          size: 48,
                          showWordmark: false,
                          borderRadius: 12,
                          glow: true,
                        ),
                        SizedBox(width: 14),
                        PlixWordmark(fontSize: 34),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome to Plix',
                      style: TextStyle(
                        color: PlixTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose your media provider to get started.',
                      style: TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Provider Cards
                    Wrap(
                      spacing: 28,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        _ProviderCard(
                          focusNode: _plexFocusNode,
                          autofocus: true,
                          title: 'Plex',
                          subtitle: 'Connect using your Plex account and link code.',
                          logoWidget: PlexLogo(size: 34, color: PlixTheme.plexGold),
                          accentColor: PlixTheme.plexGold,
                          onTap: _choosePlex,
                          onRight: () => _jellyfinFocusNode.requestFocus(),
                          onUp: widget.isCreatingProfile ? () => _backFocusNode.requestFocus() : null,
                        ),
                        _ProviderCard(
                          focusNode: _jellyfinFocusNode,
                          autofocus: false,
                          title: 'Jellyfin',
                          subtitle: 'Connect using your Jellyfin server and Quick Connect.',
                          logoWidget: const JellyfinLogo(size: 34, color: Color(0xFF8E51DC)),
                          accentColor: const Color(0xFF8E51DC),
                          onTap: _chooseJellyfin,
                          onLeft: () => _plexFocusNode.requestFocus(),
                          onUp: widget.isCreatingProfile ? () => _backFocusNode.requestFocus() : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isCreatingProfile)
              Positioned(
                top: 16,
                left: 20,
                child: PlixBackButton(
                  focusNode: _backFocusNode,
                  onPressed: _cancelCreation,
                  onDown: () => _plexFocusNode.requestFocus(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatefulWidget {
  final FocusNode focusNode;
  final bool autofocus;
  final String title;
  final String subtitle;
  final Widget logoWidget;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;

  const _ProviderCard({
    required this.focusNode,
    required this.autofocus,
    required this.title,
    required this.subtitle,
    required this.logoWidget,
    required this.accentColor,
    required this.onTap,
    this.onLeft,
    this.onRight,
    this.onUp,
  });

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeGlow = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: activeGlow ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) {
            setState(() {
              _isHovered = hovered;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: PlixDeviceHelper.isCompact(context)
                ? (MediaQuery.of(context).size.width - 32).clamp(260.0, 340.0)
                : 300,
            padding: EdgeInsets.symmetric(
              horizontal: PlixDeviceHelper.isCompact(context) ? 20 : 28,
              vertical: PlixDeviceHelper.isCompact(context) ? 24 : 32,
            ),
            decoration: BoxDecoration(
              color: activeGlow ? PlixTheme.cardFocused : PlixTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: activeGlow ? widget.accentColor : PlixTheme.cardBorder,
                width: activeGlow ? 2.5 : 1.0,
              ),
              boxShadow: activeGlow
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.accentColor.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(child: widget.logoWidget),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: activeGlow ? widget.accentColor : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Connect',
                    style: TextStyle(
                      color: activeGlow ? Colors.black : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
