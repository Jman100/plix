import 'dart:io';
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
import '../widgets/plix_home_button.dart';
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
  bool _isMultiServer = false;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _homeButtonFocusNode = FocusNode();
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
    _homeButtonFocusNode.dispose();
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

  void _handleItemFocus(int index, bool isCompact) {
    if (isCompact) return;
    if (index < _firstRowItemCount(isCompact)) {
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
      return;
    }

    void adjustVisible() {
      if (!mounted || !_gridScrollController.hasClients) return;
      final node = _focusNodes[index];
      if (node == null || !node.hasFocus) return;
      final itemContext = node.context;
      if (itemContext == null || !itemContext.mounted) return;
      final renderObject = itemContext.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.attached) return;
      final scrollable = Scrollable.maybeOf(itemContext);
      final scrollBox = scrollable?.context.findRenderObject() as RenderBox?;
      if (scrollBox == null || !scrollBox.attached) return;

      final itemOffset = renderObject.localToGlobal(Offset.zero, ancestor: scrollBox);
      final itemTop = itemOffset.dy;
      final itemBottom = itemTop + renderObject.size.height;
      final viewportHeight = _gridScrollController.position.viewportDimension;
      final currentOffset = _gridScrollController.offset;

      // Bottom margin: 40px ensures the 1.08 focus scale, border, and year subtitle stay fully visible
      const bottomMargin = 40.0;
      if (itemBottom + bottomMargin > viewportHeight) {
        final overflow = (itemBottom + bottomMargin) - viewportHeight;
        final target = (currentOffset + overflow).clamp(0.0, _gridScrollController.position.maxScrollExtent);
        if ((target - currentOffset).abs() > 1.0) {
          _gridScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (itemTop < 24.0) {
        final underflow = 24.0 - itemTop;
        final target = (currentOffset - underflow).clamp(0.0, _gridScrollController.position.maxScrollExtent);
        if ((target - currentOffset).abs() > 1.0) {
          _gridScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustVisible();
      Future<void>.delayed(const Duration(milliseconds: 80), adjustVisible);
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

      List<PlexServer> allServers = [];
      if (widget.serverService != null) {
        try {
          allServers = await widget.serverService!.fetchServers(userToken);
        } catch (_) {}
      }
      if (allServers.isEmpty) {
        allServers = [widget.server];
      }
      for (final s in allServers) {
        if (s.clientIdentifier == widget.server.clientIdentifier &&
            widget.server.activeConnectionUri != null &&
            widget.server.activeConnectionUri!.isNotEmpty) {
          s.activeConnectionUri = widget.server.activeConnectionUri;
        }
      }

      // Target all connected servers (Plex + all Jellyfin servers)
      // Watchlist is account/server wide and must not be excluded if a library is not favorited
      final targetServers = allServers.isNotEmpty ? allServers : [widget.server];
      _isMultiServer = targetServers.length > 1;

      final List<PlexMediaItem> aggregatedItems = [];
      final Set<String> seenGuidsOrKeys = {};
      bool fetchedPlexWatchlist = false;

      for (final server in targetServers) {
        if (server.isJellyfin) {
          try {
            if (server.activeConnectionUri == null || server.activeConnectionUri!.isEmpty) {
              await widget.serverService?.testAndResolveBestConnection(server);
            }
            final jfItems = await PlexMediaService(server: server).getWatchlist(
              userToken: userToken,
              clientId: clientId,
            );
            for (final it in jfItems) {
              if (it.isEpisode || it.isSeason) continue;
              final key = it.guid?.isNotEmpty == true ? it.guid! : '${server.clientIdentifier}_${it.ratingKey}';
              if (seenGuidsOrKeys.add(key)) {
                aggregatedItems.add(it.copyWith(server: server, serverId: server.clientIdentifier));
              }
            }
          } catch (_) {}
        } else {
          if (!fetchedPlexWatchlist) {
            fetchedPlexWatchlist = true;
            try {
              final plexItems = await PlexMediaService(server: server).getWatchlist(
                userToken: userToken,
                clientId: clientId,
              );
              for (final it in plexItems) {
                if (it.isEpisode || it.isSeason) continue;
                final key = it.guid?.isNotEmpty == true ? it.guid! : it.ratingKey;
                if (seenGuidsOrKeys.add(key)) {
                  aggregatedItems.add(it.copyWith(server: server, serverId: server.clientIdentifier));
                }
              }
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        setState(() {
          _items = aggregatedItems;
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

  void _openDetails(PlexMediaItem item, int index) async {
    _lastSelectedIndex = index;
    PlexServer effectiveServer = item.server ?? widget.server;
    if (effectiveServer.clientIdentifier == widget.server.clientIdentifier &&
        (effectiveServer.activeConnectionUri == null || effectiveServer.activeConnectionUri!.isEmpty)) {
      effectiveServer.activeConnectionUri = widget.server.activeConnectionUri;
    }

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetailsScreen(
            initialItem: item,
            server: effectiveServer,
            clientId: widget.clientId,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _loadWatchlist();
      }
    }
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
                                padding: EdgeInsets.only(top: isCompact ? 88 : 102),
                                child: GridView.builder(
                                controller: _gridScrollController,
                                clipBehavior: Clip.none,
                                // Keep the number of decoded posters bounded on
                                // low-memory TVs while scrolling a large list.
                                cacheExtent: 200,
                                padding: EdgeInsets.only(
                                  top: isCompact ? 10 : 20,
                                  left: isCompact ? 14 : 32,
                                  right: isCompact ? 14 : 32,
                                  bottom: isCompact ? 24 : 140,
                                ),
                                gridDelegate: isCompact
                              ? SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: (MediaQuery.of(context).size.width / 130).floor().clamp(3, 7),
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 0.47,
                                      )
                                    : const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 165,
                                        childAspectRatio: 0.47,
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
                                        mediaService: (item.server != null && item.server != _mediaService.server)
                                            ? PlexMediaService(server: item.server!)
                                            : _mediaService,
                                        bottomServerName: _isMultiServer
                                            ? (item.server?.name ?? (item.server?.isJellyfin == true ? 'Jellyfin' : 'Plex'))
                                            : null,
                                        focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                                        autofocus: !isCompact && index == (_lastSelectedIndex ?? 0),
                                        enableHighlight: !isCompact,
                                        width: constraints.maxWidth,
                                        margin: EdgeInsets.zero,
                                        onFocusChange: (focused) {
                                          if (focused) _handleItemFocus(index, isCompact);
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
                      if (!Platform.isAndroid || PlixDeviceHelper.isTelevision) ...[
                        PlixBackButton(
                          focusNode: _backButtonFocusNode,
                          onRight: () => _homeButtonFocusNode.requestFocus(),
                          onDown: () {
                            if (_items.isNotEmpty && _focusNodes.containsKey(0)) {
                              _focusNodes[0]?.requestFocus();
                            }
                          },
                        ),
                        const SizedBox(width: 10),
                        PlixHomeButton(
                          focusNode: _homeButtonFocusNode,
                          onLeft: () => _backButtonFocusNode.requestFocus(),
                          onDown: () {
                            if (_items.isNotEmpty && _focusNodes.containsKey(0)) {
                              _focusNodes[0]?.requestFocus();
                            }
                          },
                        ),
                        SizedBox(width: isCompact ? 12 : 16),
                      ],
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
