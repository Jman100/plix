import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../widgets/plix_button.dart';
import 'home_screen.dart';
import 'jellyfin_connect_screen.dart';
import 'login_screen.dart';
import '../widgets/brand_logo.dart';
import '../services/plix_device_helper.dart';

class ServerSelectScreen extends StatefulWidget {
  final List<PlexServer> servers;
  final PlexAuthService authService;
  final PlexServerService serverService;

  const ServerSelectScreen({
    super.key,
    required this.servers,
    required this.authService,
    required this.serverService,
  });

  @override
  State<ServerSelectScreen> createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> {
  late List<PlexServer> _servers;
  bool _isConnecting = false;
  String? _connectingServerName;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _jellyfinBtnFocusNode = FocusNode();
  final FocusNode _plexBtnFocusNode = FocusNode();
  final Map<String, FocusNode> _connectFocusNodes = {};
  final Map<String, FocusNode> _pinFocusNodes = {};
  Set<String> _pinnedServerIds = {};

  @override
  void initState() {
    super.initState();
    _servers = List.from(widget.servers);
    _loadPinnedServers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _jellyfinBtnFocusNode.dispose();
    _plexBtnFocusNode.dispose();
    for (final node in _connectFocusNodes.values) {
      node.dispose();
    }
    for (final node in _pinFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPinnedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('pinned_server_client_ids') ?? [];
      if (mounted) {
        setState(() {
          _pinnedServerIds = list.toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _togglePin(String clientIdentifier) async {
    setState(() {
      if (_pinnedServerIds.contains(clientIdentifier)) {
        _pinnedServerIds.remove(clientIdentifier);
      } else {
        _pinnedServerIds.add(clientIdentifier);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pinned_server_client_ids', _pinnedServerIds.toList());
    } catch (_) {}
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

  void _focusFirstAvailable() {
    final pinned = _servers.where((s) => _pinnedServerIds.contains(s.clientIdentifier)).toList();
    final target = pinned.isNotEmpty ? pinned.first : _servers.firstOrNull;
    if (target != null) {
      _connectFocusNodes[target.clientIdentifier]?.requestFocus();
    }
  }

  Future<void> _selectServer(PlexServer server) async {
    setState(() {
      _isConnecting = true;
      _connectingServerName = server.name;
      _errorMessage = null;
    });

    try {
      final uri = await widget.serverService.testAndResolveBestConnection(server);
      if (!mounted) return;

      if (uri != null && uri.isNotEmpty) {
        await widget.serverService.setActiveServerId(server.clientIdentifier);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              server: server,
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
          (route) => false,
        );
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage =
              'Could not connect to "${server.name}". Please ensure the server is online and accessible.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Connection error: $e';
        });
      }
    }
  }

  void _openJellyfinSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JellyfinConnectScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  void _openPlexSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isPhone = PlixDeviceHelper.isPhone(context);
    final pinnedServers = _servers.where((s) => _pinnedServerIds.contains(s.clientIdentifier)).toList();
    final unpinnedServers = _servers.where((s) => !_pinnedServerIds.contains(s.clientIdentifier)).toList();

    return Scaffold(
      backgroundColor: PlixTheme.background,
      appBar: AppBar(
        title: const Text('Switch Server'),
        automaticallyImplyLeading: canGoBack,
      ),
      body: Center(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: isCompact ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Available Servers',
                style: TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a server to browse your media, or sign into a new server instance.',
                style: TextStyle(
                  color: PlixTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),

              // Top Slim Buttons for connecting new instances
              if (!_isConnecting) ...[
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
                                onFocus: _scrollToTop,
                                onDown: _focusFirstAvailable,
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
                                onFocus: _scrollToTop,
                                onDown: _focusFirstAvailable,
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
                                onFocus: _scrollToTop,
                                onDown: _focusFirstAvailable,
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
                                onFocus: _scrollToTop,
                                onDown: _focusFirstAvailable,
                                onLeft: () => _jellyfinBtnFocusNode.requestFocus(),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
              ],

              if (_isConnecting) ...[
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connecting to $_connectingServerName...',
                  style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
                ),
              ] else ...[
                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],

                // 1. Pinned Servers Section (if any)
                if (pinnedServers.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 752),
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: const Row(
                        children: [
                          Icon(Icons.push_pin_rounded, color: Color(0xFFE5A00D), size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Pinned Servers',
                            style: TextStyle(
                              color: PlixTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildServerGrid(
                    servers: pinnedServers,
                    isPinnedSection: true,
                    otherSectionServers: unpinnedServers,
                    isCompact: isCompact,
                    isPhone: isPhone,
                  ),
                  const SizedBox(height: 28),
                ],

                // 2. Other Servers Section
                if (unpinnedServers.isNotEmpty) ...[
                  if (pinnedServers.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 752),
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: const Row(
                          children: [
                            Icon(Icons.dns_outlined, color: PlixTheme.textSecondary, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Other Servers',
                              style: TextStyle(
                                color: PlixTheme.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  _buildServerGrid(
                    servers: unpinnedServers,
                    isPinnedSection: false,
                    otherSectionServers: pinnedServers,
                    isCompact: isCompact,
                    isPhone: isPhone,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerGrid({
    required List<PlexServer> servers,
    required bool isPinnedSection,
    required List<PlexServer> otherSectionServers,
    required bool isCompact,
    required bool isPhone,
  }) {
    if (isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < servers.length; i++) ...[
            Builder(
              builder: (context) {
                final server = servers[i];
                final connectNode = _connectFocusNodes.putIfAbsent(
                  server.clientIdentifier,
                  () => FocusNode(debugLabel: 'connect_${server.name}'),
                );
                final pinNode = _pinFocusNodes.putIfAbsent(
                  server.clientIdentifier,
                  () => FocusNode(debugLabel: 'pin_${server.name}'),
                );
                return Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ServerCard(
                    server: server,
                    isPinned: isPinnedSection,
                    autofocus: isPinnedSection && i == 0,
                    connectFocusNode: connectNode,
                    pinFocusNode: pinNode,
                    cardWidth: double.infinity,
                    isPhone: isPhone,
                    onTogglePin: () => _togglePin(server.clientIdentifier),
                    onSelect: () => _selectServer(server),
                    onScrollTop: _scrollToTop,
                  ),
                );
              },
            ),
          ],
        ],
      );
    }

    final rowCount = (servers.length / 3).ceil();
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
                    if (index >= servers.length) {
                      return const SizedBox(width: cardWidth);
                    }
                    final server = servers[index];
                    final connectNode = _connectFocusNodes.putIfAbsent(
                      server.clientIdentifier,
                      () => FocusNode(debugLabel: 'connect_${server.name}'),
                    );
                    final pinNode = _pinFocusNodes.putIfAbsent(
                      server.clientIdentifier,
                      () => FocusNode(debugLabel: 'pin_${server.name}'),
                    );

                    // 1. Left
                    VoidCallback? onLeft;
                    VoidCallback? onPinLeft;
                    if (c > 0) {
                      final prevServer = servers[index - 1];
                      onLeft = () => _connectFocusNodes[prevServer.clientIdentifier]?.requestFocus();
                      onPinLeft = () => _pinFocusNodes[prevServer.clientIdentifier]?.requestFocus();
                    }

                    // 2. Right
                    VoidCallback? onRight;
                    VoidCallback? onPinRight;
                    if (c < 2 && index + 1 < servers.length) {
                      final nextServer = servers[index + 1];
                      onRight = () => _connectFocusNodes[nextServer.clientIdentifier]?.requestFocus();
                      onPinRight = () => _pinFocusNodes[nextServer.clientIdentifier]?.requestFocus();
                    }

                    // 3. Up from Connect button
                    VoidCallback? onConnectUp;
                    if (r > 0) {
                      final aboveServer = servers[(r - 1) * 3 + c];
                      if (Platform.isAndroid && !isPhone) {
                        onConnectUp = () => _pinFocusNodes[aboveServer.clientIdentifier]?.requestFocus();
                      } else {
                        onConnectUp = () => _connectFocusNodes[aboveServer.clientIdentifier]?.requestFocus();
                      }
                    } else {
                      // Top row of this section
                      if (isPinnedSection) {
                        onConnectUp = () => (c == 0 ? _jellyfinBtnFocusNode : _plexBtnFocusNode).requestFocus();
                      } else {
                        if (otherSectionServers.isNotEmpty) {
                          final pinnedRowCount = (otherSectionServers.length / 3).ceil();
                          final lastRowStart = (pinnedRowCount - 1) * 3;
                          final targetCol = (c < (otherSectionServers.length - lastRowStart))
                              ? c
                              : (otherSectionServers.length - 1 - lastRowStart);
                          final targetPinned = otherSectionServers[lastRowStart + targetCol];
                          if (Platform.isAndroid && !isPhone) {
                            onConnectUp = () => _pinFocusNodes[targetPinned.clientIdentifier]?.requestFocus();
                          } else {
                            onConnectUp = () => _connectFocusNodes[targetPinned.clientIdentifier]?.requestFocus();
                          }
                        } else {
                          onConnectUp = () => (c == 0 ? _jellyfinBtnFocusNode : _plexBtnFocusNode).requestFocus();
                        }
                      }
                    }

                    // 4. Down from Pin button (Android TV) or Connect button (Windows/Phone)
                    VoidCallback? onSectionDown;
                    if (r < rowCount - 1) {
                      final nextRowIndex = (r + 1) * 3 + c;
                      final targetServer = nextRowIndex < servers.length
                          ? servers[nextRowIndex]
                          : servers.last;
                      onSectionDown = () => _connectFocusNodes[targetServer.clientIdentifier]?.requestFocus();
                    } else {
                      // Last row of this section
                      if (isPinnedSection && otherSectionServers.isNotEmpty) {
                        final targetCol = (c < otherSectionServers.length)
                            ? (c < 3 ? c : otherSectionServers.length - 1)
                            : (otherSectionServers.length - 1);
                        final targetServer = otherSectionServers[targetCol];
                        onSectionDown = () => _connectFocusNodes[targetServer.clientIdentifier]?.requestFocus();
                      }
                    }

                    return _ServerCard(
                      server: server,
                      isPinned: isPinnedSection,
                      autofocus: isPinnedSection && index == 0,
                      connectFocusNode: connectNode,
                      pinFocusNode: pinNode,
                      cardWidth: cardWidth,
                      isPhone: isPhone,
                      onTogglePin: () => _togglePin(server.clientIdentifier),
                      onSelect: () => _selectServer(server),
                      onConnectUp: onConnectUp,
                      onDown: onSectionDown,
                      onLeft: onLeft,
                      onRight: onRight,
                      onPinLeft: onPinLeft,
                      onPinRight: onPinRight,
                      onScrollTop: _scrollToTop,
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
  final VoidCallback? onFocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _SlimTopButton({
    required this.title,
    required this.logo,
    required this.accentColor,
    required this.onPressed,
    this.focusNode,
    this.onDown,
    this.onFocus,
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
      if (_focusNode.hasFocus) {
        widget.onFocus?.call();
      }
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
  final bool isPinned;
  final bool autofocus;
  final FocusNode connectFocusNode;
  final FocusNode pinFocusNode;
  final double cardWidth;
  final bool isPhone;
  final VoidCallback onSelect;
  final VoidCallback onTogglePin;
  final VoidCallback? onConnectUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onPinLeft;
  final VoidCallback? onPinRight;
  final VoidCallback? onScrollTop;

  const _ServerCard({
    required this.server,
    required this.isPinned,
    required this.autofocus,
    required this.connectFocusNode,
    required this.pinFocusNode,
    required this.cardWidth,
    this.isPhone = false,
    required this.onSelect,
    required this.onTogglePin,
    this.onConnectUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onPinLeft,
    this.onPinRight,
    this.onScrollTop,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _isConnectFocused = false;
  bool _isPinFocused = false;
  bool _isHovered = false;
  bool _isPinHovered = false;

  @override
  void initState() {
    super.initState();
    widget.connectFocusNode.addListener(_onConnectFocusChange);
    widget.pinFocusNode.addListener(_onPinFocusChange);
  }

  void _onConnectFocusChange() {
    if (mounted) {
      setState(() => _isConnectFocused = widget.connectFocusNode.hasFocus);
      if (widget.connectFocusNode.hasFocus) {
        if (widget.isPinned) {
          widget.onScrollTop?.call();
        } else {
          Scrollable.ensureVisible(
            context,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _onPinFocusChange() {
    if (mounted) {
      setState(() => _isPinFocused = widget.pinFocusNode.hasFocus);
      if (widget.pinFocusNode.hasFocus) {
        if (widget.isPinned) {
          widget.onScrollTop?.call();
        } else {
          Scrollable.ensureVisible(
            context,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ServerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connectFocusNode != oldWidget.connectFocusNode) {
      oldWidget.connectFocusNode.removeListener(_onConnectFocusChange);
      widget.connectFocusNode.addListener(_onConnectFocusChange);
    }
    if (widget.pinFocusNode != oldWidget.pinFocusNode) {
      oldWidget.pinFocusNode.removeListener(_onPinFocusChange);
      widget.pinFocusNode.addListener(_onPinFocusChange);
    }
  }

  @override
  void dispose() {
    widget.connectFocusNode.removeListener(_onConnectFocusChange);
    widget.pinFocusNode.removeListener(_onPinFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isJf = widget.server.isJellyfin;
    // Plex uses official yellow/amber (#E5A00D), Jellyfin uses official purple (#8E51DC).
    // User theme color must NOT be used here.
    final brandColor = isJf ? const Color(0xFF8E51DC) : const Color(0xFFE5A00D);
    final brandTextColor = isJf ? Colors.white : Colors.black;
    final isHighlighted = _isConnectFocused || _isPinFocused || _isHovered;

    return InkWell(
      canRequestFocus: false, // Absolutely essential: never steal focus from buttons!
      onTap: widget.onSelect,
      onHover: (h) => setState(() => _isHovered = h),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.cardWidth,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? brandColor : PlixTheme.cardBorder,
            width: isHighlighted ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isHighlighted ? brandColor.withOpacity(0.35) : Colors.black.withOpacity(0.35),
              blurRadius: isHighlighted ? 12 : 10,
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
                // On Windows or Phone: keep pin button in top right corner
                if (Platform.isWindows || widget.isPhone) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    canRequestFocus: false,
                    onTap: widget.onTogglePin,
                    onHover: (h) => setState(() => _isPinHovered = h),
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isPinHovered ? Colors.white12 : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        widget.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        color: widget.isPinned
                            ? brandColor
                            : (_isPinHovered ? Colors.white : Colors.white38),
                        size: 18,
                      ),
                    ),
                  ),
                ],
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

            const SizedBox(height: 4),

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

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: PlixButton(
                focusNode: widget.connectFocusNode,
                autofocus: widget.autofocus,
                label: 'Connect',
                fontSize: 13.0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                backgroundColor: brandColor,
                highlightColor: isJf ? const Color(0xFFA56CF0) : const Color(0xFFFFB82E),
                borderColor: brandColor,
                textColor: brandTextColor,
                onPressed: widget.onSelect,
                onUp: widget.onConnectUp,
                onDown: (Platform.isAndroid && !widget.isPhone)
                    ? () => widget.pinFocusNode.requestFocus()
                    : widget.onDown,
                onLeft: widget.onLeft,
                onRight: widget.onRight,
              ),
            ),

            // On Android TV: move Pin button to a dedicated button below Connect
            if (Platform.isAndroid && !widget.isPhone) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: PlixButton(
                  focusNode: widget.pinFocusNode,
                  isPrimary: false,
                  label: widget.isPinned ? 'Unpin from Top' : 'Pin to Top',
                  fontSize: 12.0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  icon: Icon(
                    widget.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 14,
                    color: widget.isPinned ? brandColor : PlixTheme.textSecondary,
                  ),
                  backgroundColor: widget.isPinned ? brandColor.withOpacity(0.18) : PlixTheme.surface,
                  highlightColor: brandColor.withOpacity(0.25),
                  borderColor: brandColor,
                  textColor: _isPinFocused ? Colors.white : PlixTheme.textSecondary,
                  onPressed: widget.onTogglePin,
                  onUp: () => widget.connectFocusNode.requestFocus(),
                  onDown: widget.onDown,
                  onLeft: widget.onPinLeft ?? widget.onLeft,
                  onRight: widget.onPinRight ?? widget.onRight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
