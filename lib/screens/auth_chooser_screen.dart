import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import 'jellyfin_connect_screen.dart';
import 'login_screen.dart';
import '../services/plix_device_helper.dart';

class AuthChooserScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const AuthChooserScreen({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  State<AuthChooserScreen> createState() => _AuthChooserScreenState();
}

class _AuthChooserScreenState extends State<AuthChooserScreen> {
  final FocusNode _plexFocusNode = FocusNode();
  final FocusNode _jellyfinFocusNode = FocusNode();

  @override
  void dispose() {
    _plexFocusNode.dispose();
    _jellyfinFocusNode.dispose();
    super.dispose();
  }

  void _choosePlex() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  void _chooseJellyfin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => JellyfinConnectScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: isCompact ? 20 : 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: PlixTheme.plexGold,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 36),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'PLIX',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
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
                    icon: Icons.dns_rounded,
                    accentColor: PlixTheme.plexGold,
                    onTap: _choosePlex,
                    onRight: () => _jellyfinFocusNode.requestFocus(),
                  ),
                  _ProviderCard(
                    focusNode: _jellyfinFocusNode,
                    autofocus: false,
                    title: 'Jellyfin',
                    subtitle: 'Connect using your Jellyfin server and Quick Connect.',
                    icon: Icons.hub_rounded,
                    accentColor: const Color(0xFF00A4DC),
                    onTap: _chooseJellyfin,
                    onLeft: () => _plexFocusNode.requestFocus(),
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

class _ProviderCard extends StatefulWidget {
  final FocusNode focusNode;
  final bool autofocus;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _ProviderCard({
    required this.focusNode,
    required this.autofocus,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.onLeft,
    this.onRight,
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
                  child: Icon(widget.icon, color: widget.accentColor, size: 34),
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
