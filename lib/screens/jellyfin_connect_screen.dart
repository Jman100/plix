import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/jellyfin_auth_service.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/plix_device_helper.dart';
import '../services/update_service.dart';
import '../widgets/plix_back_button.dart';
import 'home_screen.dart';

class JellyfinConnectScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const JellyfinConnectScreen({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  State<JellyfinConnectScreen> createState() => _JellyfinConnectScreenState();
}

class _JellyfinConnectScreenState extends State<JellyfinConnectScreen> {
  final JellyfinAuthService _jellyfinAuthService = JellyfinAuthService();
  final TextEditingController _urlController = TextEditingController();
  final Map<String, FocusNode> _lanServerFocusNodes = {};
  final FocusNode _urlFocusNode = FocusNode();
  final FocusNode _connectBtnFocusNode = FocusNode();
  final FocusNode _cancelBtnFocusNode = FocusNode();
  final FocusNode _backBtnFocusNode = FocusNode();

  bool _isStep2QuickConnect = false;
  bool _isLoading = false;
  String? _errorMessage;

  List<JellyfinServerInfo> _discoveredServers = [];
  bool _isScanningLAN = false;

  String _targetServerUrl = '';
  String _targetServerName = 'Jellyfin Server';
  String _quickConnectCode = '';
  String _quickConnectSecret = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startLanDiscovery();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlController.dispose();
    _urlFocusNode.dispose();
    _connectBtnFocusNode.dispose();
    _cancelBtnFocusNode.dispose();
    _backBtnFocusNode.dispose();
    for (final node in _lanServerFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _startLanDiscovery() async {
    setState(() {
      _isScanningLAN = true;
    });
    try {
      final list = await _jellyfinAuthService.discoverServersLAN(timeout: const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _discoveredServers = list;
          _isScanningLAN = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isScanningLAN = false);
      }
    }
  }

  Future<void> _onConnectServer(String inputUrl) async {
    final cleanUrl = JellyfinAuthService.normalizeUrl(inputUrl);
    if (cleanUrl.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid Jellyfin server address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final info = await _jellyfinAuthService.testServer(cleanUrl);
      if (info == null) {
        throw Exception('Could not reach a Jellyfin server at "$cleanUrl".');
      }

      final clientId = await widget.authService.getClientIdentifier();
      final qcResult = await _jellyfinAuthService.initiateQuickConnect(
        cleanUrl,
        clientId: clientId,
        clientName: PlixDeviceHelper.clientName,
        version: UpdateService.currentVersion,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isStep2QuickConnect = true;
        _targetServerUrl = cleanUrl;
        _targetServerName = info.name;
        _quickConnectCode = qcResult.code;
        _quickConnectSecret = qcResult.secret;
      });

      _startQuickConnectPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _startQuickConnectPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final authorized = await _jellyfinAuthService.checkQuickConnect(
          _targetServerUrl,
          _quickConnectSecret,
        );

        if (authorized) {
          timer.cancel();
          _onQuickConnectAuthorized();
        }
      } catch (_) {}
    });
  }

  Future<void> _onQuickConnectAuthorized() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final clientId = await widget.authService.getClientIdentifier();
      final authResult = await _jellyfinAuthService.authenticateWithQuickConnect(
        _targetServerUrl,
        _quickConnectSecret,
        clientId: clientId,
        clientName: PlixDeviceHelper.clientName,
        version: UpdateService.currentVersion,
      );

      final server = PlexServer(
        name: authResult.serverName.isNotEmpty ? authResult.serverName : _targetServerName,
        clientIdentifier: authResult.serverId.isNotEmpty ? authResult.serverId : 'jf_${DateTime.now().millisecondsSinceEpoch}',
        accessToken: authResult.accessToken,
        owned: true,
        connections: [
          PlexConnection(
            protocol: _targetServerUrl.startsWith('https') ? 'https' : 'http',
            address: Uri.parse(_targetServerUrl).host,
            port: Uri.parse(_targetServerUrl).port,
            uri: _targetServerUrl,
            local: true,
            relay: false,
          ),
        ],
        activeConnectionUri: _targetServerUrl,
        serverType: 'jellyfin',
        userId: authResult.userId,
      );

      await widget.serverService.saveJellyfinServer(server);
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to complete authentication: $e';
        });
      }
    }
  }

  void _cancelQuickConnect() {
    _pollTimer?.cancel();
    setState(() {
      _isStep2QuickConnect = false;
      _quickConnectCode = '';
      _quickConnectSecret = '';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 20,
              child: PlixBackButton(
                focusNode: _backBtnFocusNode,
                onPressed: () {
                  if (_isStep2QuickConnect) {
                    _cancelQuickConnect();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 40, vertical: isCompact ? 20 : 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: _isStep2QuickConnect
                      ? _buildStep2QuickConnect()
                      : _buildStep1ServerInput(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1ServerInput() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF00A4DC).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00A4DC), width: 1.5),
          ),
          child: const Icon(Icons.hub_rounded, color: Color(0xFF00A4DC), size: 30),
        ),
        const SizedBox(height: 16),
        const Text(
          'Connect to Jellyfin',
          style: TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your Jellyfin server address or choose a detected server below.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PlixTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 28),

        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        // URL Input Field with clear focus outline
        AnimatedBuilder(
          animation: _urlFocusNode,
          builder: (context, _) {
            final isFocused = _urlFocusNode.hasFocus;
            return Container(
              decoration: BoxDecoration(
                color: PlixTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? const Color(0xFF00A4DC) : PlixTheme.cardBorder,
                  width: isFocused ? 2.5 : 1.0,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00A4DC).withOpacity(0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: _urlController,
                focusNode: _urlFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'https://jellyfin.example.com or 192.168.0.x:8096',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.dns_rounded, color: Color(0xFF00A4DC)),
                ),
                onSubmitted: (val) => _onConnectServer(val),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // Connect Button with clear focus outline
        Focus(
          focusNode: _connectBtnFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.space ||
                 event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
              _onConnectServer(_urlController.text);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (ctx) {
              final isFocused = Focus.of(ctx).hasFocus;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isFocused ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00A4DC).withOpacity(0.55),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _onConnectServer(_urlController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFocused ? const Color(0xFF38BDF8) : const Color(0xFF00A4DC),
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: isFocused ? 6 : 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text(
                          'Continue to Quick Connect',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 28),

        // Discovered servers section
        if (_discoveredServers.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Discovered on Local Network:',
              style: TextStyle(
                color: PlixTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: _discoveredServers.map((srv) {
              final srvKey = srv.id.isNotEmpty ? srv.id : srv.address;
              final focusNode = _lanServerFocusNodes.putIfAbsent(srvKey, () => FocusNode());
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _DiscoveredServerTile(
                  server: srv,
                  focusNode: focusNode,
                  onTap: () {
                    _urlController.text = srv.address;
                    _onConnectServer(srv.address);
                  },
                ),
              );
            }).toList(),
          ),
        ] else if (_isScanningLAN) ...[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
              SizedBox(width: 10),
              Text(
                'Scanning local network for Jellyfin servers...',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStep2QuickConnect() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF00A4DC).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00A4DC), width: 1.5),
          ),
          child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF00A4DC), size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          _targetServerName,
          style: const TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _targetServerUrl,
          style: const TextStyle(
            color: Color(0xFF00A4DC),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),

        // Big Quick Connect Code Box
        Builder(
          builder: (context) {
            final isCompact = PlixDeviceHelper.isCompact(context);
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 28,
                vertical: isCompact ? 16 : 20,
              ),
              decoration: BoxDecoration(
                color: PlixTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00A4DC).withOpacity(0.6), width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00A4DC).withOpacity(0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'QUICK CONNECT CODE',
                    style: TextStyle(
                      color: PlixTheme.textSecondary,
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _quickConnectCode.split('').join('  '),
                      style: TextStyle(
                        color: PlixTheme.plexGold,
                        fontSize: isCompact ? 30 : 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: isCompact ? 3 : 6,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),

        // Instructions
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How to connect:',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                '1. Open the Jellyfin app on your phone or web browser.\n'
                '2. Go to Settings → Quick Connect.\n'
                '3. Enter the code above to authorize this device.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Waiting Indicator
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00A4DC),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Waiting for authorization on your other device...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Change Server Button with clear outline
        Focus(
          focusNode: _cancelBtnFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                 event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.space ||
                 event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
              _cancelQuickConnect();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (ctx) {
              final isFocused = Focus.of(ctx).hasFocus;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFocused ? Colors.white : Colors.transparent,
                    width: 2.0,
                  ),
                ),
                child: TextButton.icon(
                  onPressed: _cancelQuickConnect,
                  icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white70),
                  label: const Text('Change Server Address', style: TextStyle(color: Colors.white70)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DiscoveredServerTile extends StatefulWidget {
  final JellyfinServerInfo server;
  final VoidCallback onTap;
  final FocusNode focusNode;

  const _DiscoveredServerTile({
    required this.server,
    required this.onTap,
    required this.focusNode,
  });

  @override
  State<_DiscoveredServerTile> createState() => _DiscoveredServerTileState();
}

class _DiscoveredServerTileState extends State<_DiscoveredServerTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _DiscoveredServerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      if (widget.focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.space ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _isHovered = h),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted ? const Color(0xFF00A4DC) : PlixTheme.cardBorder,
              width: isHighlighted ? 2.5 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: const Color(0xFF00A4DC).withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A4DC).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering, color: Color(0xFF00A4DC), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.server.name,
                      style: TextStyle(
                        color: isHighlighted ? Colors.white : Colors.white.withOpacity(0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.server.address,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isHighlighted ? const Color(0xFF00A4DC) : Colors.white38,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
