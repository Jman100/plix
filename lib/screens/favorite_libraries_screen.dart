import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_server_service.dart';
import '../services/plix_device_helper.dart';
import '../widgets/brand_logo.dart';
import '../widgets/plix_button.dart';
import 'home_screen.dart';
import 'server_select_screen.dart';

class FavoriteLibrariesScreen extends StatefulWidget {
  final PlexAuthService authService;
  final PlexServerService serverService;
  final List<PlexServer>? servers;
  final PlexServer? primaryServer;
  final bool isInitialSetup;

  const FavoriteLibrariesScreen({
    super.key,
    required this.authService,
    required this.serverService,
    this.servers,
    this.primaryServer,
    this.isInitialSetup = false,
  });

  @override
  State<FavoriteLibrariesScreen> createState() => _FavoriteLibrariesScreenState();
}

class _FavoriteLibrariesScreenState extends State<FavoriteLibrariesScreen> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  List<PlexServer> _servers = [];
  final Map<String, List<PlexLibrary>> _serverLibraries = {};
  final Set<String> _selectedCompositeIds = {};
  bool _hasInitialFocusRequested = false;
  bool _isSaving = false;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _refreshBtnFocusNode = FocusNode();
  final FocusNode _saveBtnFocusNode = FocusNode();
  final FocusNode _bottomSaveBtnFocusNode = FocusNode();
  final Map<String, FocusNode> _cardFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _refreshBtnFocusNode.addListener(_onTopFocus);
    _saveBtnFocusNode.addListener(_onTopFocus);
    _loadAllLibraries();
  }

  void _onTopFocus() {
    if (_saveBtnFocusNode.hasFocus || _refreshBtnFocusNode.hasFocus) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _saveBtnFocusNode.removeListener(_onTopFocus);
    _refreshBtnFocusNode.removeListener(_onTopFocus);
    _scrollController.dispose();
    _refreshBtnFocusNode.dispose();
    _saveBtnFocusNode.dispose();
    _bottomSaveBtnFocusNode.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAllLibraries({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      if (forceRefresh) {
        _isRefreshing = true;
        _serverLibraries.clear();
      }
      _errorMessage = null;
    });

    try {
      final token = await widget.authService.getSavedToken() ?? '';
      List<PlexServer> servers = (!forceRefresh && widget.servers != null)
          ? List<PlexServer>.from(widget.servers!)
          : [];
      if (servers.isEmpty || forceRefresh) {
        servers = await widget.serverService.fetchServers(token);
      }

      final addedOrder = await widget.serverService.getServerAddedOrder();
      servers.sort((a, b) {
        if (widget.primaryServer != null) {
          if (a.clientIdentifier == widget.primaryServer!.clientIdentifier) return -1;
          if (b.clientIdentifier == widget.primaryServer!.clientIdentifier) return 1;
        }
        final aIdx = addedOrder.indexOf(a.clientIdentifier);
        final bIdx = addedOrder.indexOf(b.clientIdentifier);
        final aVal = aIdx == -1 ? 999999 : aIdx;
        final bVal = bIdx == -1 ? 999999 : bIdx;
        if (aVal != bVal) {
          return aVal.compareTo(bVal);
        }
        return 0;
      });
      _servers = servers;

      final savedFavoriteIds = await widget.serverService.getFavoriteLibraryIds();
      final hasSaved = savedFavoriteIds != null;
      if (hasSaved) {
        _selectedCompositeIds.addAll(savedFavoriteIds);
      }

      // First, quickly display cached libraries so names load instantly
      for (final server in servers) {
        final cached = await widget.serverService.getCachedServerLibraries(server.clientIdentifier, server);
        if (cached.isNotEmpty) {
          _serverLibraries[server.clientIdentifier] = cached;
          if (!hasSaved && server.owned) {
            for (final lib in cached) {
              _selectedCompositeIds.add(lib.compositeId);
            }
          }
        }
      }
      void requestInitialFocusIfNeeded() {
        if (_hasInitialFocusRequested || !mounted || forceRefresh) return;
        _hasInitialFocusRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentFocus = FocusScope.of(context).focusedChild;
          if (currentFocus != null && currentFocus != FocusScope.of(context)) {
            return;
          }
          if (_saveBtnFocusNode.canRequestFocus) {
            _saveBtnFocusNode.requestFocus();
          }
        });
      }

      if (_serverLibraries.isNotEmpty && mounted) {
        setState(() {
          _isLoading = false;
        });
        requestInitialFocusIfNeeded();
      }

      // Fetch fresh libraries from each server concurrently (only titles & types)
      await Future.wait(servers.map((server) async {
        try {
          if (server.activeConnectionUri == null || server.activeConnectionUri!.isEmpty) {
            await widget.serverService.testAndResolveBestConnection(server);
          }
          final mediaService = PlexMediaService(server: server);
          final libs = await mediaService.getLibraries().timeout(const Duration(seconds: 3));
          _serverLibraries[server.clientIdentifier] = libs;
          await widget.serverService.cacheServerLibraries(server.clientIdentifier, libs);

          if (!hasSaved && server.owned) {
            for (final lib in libs) {
              _selectedCompositeIds.add(lib.compositeId);
            }
          }
        } catch (_) {}
      }));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });

        if (forceRefresh) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _refreshBtnFocusNode.canRequestFocus) {
              _refreshBtnFocusNode.requestFocus();
            }
          });
        } else {
          requestInitialFocusIfNeeded();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _errorMessage = 'Failed to load libraries: $e';
        });
        if (forceRefresh) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _refreshBtnFocusNode.canRequestFocus) {
              _refreshBtnFocusNode.requestFocus();
            }
          });
        }
      }
    }
  }

  void _toggleFavorite(String compositeId) {
    setState(() {
      if (_selectedCompositeIds.contains(compositeId)) {
        _selectedCompositeIds.remove(compositeId);
      } else {
        _selectedCompositeIds.add(compositeId);
      }
    });
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        backgroundColor: PlixTheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.cardBorder),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleBackAttempt() {
    final totalLibsCount = _serverLibraries.values.fold<int>(0, (sum, list) => sum + list.length);
    if (_selectedCompositeIds.isEmpty && totalLibsCount > 0) {
      _showToast('You must pick at least one favorite library.');
      return;
    }
    _saveChanges();
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    final totalLibsCount = _serverLibraries.values.fold<int>(0, (sum, list) => sum + list.length);
    if (_selectedCompositeIds.isEmpty && totalLibsCount > 0) {
      _showToast('You must pick at least one favorite library.');
      return;
    }

    _isSaving = true;
    try {
      await widget.serverService.saveFavoriteLibraryIds(_selectedCompositeIds.toList());
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('plix_v160_favorites_prompted', true);
      } catch (_) {}

      if (!mounted) return;

      if (widget.isInitialSetup) {
        // Resolve a primary server to launch HomeScreen
        PlexServer? targetServer = widget.primaryServer;
        if (targetServer == null && _servers.isNotEmpty) {
          final activeId = await widget.serverService.getActiveServerId();
          targetServer = _servers.firstWhere(
            (s) => s.clientIdentifier == activeId,
            orElse: () => _servers.first,
          );
        }

        if (targetServer != null) {
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
          return;
        } else {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ServerSelectScreen(
                servers: _servers,
                authService: widget.authService,
                serverService: widget.serverService,
              ),
            ),
            (route) => false,
          );
          return;
        }
      }

      // Return to previous screen (Customize Servers)
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      _isSaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackAttempt();
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        appBar: AppBar(
          title: const Text('Favorite Libraries'),
          automaticallyImplyLeading: false,
          leading: widget.isInitialSetup
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _handleBackAttempt,
                ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: PlixButton(
              focusNode: _refreshBtnFocusNode,
              label: _isRefreshing ? 'Refreshing...' : 'Refresh Servers',
              icon: _isRefreshing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _refreshBtnFocusNode.hasFocus ? Colors.black : PlixTheme.plexGold,
                        ),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              backgroundColor: Colors.white.withOpacity(0.1),
              borderColor: PlixTheme.plexGold.withOpacity(0.4),
              textColor: PlixTheme.textPrimary,
              highlightColor: PlixTheme.plexGold,
              highlightTextColor: Colors.black,
              highlightBorderColor: PlixTheme.plexGold,
              fontSize: 13,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onRight: () {
                if (_saveBtnFocusNode.canRequestFocus) {
                  _saveBtnFocusNode.requestFocus();
                }
              },
              onDown: () {
                if (_cardFocusNodes.isNotEmpty) {
                  _cardFocusNodes.values.first.requestFocus();
                } else {
                  _bottomSaveBtnFocusNode.requestFocus();
                }
              },
              onPressed: _isRefreshing ? () {} : () => _loadAllLibraries(forceRefresh: true),
            ),
          ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: PlixButton(
                focusNode: _saveBtnFocusNode,
                label: 'Save Changes',
                icon: const Icon(Icons.check_rounded, size: 18),
                backgroundColor: PlixTheme.plexGold,
                highlightColor: PlixTheme.plexGoldLight,
                borderColor: PlixTheme.plexGold,
                textColor: Colors.black,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                onLeft: () => _refreshBtnFocusNode.requestFocus(),
                onDown: () {
                  if (_cardFocusNodes.isNotEmpty) {
                    _cardFocusNodes.values.first.requestFocus();
                  } else {
                    _bottomSaveBtnFocusNode.requestFocus();
                  }
                },
                onPressed: _saveChanges,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Loading libraries across all servers...',
                    style: TextStyle(color: PlixTheme.textSecondary, fontSize: 15),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 16),
                      PlixButton(
                        label: 'Retry',
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: _loadAllLibraries,
                      ),
                    ],
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 16 : 40,
                      vertical: isCompact ? 16 : 24,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Explanatory Instructions Banner
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: PlixTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: PlixTheme.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 22),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Choose Your Favorite Libraries',
                                        style: TextStyle(
                                          color: PlixTheme.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Favorite libraries will appear in your navigation and library list. Only favorited libraries will be shown.',
                                        style: TextStyle(
                                          color: PlixTheme.textSecondary,
                                          fontSize: 13,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Servers and their libraries
                          for (int sIdx = 0; sIdx < _servers.length; sIdx++) ...[
                            _buildServerSection(_servers[sIdx], sIdx, isCompact),
                            const SizedBox(height: 24),
                          ],

                          const SizedBox(height: 16),

                          // Big Save Changes button at bottom as well
                          Center(
                            child: SizedBox(
                              width: isCompact ? double.infinity : 280,
                              child: PlixButton(
                                focusNode: _bottomSaveBtnFocusNode,
                                label: 'Save Changes',
                                icon: const Icon(Icons.check_circle_rounded, size: 20),
                                backgroundColor: PlixTheme.plexGold,
                                highlightColor: const Color(0xFFFFB82E),
                                borderColor: PlixTheme.plexGold,
                                textColor: Colors.black,
                                fontSize: 14,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                onPressed: _saveChanges,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildServerSection(PlexServer server, int sIdx, bool isCompact) {
    final libs = _serverLibraries[server.clientIdentifier] ?? [];
    final isJf = server.isJellyfin;
    final brandColor = isJf ? const Color(0xFF8E51DC) : const Color(0xFFE5A00D);

    // Find next server that has libraries
    PlexServer? nextServerWithLibs;
    for (int nextIdx = sIdx + 1; nextIdx < _servers.length; nextIdx++) {
      final nextCandidate = _servers[nextIdx];
      if ((_serverLibraries[nextCandidate.clientIdentifier] ?? []).isNotEmpty) {
        nextServerWithLibs = nextCandidate;
        break;
      }
    }

    // Find previous server that has libraries
    PlexServer? prevServerWithLibs;
    for (int prevIdx = sIdx - 1; prevIdx >= 0; prevIdx--) {
      final prevCandidate = _servers[prevIdx];
      if ((_serverLibraries[prevCandidate.clientIdentifier] ?? []).isNotEmpty) {
        prevServerWithLibs = prevCandidate;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: isJf
                  ? const JellyfinLogo(size: 16, color: Color(0xFF8E51DC))
                  : const PlexLogo(size: 16, color: Color(0xFFE5A00D)),
            ),
            const SizedBox(width: 10),
            Text(
              server.name,
              style: const TextStyle(
                color: PlixTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
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

        if (libs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'No libraries found or server is unreachable.',
              style: TextStyle(color: PlixTheme.textMuted, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              const cardWidth = 240.0;
              const spacing = 12.0;
              final columns = isCompact
                  ? 2
                  : ((availableWidth + spacing) / (cardWidth + spacing)).floor().clamp(1, 4);

              final List<List<PlexLibrary>> rows = [];
              for (int i = 0; i < libs.length; i += columns) {
                rows.add(libs.sublist(i, math.min(i + columns, libs.length)));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int r = 0; r < rows.length; r++) ...[
                    if (r > 0) const SizedBox(height: spacing),
                    Row(
                      mainAxisSize: isCompact ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        for (int c = 0; c < rows[r].length; c++) ...[
                          if (c > 0) const SizedBox(width: spacing),
                          isCompact
                              ? Expanded(
                                  child: _FavoriteLibraryCard(
                                    library: rows[r][c],
                                    isCompact: true,
                                    isFavorited: _selectedCompositeIds.contains(rows[r][c].compositeId),
                                    isFirstRow: sIdx == 0 && r == 0,
                                    focusNode: _cardFocusNodes.putIfAbsent(
                                      rows[r][c].compositeId,
                                      () => FocusNode(debugLabel: 'fav_'),
                                    ),
                                    onLeft: c > 0
                                        ? () => _cardFocusNodes[rows[r][c - 1].compositeId]?.requestFocus()
                                        : null,
                                    onRight: c < rows[r].length - 1
                                        ? () => _cardFocusNodes[rows[r][c + 1].compositeId]?.requestFocus()
                                        : null,
                                    onDown: () {
                                      if (r < rows.length - 1) {
                                        final nextRow = rows[r + 1];
                                        final targetCol = math.min(c, nextRow.length - 1);
                                        _cardFocusNodes[nextRow[targetCol].compositeId]?.requestFocus();
                                      } else {
                                        if (nextServerWithLibs != null) {
                                          final nextLibs = _serverLibraries[nextServerWithLibs.clientIdentifier]!;
                                          _cardFocusNodes[nextLibs.first.compositeId]?.requestFocus();
                                        } else {
                                          _bottomSaveBtnFocusNode.requestFocus();
                                        }
                                      }
                                    },
                                    onUp: () {
                                      if (r > 0) {
                                        final prevRow = rows[r - 1];
                                        final targetCol = math.min(c, prevRow.length - 1);
                                        _cardFocusNodes[prevRow[targetCol].compositeId]?.requestFocus();
                                      } else {
                                        if (prevServerWithLibs != null) {
                                          final prevLibs = _serverLibraries[prevServerWithLibs.clientIdentifier]!;
                                          _cardFocusNodes[prevLibs.first.compositeId]?.requestFocus();
                                        } else {
                                          _saveBtnFocusNode.requestFocus();
                                          if (_scrollController.hasClients) {
                                            _scrollController.animateTo(0.0,
                                                duration: const Duration(milliseconds: 200),
                                                curve: Curves.easeOutCubic);
                                          }
                                        }
                                      }
                                    },
                                    onToggle: () => _toggleFavorite(rows[r][c].compositeId),
                                  ),
                                )
                              : _FavoriteLibraryCard(
                                  library: rows[r][c],
                                  isCompact: false,
                                  isFavorited: _selectedCompositeIds.contains(rows[r][c].compositeId),
                                  isFirstRow: sIdx == 0 && r == 0,
                                  focusNode: _cardFocusNodes.putIfAbsent(
                                    rows[r][c].compositeId,
                                    () => FocusNode(debugLabel: 'fav_'),
                                  ),
                                  onLeft: c > 0
                                      ? () => _cardFocusNodes[rows[r][c - 1].compositeId]?.requestFocus()
                                      : null,
                                  onRight: c < rows[r].length - 1
                                      ? () => _cardFocusNodes[rows[r][c + 1].compositeId]?.requestFocus()
                                      : null,
                                  onDown: () {
                                    if (r < rows.length - 1) {
                                      final nextRow = rows[r + 1];
                                      final targetCol = math.min(c, nextRow.length - 1);
                                      _cardFocusNodes[nextRow[targetCol].compositeId]?.requestFocus();
                                    } else {
                                      if (nextServerWithLibs != null) {
                                        final nextLibs = _serverLibraries[nextServerWithLibs.clientIdentifier]!;
                                        _cardFocusNodes[nextLibs.first.compositeId]?.requestFocus();
                                      } else {
                                        _bottomSaveBtnFocusNode.requestFocus();
                                      }
                                    }
                                  },
                                  onUp: () {
                                    if (r > 0) {
                                      final prevRow = rows[r - 1];
                                      final targetCol = math.min(c, prevRow.length - 1);
                                      _cardFocusNodes[prevRow[targetCol].compositeId]?.requestFocus();
                                    } else {
                                      if (prevServerWithLibs != null) {
                                        final prevLibs = _serverLibraries[prevServerWithLibs.clientIdentifier]!;
                                        _cardFocusNodes[prevLibs.first.compositeId]?.requestFocus();
                                      } else {
                                        _saveBtnFocusNode.requestFocus();
                                        if (_scrollController.hasClients) {
                                          _scrollController.animateTo(0.0,
                                              duration: const Duration(milliseconds: 200),
                                              curve: Curves.easeOutCubic);
                                        }
                                      }
                                    }
                                  },
                                  onToggle: () => _toggleFavorite(rows[r][c].compositeId),
                                ),
                        ],
                        if (isCompact && rows[r].length < columns) ...[
                          const SizedBox(width: spacing),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _FavoriteLibraryCard extends StatefulWidget {
  final PlexLibrary library;
  final bool isFavorited;
  final bool isFirstRow;
  final bool isCompact;
  final FocusNode focusNode;
  final VoidCallback onToggle;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _FavoriteLibraryCard({
    required this.library,
    required this.isFavorited,
    this.isFirstRow = false,
    this.isCompact = false,
    required this.focusNode,
    required this.onToggle,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_FavoriteLibraryCard> createState() => _FavoriteLibraryCardState();
}

class _FavoriteLibraryCardState extends State<_FavoriteLibraryCard> {
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
        final renderObject = context.findRenderObject() as RenderBox?;
        final scrollable = Scrollable.maybeOf(context);
        if (renderObject != null && renderObject.hasSize && scrollable != null) {
          final scrollRenderBox = scrollable.context.findRenderObject() as RenderBox?;
          if (scrollRenderBox != null && scrollRenderBox.hasSize) {
            final cardTop = renderObject.localToGlobal(Offset.zero, ancestor: scrollRenderBox).dy;
            final cardBottom = cardTop + renderObject.size.height;
            final viewportHeight = scrollRenderBox.size.height;
            // If already comfortably visible vertically, do NOT re-scroll horizontally
            if (cardTop >= 50 && cardBottom <= viewportHeight - 50) {
              return;
            }
          }
        }

        if (widget.isFirstRow) {
          if (scrollable != null && scrollable.position.hasContentDimensions) {
            if (scrollable.position.pixels > 0) {
              scrollable.position.animateTo(
                0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          }
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
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final isFavorited = widget.isFavorited;

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
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (widget.onLeft != null) {
              widget.onLeft!();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (widget.onRight != null) {
              widget.onRight!();
            }
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onToggle,
        onHover: (h) => setState(() => _isHovered = h),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.isCompact ? null : 240,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? PlixTheme.cardFocused
                : (isFavorited ? PlixTheme.surface : PlixTheme.surface.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted
                  ? PlixTheme.plexGold
                  : (isFavorited ? Colors.redAccent.withOpacity(0.5) : PlixTheme.cardBorder),
              width: isHighlighted ? 2.5 : 1.2,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: PlixTheme.plexGold.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.library.isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                color: isHighlighted ? Colors.white : PlixTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.library.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isHighlighted ? Colors.white : PlixTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: isFavorited ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: isFavorited ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorited ? Colors.redAccent : Colors.white38,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
