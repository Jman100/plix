import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import 'favorite_libraries_screen.dart';
import 'jellyfin_connect_screen.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../widgets/brand_logo.dart';
import '../services/plix_device_helper.dart';

class ServerSelectScreen extends StatefulWidget {
  final List<PlexServer> servers;
  final PlexAuthService authService;
  final PlexServerService serverService;
  final PlexServer? currentServer;

  const ServerSelectScreen({
    super.key,
    required this.servers,
    required this.authService,
    required this.serverService,
    this.currentServer,
  });

  @override
  State<ServerSelectScreen> createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> {
  bool _isNavigating = false;
  late List<PlexServer> _servers;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _favBtnFocusNode = FocusNode();
  final FocusNode _jellyfinBtnFocusNode = FocusNode();
  final FocusNode _plexBtnFocusNode = FocusNode();
  final Map<String, FocusNode> _cardFocusNodes = {};
  final Map<String, FocusNode> _removeFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _servers = List.from(widget.servers);
    _favBtnFocusNode.addListener(_onTopFocus);
    _jellyfinBtnFocusNode.addListener(_onTopFocus);
    _plexBtnFocusNode.addListener(_onTopFocus);
  }

  void _onTopFocus() {
    if (_favBtnFocusNode.hasFocus || _jellyfinBtnFocusNode.hasFocus || _plexBtnFocusNode.hasFocus) {
      _scrollToTop();
    }
  }

  @override
  void dispose() {
    _favBtnFocusNode.removeListener(_onTopFocus);
    _jellyfinBtnFocusNode.removeListener(_onTopFocus);
    _plexBtnFocusNode.removeListener(_onTopFocus);
    _scrollController.dispose();
    _favBtnFocusNode.dispose();
    _jellyfinBtnFocusNode.dispose();
    _plexBtnFocusNode.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    for (final node in _removeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _openFavoriteLibraries() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteLibrariesScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          servers: _servers,
          primaryServer: null,
          isInitialSetup: false,
        ),
      ),
    );
    if (result == true && mounted) {
      // Refresh server list if needed
      _refreshServers();
    }
  }

  Future<void> _refreshServers() async {
    try {
      final token = await widget.authService.getSavedToken() ?? '';
      final updated = await widget.serverService.fetchServers(token);
      if (mounted) {
        setState(() {
          _servers = updated;
        });
      }
    } catch (_) {}
  }

  void _openJellyfinSignIn() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JellyfinConnectScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
    if (mounted) _refreshServers();
    } finally {
      _isNavigating = false;
    }
  }

  void _openPlexSignIn() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            authService: widget.authService,
            serverService: widget.serverService,
          ),
        ),
      );
      if (mounted) _refreshServers();
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _confirmRemoveServer(PlexServer server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PlixTheme.surface,
        title: const Text('Remove Server', style: TextStyle(color: PlixTheme.textPrimary)),
        content: Text(
          'Are you sure you want to remove "${server.name}"?',
          style: const TextStyle(color: PlixTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: PlixTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.serverService.removeServer(server.clientIdentifier);
      if (mounted) {
        setState(() {
          _servers.removeWhere((s) => s.clientIdentifier == server.clientIdentifier);
        });
      }
    }
  }

  void _navigateToHome() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      PlexServer? targetServer = widget.currentServer;
      if (targetServer == null && _servers.isNotEmpty) {
        final activeId = await widget.serverService.getActiveServerId();
        targetServer = _servers.firstWhere(
          (s) => s.clientIdentifier == activeId,
          orElse: () => _servers.first,
        );
      }
      if (targetServer != null && mounted) {
        await widget.serverService.setActiveServerId(targetServer.clientIdentifier);
        await widget.serverService.testAndResolveBestConnection(targetServer);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              server: targetServer!,
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
          (route) => false,
        );
      }
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    final isCompact = PlixDeviceHelper.isCompact(context);

    return PopScope(
      canPop: canGoBack || _servers.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_servers.isNotEmpty) {
          _navigateToHome();
        }
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        appBar: AppBar(
          title: const Text('Customize Servers'),
          automaticallyImplyLeading: canGoBack,
          leading: canGoBack
              ? null
              : (_servers.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: _navigateToHome,
                    )
                  : null),
        ),
      body: Center(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: isCompact ? 16 : 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Connected Servers',
                  style: TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'All servers you have access to are connected at once. You can connect additional servers using the buttons below, or customize your favorite libraries, which will determine which libraries appear in the navigation menu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // Slim Buttons for adding new servers
                Container(
                  constraints: BoxConstraints(maxWidth: isCompact ? 420 : 752),
                  child: isCompact
                      ? Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: _SlimTopButton(
                                title: 'Connect to New Jellyfin',
                                logo: const JellyfinLogo(size: 20, color: Color(0xFF8E51DC)),
                                accentColor: const Color(0xFF8E51DC),
                                onPressed: _openJellyfinSignIn,
                                focusNode: _jellyfinBtnFocusNode,
                                onDown: () => _plexBtnFocusNode.requestFocus(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: _SlimTopButton(
                                title: 'Connect to New Plex',
                                logo: const PlexLogo(size: 20, color: Color(0xFFE5A00D)),
                                accentColor: const Color(0xFFE5A00D),
                                onPressed: _openPlexSignIn,
                                focusNode: _plexBtnFocusNode,
                                onUp: () => _jellyfinBtnFocusNode.requestFocus(),
                                onDown: () => _favBtnFocusNode.requestFocus(),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _SlimTopButton(
                                title: 'Connect to New Jellyfin',
                                logo: const JellyfinLogo(size: 20, color: Color(0xFF8E51DC)),
                                accentColor: const Color(0xFF8E51DC),
                                onPressed: _openJellyfinSignIn,
                                focusNode: _jellyfinBtnFocusNode,
                                onDown: () => _favBtnFocusNode.requestFocus(),
                                onRight: () => _plexBtnFocusNode.requestFocus(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _SlimTopButton(
                                title: 'Connect to New Plex',
                                logo: const PlexLogo(size: 20, color: Color(0xFFE5A00D)),
                                accentColor: const Color(0xFFE5A00D),
                                onPressed: _openPlexSignIn,
                                focusNode: _plexBtnFocusNode,
                                onDown: () => _favBtnFocusNode.requestFocus(),
                                onLeft: () => _jellyfinBtnFocusNode.requestFocus(),
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 14),

                // Manage Favorite Libraries Button placed below Connect buttons
                Container(
                  constraints: BoxConstraints(maxWidth: isCompact ? 420 : 752),
                  child: _ManageFavoriteButton(
                    focusNode: _favBtnFocusNode,
                    autofocus: true,
                    onPressed: _openFavoriteLibraries,
                    onUp: () => _jellyfinBtnFocusNode.requestFocus(),
                    onDown: () => _focusFirstCard(),
                  ),
                ),

                const SizedBox(height: 32),

                // Server List Header
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.dns_rounded, color: PlixTheme.plexGold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Servers (${_servers.length})',
                        style: const TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Unified Server Cards List (no Connect or Pin buttons!)
                _buildServerGrid(isCompact),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  void _focusFirstCard() {
    if (_servers.isNotEmpty) {
      _cardFocusNodes[_servers.first.clientIdentifier]?.requestFocus();
    }
  }

  Widget _buildServerGrid(bool isCompact) {
    if (_servers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Text(
          'No servers currently connected.',
          style: TextStyle(color: PlixTheme.textSecondary),
        ),
      );
    }

    if (isCompact) {
      return Column(
        children: [
          for (int i = 0; i < _servers.length; i++) ...[
            Builder(builder: (context) {
              final server = _servers[i];
              final node = _cardFocusNodes.putIfAbsent(
                server.clientIdentifier,
                () => FocusNode(debugLabel: 'server_${server.name}'),
              );
              return Container(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ServerCard(
                  server: server,
                  focusNode: node,
                  cardWidth: double.infinity,
                  onLongPress: server.isJellyfin ? () => _confirmRemoveServer(server) : null,
                  onUp: i == 0 ? () => _favBtnFocusNode.requestFocus() : null,
                  onTap: _openFavoriteLibraries,
                ),
              );
            }),
          ],
        ],
      );
    }

    // Grid layout for TV and desktop
    final rowCount = (_servers.length / 3).ceil();
    const double cardWidth = 240.0;
    const double spacing = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int r = 0; r < rowCount; r++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int c = 0; c < 3; c++) ...[
                Builder(
                  builder: (context) {
                    final index = r * 3 + c;
                    if (index >= _servers.length) {
                      return const SizedBox(width: cardWidth);
                    }
                    final server = _servers[index];
                    final node = _cardFocusNodes.putIfAbsent(
                      server.clientIdentifier,
                      () => FocusNode(debugLabel: 'server_${server.name}'),
                    );

                    VoidCallback? onLeft;
                    if (c > 0) {
                      final prev = _servers[index - 1];
                      onLeft = () => _cardFocusNodes[prev.clientIdentifier]?.requestFocus();
                    }

                    VoidCallback? onRight;
                    if (c < 2 && index + 1 < _servers.length) {
                      final next = _servers[index + 1];
                      onRight = () => _cardFocusNodes[next.clientIdentifier]?.requestFocus();
                    }

                    VoidCallback? onUp;
                    if (r > 0) {
                      final above = _servers[(r - 1) * 3 + c];
                      onUp = () => _cardFocusNodes[above.clientIdentifier]?.requestFocus();
                    } else {
                      onUp = () => _favBtnFocusNode.requestFocus();
                    }

                    VoidCallback? onDown;
                    if (r < rowCount - 1) {
                      final nextRow = (r + 1) * 3 + c;
                      final target = nextRow < _servers.length ? _servers[nextRow] : _servers.last;
                      onDown = () => _cardFocusNodes[target.clientIdentifier]?.requestFocus();
                    }

                    return _ServerCard(
                      server: server,
                      focusNode: node,
                      cardWidth: cardWidth,
                      onLongPress: server.isJellyfin ? () => _confirmRemoveServer(server) : null,
                      onTap: _openFavoriteLibraries,
                      onUp: onUp,
                      onDown: onDown,
                      onLeft: onLeft,
                      onRight: onRight,
                    );
                  },
                ),
                if (c < 2) const SizedBox(width: spacing),
              ],
            ],
          ),
          if (r < rowCount - 1) const SizedBox(height: spacing),
        ],
      ],
    );
  }
}

class _SlimTopButton extends StatefulWidget {
  final String title;
  final Widget logo;
  final Color accentColor;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _SlimTopButton({
    required this.title,
    required this.logo,
    required this.accentColor,
    required this.onPressed,
    this.focusNode,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_SlimTopButton> createState() => _SlimTopButtonState();
}

class _SlimTopButtonState extends State<_SlimTopButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (h) => setState(() => _isHovered = h),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? widget.accentColor : PlixTheme.cardBorder,
              width: isHighlighted ? 2.5 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.logo,
              const SizedBox(width: 10),
              Text(
                widget.title,
                style: TextStyle(
                  color: isHighlighted ? Colors.white : Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  final PlexServer server;
  final FocusNode focusNode;
  final double cardWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _ServerCard({
    required this.server,
    required this.focusNode,
    required this.cardWidth,
    this.onTap,
    this.onLongPress,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      if (widget.focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.15,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isJf = widget.server.isJellyfin;
    final brandColor = isJf ? const Color(0xFF8E51DC) : const Color(0xFFE5A00D);
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onTap?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHover: (h) => setState(() => _isHovered = h),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.cardWidth,
          height: widget.cardWidth == double.infinity ? null : 116,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted ? brandColor : PlixTheme.cardBorder,
              width: isHighlighted ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isHighlighted ? brandColor.withOpacity(0.35) : Colors.black.withOpacity(0.3),
                blurRadius: isHighlighted ? 12 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: brandColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: isJf
                        ? const JellyfinLogo(size: 20, color: Color(0xFF8E51DC))
                        : const PlexLogo(size: 20, color: Color(0xFFE5A00D)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: brandColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: brandColor.withOpacity(0.4), width: 1.0),
                    ),
                    child: Text(
                      isJf ? 'Jellyfin' : 'Plex',
                      style: TextStyle(
                        color: brandColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isJf
                          ? (widget.server.activeConnectionUri ?? 'Jellyfin Server')
                          : (widget.server.owned ? 'Owned Server' : 'Shared Server'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 11,
                      ),
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

class _ManageFavoriteButton extends StatefulWidget {
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final bool autofocus;

  const _ManageFavoriteButton({
    required this.onPressed,
    this.focusNode,
    this.onDown,
    this.onUp,
    this.autofocus = false,
  });

  @override
  State<_ManageFavoriteButton> createState() => _ManageFavoriteButtonState();
}

class _ManageFavoriteButtonState extends State<_ManageFavoriteButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (h) => setState(() => _isHovered = h),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? Colors.redAccent : PlixTheme.cardBorder,
              width: isHighlighted ? 2.5 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 20,
                color: isHighlighted ? Colors.redAccent : PlixTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                'Manage Favorite Libraries',
                style: TextStyle(
                  color: isHighlighted ? PlixTheme.textPrimary : PlixTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
