import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_server_service.dart';
import '../services/plix_device_helper.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/watchlist_screen.dart';

class PlixBottomNav extends StatelessWidget {
  final int currentIndex;
  final PlexServer server;
  final PlexAuthService? authService;
  final PlexServerService? serverService;
  final String clientId;
  final List<PlexLibrary>? libraries;
  final ValueChanged<List<PlexLibrary>>? onLibrariesReordered;
  final VoidCallback? onHomeTap;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onLibrariesTap;
  final VoidCallback? onSettingsTap;

  const PlixBottomNav({
    super.key,
    required this.currentIndex,
    required this.server,
    this.authService,
    this.serverService,
    required this.clientId,
    this.libraries,
    this.onLibrariesReordered,
    this.onHomeTap,
    this.onWatchlistTap,
    this.onSearchTap,
    this.onLibrariesTap,
    this.onSettingsTap,
  });

  PlexAuthService _resolveAuthService() {
    return authService ?? PlexAuthService();
  }

  void _handleTap(BuildContext context, int index) {
    if (index == 0) {
      if (currentIndex == 0) {
        onHomeTap?.call();
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else if (index == 1) {
      if (currentIndex == 1) {
        onWatchlistTap?.call();
      } else {
        final screen = WatchlistScreen(
          server: server,
          authService: _resolveAuthService(),
          serverService: serverService,
          clientId: clientId,
        );
        if (currentIndex == 0) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
        }
      }
    } else if (index == 2) {
      if (currentIndex == 2) {
        onSearchTap?.call();
      } else {
        final screen = SearchScreen(
          server: server,
          clientId: clientId,
        );
        if (currentIndex == 0) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
        }
      }
    } else if (index == 3) {
      if (onLibrariesTap != null) {
        onLibrariesTap!();
      } else {
        showLibrariesModal(context);
      }
    } else if (index == 4) {
      if (currentIndex == 4) {
        onSettingsTap?.call();
      } else {
        final screen = SettingsScreen(
          server: server,
          clientId: clientId,
        );
        if (currentIndex == 0) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
        }
      }
    }
  }

  void showLibrariesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PlixTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _LibrariesSheetContent(
          server: server,
          clientId: clientId,
          authService: _resolveAuthService(),
          serverService: serverService,
          initialLibraries: libraries,
          onLibrariesReordered: onLibrariesReordered,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlixDeviceHelper.isTelevision || !PlixDeviceHelper.isCompact(context)) {
      return const SizedBox.shrink();
    }

    final safeIndex = (currentIndex >= 0 && currentIndex <= 4) ? currentIndex : 0;
    final hasActiveSelection = currentIndex >= 0 && currentIndex <= 4;

    return Container(
      decoration: BoxDecoration(
        color: PlixTheme.surface,
        border: Border(
          top: BorderSide(color: PlixTheme.cardBorder, width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: safeIndex,
          onTap: (idx) => _handleTap(context, idx),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: hasActiveSelection ? PlixTheme.plexGold : Colors.white60,
          unselectedItemColor: Colors.white60,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark_rounded),
              label: 'Watchlist',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.video_library_rounded),
              label: 'Libraries',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _LibrariesSheetContent extends StatefulWidget {
  final PlexServer server;
  final String clientId;
  final PlexAuthService authService;
  final PlexServerService? serverService;
  final List<PlexLibrary>? initialLibraries;
  final ValueChanged<List<PlexLibrary>>? onLibrariesReordered;

  const _LibrariesSheetContent({
    required this.server,
    required this.clientId,
    required this.authService,
    this.serverService,
    this.initialLibraries,
    this.onLibrariesReordered,
  });

  @override
  State<_LibrariesSheetContent> createState() => _LibrariesSheetContentState();
}

class _LibrariesSheetContentState extends State<_LibrariesSheetContent> {
  List<PlexLibrary> _libs = [];
  bool _isLoading = false;
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLibraries != null && widget.initialLibraries!.isNotEmpty) {
      _libs = List.from(widget.initialLibraries!);
    } else {
      _loadLibraries();
    }
  }

  Future<void> _loadLibraries() async {
    setState(() => _isLoading = true);
    try {
      final mediaService = PlexMediaService(server: widget.server);
      final fetched = await mediaService.getLibraries();

      try {
        final prefs = await SharedPreferences.getInstance();
        final savedOrder = prefs.getStringList('library_order_${widget.server.clientIdentifier}');
        if (savedOrder != null && savedOrder.isNotEmpty) {
          final Map<String, int> orderMap = {
            for (int i = 0; i < savedOrder.length; i++) savedOrder[i]: i,
          };
          fetched.sort((a, b) {
            final aOrder = orderMap[a.key] ?? 999;
            final bOrder = orderMap[b.key] ?? 999;
            return aOrder.compareTo(bOrder);
          });
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _libs = fetched;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOrder(List<PlexLibrary> reordered) async {
    setState(() {
      _libs = List.from(reordered);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = reordered.map((l) => l.key).toList();
      await prefs.setStringList('library_order_${widget.server.clientIdentifier}', keys);
    } catch (_) {}
    widget.onLibrariesReordered?.call(List.from(reordered));
  }

  void _openLibrary(PlexLibrary lib) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          library: lib,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.video_library_rounded, color: PlixTheme.plexGold, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Libraries',
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_libs.length > 1)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _isReorderMode ? PlixTheme.plexGold : Colors.white70,
                        backgroundColor: _isReorderMode ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(_isReorderMode ? Icons.check_rounded : Icons.swap_vert_rounded, size: 18),
                      label: Text(
                        _isReorderMode ? 'Done' : 'Sort Order',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        setState(() => _isReorderMode = !_isReorderMode);
                      },
                    ),
                ],
              ),
            ),
            if (_isReorderMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                color: PlixTheme.plexGold.withOpacity(0.08),
                child: const Text(
                  'Drag using the handles on the right to change library order.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            Divider(color: PlixTheme.cardBorder, height: 1),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold)),
                ),
              )
            else if (_libs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No libraries found on this server.',
                    style: TextStyle(color: PlixTheme.textSecondary, fontSize: 14),
                  ),
                ),
              )
            else
              Flexible(
                child: _isReorderMode
                    ? ReorderableListView.builder(
                        shrinkWrap: true,
                        itemCount: _libs.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final list = List<PlexLibrary>.from(_libs);
                          final item = list.removeAt(oldIndex);
                          list.insert(newIndex, item);
                          _saveOrder(list);
                        },
                        itemBuilder: (ctx, i) {
                          final lib = _libs[i];
                          IconData icon = Icons.folder_rounded;
                          if (lib.type == 'movie') icon = Icons.movie_outlined;
                          if (lib.type == 'show') icon = Icons.tv_rounded;
                          if (lib.type == 'artist') icon = Icons.music_note_rounded;

                          return ListTile(
                            key: ValueKey('reorder_${lib.key}'),
                            leading: Icon(icon, color: PlixTheme.plexGold),
                            title: Text(
                              lib.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle_rounded, color: Colors.white70),
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _libs.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (ctx, i) {
                          final lib = _libs[i];
                          IconData icon = Icons.folder_rounded;
                          if (lib.type == 'movie') icon = Icons.movie_outlined;
                          if (lib.type == 'show') icon = Icons.tv_rounded;
                          if (lib.type == 'artist') icon = Icons.music_note_rounded;

                          return ListTile(
                            leading: Icon(icon, color: PlixTheme.plexGold),
                            title: Text(
                              lib.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                            onTap: () => _openLibrary(lib),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
