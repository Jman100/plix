import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import 'auth_chooser_screen.dart';
import 'home_screen.dart';
import 'favorite_libraries_screen.dart';
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

    final prefs = await SharedPreferences.getInstance();
    final token = await widget.authService.getSavedToken();
    final jfServers = await widget.serverService.getSavedJellyfinServers();
    final hasSavedToken = token != null && token.isNotEmpty;
    final hasSavedJf = jfServers.isNotEmpty;
    final hasSavedActiveServer = prefs.containsKey('active_server_id');
    final hasSavedFavorites = prefs.containsKey('favorite_libraries');
    final hasSavedThemes = prefs.containsKey('plix_theme');
    final hasExistingInstallData = hasSavedToken ||
        hasSavedJf ||
        hasSavedActiveServer ||
        hasSavedFavorites ||
        hasSavedThemes ||
        (prefs.getKeys().isNotEmpty && !prefs.containsKey('plix_is_fresh_install'));

    if (hasExistingInstallData) {
      // Existing install or app update: ensure welcome tour is permanently disabled
      await prefs.setBool('plix_welcome_tour_shown', true);
      await prefs.remove('plix_fresh_install_pending_tour');
      await prefs.remove('plix_is_fresh_install');
    } else {
      // Brand new clean install
      await prefs.setBool('plix_is_fresh_install', true);
    }

    if (!hasSavedToken && !hasSavedJf) {
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

      final bool v160FavoritesPrompted = prefs.getBool('plix_v160_favorites_prompted') ?? false;

      if (servers.length == 1) {
        // Only one server accessible: use it by default
        final server = servers.first;
        await widget.serverService.testAndResolveBestConnection(server);
        await widget.serverService.setActiveServerId(server.clientIdentifier);
        final favoriteIds = await widget.serverService.getFavoriteLibraryIds();
        if (favoriteIds == null || !v160FavoritesPrompted) {
          await prefs.setBool('plix_v160_favorites_prompted', true);
          _navigateToFavoriteLibraries(servers, server);
        } else {
          _navigateToHome(server);
        }
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
        } else {
          selectedServer = servers.first;
        }

        if (!v160FavoritesPrompted) {
          await prefs.setBool('plix_v160_favorites_prompted', true);
          if (selectedServer != null) {
            await widget.serverService.testAndResolveBestConnection(selectedServer);
            await widget.serverService.setActiveServerId(selectedServer.clientIdentifier);
          }
          _navigateToFavoriteLibraries(servers, selectedServer ?? servers.first);
        } else if (selectedServer != null && savedActiveId != null) {
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

  void _navigateToFavoriteLibraries(List<PlexServer> servers, PlexServer primaryServer) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FavoriteLibrariesScreen(
          authService: widget.authService,
          serverService: widget.serverService,
          servers: servers,
          primaryServer: primaryServer,
          isInitialSetup: true,
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
                const PlixAppLogo(
                  size: 110,
                  showWordmark: true,
                  borderRadius: 28,
                  glow: true,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Universal Media Client',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 13,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w500,
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
