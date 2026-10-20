import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_theme.dart';
import '../models/plex_pin.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_button.dart';
import 'home_screen.dart';
import 'server_select_screen.dart';

class LoginScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  PlexPin? _currentPin;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startAuthFlow();
  }

  Future<void> _startAuthFlow() async {
    _pollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pin = await widget.authService.createPin();
      if (!mounted) return;
      setState(() {
        _currentPin = pin;
        _isLoading = false;
      });
      _startPolling(pin);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not generate Plex PIN. Please check your internet connection.';
      });
    }
  }

  void _startPolling(PlexPin pin) {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final updatedPin = await widget.authService.checkPin(pin.id, pin.code);
        if (updatedPin.isLinked) {
          timer.cancel();
          _onAuthSuccess(updatedPin.authToken!);
        }
      } catch (_) {}
    });
  }

  Future<void> _onAuthSuccess(String authToken) async {
    final user = await widget.authService.fetchUser(authToken);
    await widget.authService.saveSession(authToken, user);

    if (!mounted) return;

    try {
      final servers = await widget.serverService.fetchServers(authToken);
      if (!mounted) return;

      if (servers.isEmpty) {
        setState(() {
          _errorMessage = 'No Plex servers found for this account.';
        });
        return;
      }

      if (servers.length == 1) {
        final server = servers.first;
        await widget.serverService.testAndResolveBestConnection(server);
        await widget.serverService.setActiveServerId(server.clientIdentifier);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              server: server,
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ServerSelectScreen(
              servers: servers,
              authService: widget.authService,
              serverService: widget.serverService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load servers: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            if (canPop)
              Positioned(
                top: 16,
                left: 20,
                child: PlixBackButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
              // Logo
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: PlixTheme.plexGold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'PLIX',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Text(
                'Sign in to link your Plex account',
                style: TextStyle(
                  color: PlixTheme.textSecondary,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 36),

              if (_isLoading)
                Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Generating linking code...',
                      style: TextStyle(color: PlixTheme.textSecondary),
                    ),
                  ],
                )
              else if (_errorMessage != null)
                Column(
                  children: [
                    Icon(Icons.error_outline, color: Colors.redAccent.shade200, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                    PlixButton(
                      autofocus: true,
                      label: 'Try Again',
                      icon: const Icon(Icons.refresh),
                      onPressed: _startAuthFlow,
                    ),
                  ],
                )
              else if (_currentPin != null) ...[
                // Side-by-side QR Code and PIN code card
                Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: PlixTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PlixTheme.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // QR Code container
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: 'https://plex.tv/link?pin=${_currentPin!.code}',
                              version: QrVersions.auto,
                              size: 190,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scan with Phone Camera',
                            style: TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      Container(
                        height: 200,
                        width: 1,
                        color: PlixTheme.cardBorder,
                      ),

                      // Code & Instructions
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '1. On your phone or computer, go to:',
                                style: TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: PlixTheme.card,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'plex.tv/link',
                                  style: TextStyle(
                                    color: PlixTheme.plexGold,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '2. Enter this 4-digit code:',
                                style: TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Builder(
                                builder: (context) {
                                  final code = _currentPin!.code.trim().toUpperCase();
                                  return Row(
                                    children: [
                                      for (int i = 0; i < code.length; i++)
                                        Container(
                                          margin: const EdgeInsets.only(right: 10),
                                          width: 48,
                                          height: 58,
                                          decoration: BoxDecoration(
                                            color: PlixTheme.card,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: PlixTheme.plexGold,
                                              width: 2.0,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              code[i],
                                              style: const TextStyle(
                                                color: PlixTheme.textPrimary,
                                                fontSize: 28,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        PlixTheme.plexGold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Waiting for authorization...',
                                    style: TextStyle(
                                      color: PlixTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                PlixButton(
                  isPrimary: false,
                  label: 'Get New Code',
                  icon: const Icon(Icons.refresh),
                  onPressed: _startAuthFlow,
                ),
              ],
            ],
          ),
        ),
      ),
          ],
        ),
      ),
    );
  }
}
