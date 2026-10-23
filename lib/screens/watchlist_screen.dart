import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_server_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import 'details_screen.dart';
import '../services/plix_device_helper.dart';
import '../widgets/plix_bottom_nav.dart';

class WatchlistScreen extends StatefulWidget {
  final PlexServer server;
  final PlexAuthService authService;
  final PlexServerService? serverService;
  final String clientId;

  const WatchlistScreen({
    super.key,
    required this.server,
    required this.authService,
    this.serverService,
    required this.clientId,
  });

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late PlexMediaService _mediaService;
  List<PlexMediaItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};
  final FocusNode _backButtonFocusNode = FocusNode();
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);
    _loadWatchlist();
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    _gridScrollController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  int _firstRowItemCount(bool isCompact) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCompact) {
      return (width / 130).floor().clamp(3, 7);
    }
    // Matches SliverGridDelegateWithMaxCrossAxisExtent's column calculation.
    final available = width - 64;
    return (available / (165 + 16)).ceil();
  }

  void _keepFirstRowVisible(int index, bool isCompact) {
    if (index >= _firstRowItemCount(isCompact)) return;
    void scrollToTop() {
      if (!mounted || !_gridScrollController.hasClients) return;
      if (!(_focusNodes[index]?.hasFocus ?? false)) return;
      if (_gridScrollController.offset <= 0.5) return;
      _gridScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToTop();
      // Re-assert after the framework's focus ensureVisible pass.
      Future<void>.delayed(const Duration(milliseconds: 80), scrollToTop);
    });
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final savedToken = await widget.authService.getSavedToken();
      final userToken = (savedToken != null && savedToken.isNotEmpty)
          ? savedToken
          : widget.server.accessToken;
      final clientId = widget.clientId.isNotEmpty
          ? widget.clientId
          : await widget.authService.getClientIdentifier();

      final items = await _mediaService.getWatchlist(
        userToken: userToken,
        clientId: clientId,
      );

      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
        if (_lastSelectedIndex != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_focusNodes.containsKey(_lastSelectedIndex)) {
              _focusNodes[_lastSelectedIndex]?.requestFocus();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load Watchlist: $e';
        });
      }
    }
  }

  Future<PlexMediaItem> _resolveServerItem(PlexMediaItem watchlistItem) async {
    try {
      final searchResults = await _mediaService.search(watchlistItem.title);
      for (final r in searchResults) {
        final isSameType = (watchlistItem.isMovie && r.isMovie) || (watchlistItem.isShow && r.isShow);
        if (!isSameType) continue;

        // 1. GUID match
        if (watchlistItem.guid != null && r.guid != null && watchlistItem.guid!.isNotEmpty && r.guid!.isNotEmpty) {
          final cleanW = watchlistItem.guid!.trim().toLowerCase().split('?').first;
          final cleanR = r.guid!.trim().toLowerCase().split('?').first;
          if (cleanW == cleanR) {
            return r;
          }
        }

        // 2. Title + Year match
        if (watchlistItem.title.trim().toLowerCase() == r.title.trim().toLowerCase()) {
          if (watchlistItem.year == null || r.year == null || watchlistItem.year == r.year) {
            return r;
          }
        }
      }
    } catch (_) {}
    return watchlistItem;
  }

  void _openDetails(PlexMediaItem item, int index) async {
    _lastSelectedIndex = index;
    final resolvedItem = await _resolveServerItem(item);

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: resolvedItem,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _loadWatchlist();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      bottomNavigationBar: (isCompact && !isTv)
          ? PlixBottomNav(
              currentIndex: 1,
              server: widget.server,
              authService: widget.authService,
              serverService: widget.serverService,
              clientId: widget.clientId,
              onWatchlistTap: _loadWatchlist,
            )
          : null,
      body: SafeArea(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.goBack)) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              // Content Grid
              Positioned.fill(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                                const SizedBox(height: 12),
                                Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadWatchlist,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: PlixTheme.plexGold,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bookmark_border_rounded, size: 56, color: PlixTheme.textSecondary.withOpacity(0.4)),
                                      const SizedBox(height: 14),
                                      Text(
                                        widget.server.isJellyfin
                                            ? 'Your Jellyfin Watchlist is empty.'
                                            : 'Your Plex Watchlist is empty.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        widget.server.isJellyfin
                                            ? 'Add movies and shows to your Watchlist on Jellyfin to see them here.'
                                            : 'Add movies and shows to your Watchlist on Plex to see them here.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(top: 88),
                                child: GridView.builder(
                                controller: _gridScrollController,
                                clipBehavior: Clip.hardEdge,
                                // Keep the number of decoded posters bounded on
                                // low-memory TVs while scrolling a large list.
                                cacheExtent: 200,
                                padding: EdgeInsets.only(
                                  left: isCompact ? 14 : 32,
                                  right: isCompact ? 14 : 32,
                                  bottom: isCompact ? 24 : 140,
                                ),
                                gridDelegate: isCompact
                              ? SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: (MediaQuery.of(context).size.width / 130).floor().clamp(3, 7),
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 0.51,
                                      )
                                    : const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 165,
                                        childAspectRatio: 0.55,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 18,
                                      ),
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return LayoutBuilder(
                                    builder: (context, constraints) {
                                      return MediaCard(
                                        item: item,
                                        mediaService: _mediaService,
                                        focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                                        autofocus: !isCompact && index == (_lastSelectedIndex ?? 0),
                                        enableHighlight: !isCompact,
                                        width: constraints.maxWidth,
                                        margin: EdgeInsets.zero,
                                        onFocusChange: (focused) {
                                          if (focused) _keepFirstRowVisible(index, isCompact);
                                        },
                                        onTap: () => _openDetails(item, index),
                                      );
                                    },
                                  );
                                },
                              ),
                              ),
              ),

              // Pinned Top Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: PlixTheme.background,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 16 : 32,
                    vertical: isCompact ? 12 : 16,
                  ),
                  child: Row(
                    children: [
                      PlixBackButton(
                        focusNode: _backButtonFocusNode,
                        onDown: () {
                          if (_items.isNotEmpty && _focusNodes.containsKey(0)) {
                            _focusNodes[0]?.requestFocus();
                          }
                        },
                      ),
                      SizedBox(width: isCompact ? 12 : 16),
                      Icon(Icons.bookmark_rounded, color: PlixTheme.plexGold, size: isCompact ? 22 : 24),
                      const SizedBox(width: 10),
                      Text(
                        'Watchlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_isLoading && _items.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: PlixTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            '${_items.length}',
                            style: const TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
