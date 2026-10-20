import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import 'auth_chooser_screen.dart';
import 'home_screen.dart';
import 'server_select_screen.dart';

class SplashScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;

  const SplashScreen({
    super.key,
    required this.authService,
    required this.serverService,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Brief splash delay for smooth visual transition
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final token = await widget.authService.getSavedToken();
    final jfServers = await widget.serverService.getSavedJellyfinServers();

    if ((token == null || token.isEmpty) && jfServers.isEmpty) {
      _navigateToAuthChooser();
      return;
    }

    try {
      final servers = <PlexServer>[];
      if (token != null && token.isNotEmpty) {
        final fetched = await widget.serverService.fetchServers(token);
        servers.addAll(fetched);
      } else {
        servers.addAll(jfServers);
      }
      if (!mounted) return;

      if (servers.isEmpty) {
        _navigateToAuthChooser();
        return;
      }

      if (servers.length == 1) {
        // Only one server accessible: use it by default
        final server = servers.first;
        await widget.serverService.testAndResolveBestConnection(server);
        await widget.serverService.setActiveServerId(server.clientIdentifier);
        _navigateToHome(server);
      } else {
        // Multiple servers accessible
        final savedActiveId = await widget.serverService.getActiveServerId();
        final pinnedIds = await widget.serverService.getPinnedServerIds();

        PlexServer? selectedServer;
        if (savedActiveId != null) {
          selectedServer = servers.firstWhere(
            (s) => s.clientIdentifier == savedActiveId,
            orElse: () => servers.first,
          );
        } else if (pinnedIds.isNotEmpty) {
          selectedServer = servers.firstWhere(
            (s) => pinnedIds.contains(s.clientIdentifier),
            orElse: () => servers.first,
          );
        }

        if (selectedServer != null && savedActiveId != null) {
          await widget.serverService.testAndResolveBestConnection(selectedServer);
          _navigateToHome(selectedServer);
        } else {
          // Offer server pinning selection screen
          _navigateToServerSelect(servers);
        }
      }
    } catch (_) {
      if (mounted) {
        _navigateToAuthChooser();
      }
    }
  }

  void _navigateToAuthChooser() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AuthChooserScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  void _navigateToServerSelect(List<PlexServer> servers) {
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

  void _navigateToHome(PlexServer server) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          server: server,
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: PlixTheme.plexGold,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.35),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 64,
                    ),
                  ),
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'pli',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Trebuchet MS',
                          letterSpacing: 2,
                        ),
                      ),
                      TextSpan(
                        text: 'x',
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Trebuchet MS',
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Universal Media Client',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
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
