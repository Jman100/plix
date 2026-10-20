import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import 'details_screen.dart';
import '../services/plix_device_helper.dart';
import '../widgets/plix_bottom_nav.dart';

class RecentlyAddedScreen extends StatefulWidget {
  final PlexLibrary library;
  final PlexServer server;
  final String clientId;

  const RecentlyAddedScreen({
    super.key,
    required this.library,
    required this.server,
    required this.clientId,
  });

  @override
  State<RecentlyAddedScreen> createState() => _RecentlyAddedScreenState();
}

class _RecentlyAddedScreenState extends State<RecentlyAddedScreen> {
  late PlexMediaService _mediaService;
  List<PlexMediaItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);
    _loadRecentlyAdded();
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRecentlyAdded() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _mediaService.getRecentlyAdded(
        widget.library.key,
        limit: 50,
        libraryType: widget.library.type,
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
          _errorMessage = 'Failed to load recently added items: $e';
        });
      }
    }
  }

  void _openDetails(PlexMediaItem item, int index) {
    _lastSelectedIndex = index;
    PlexMediaItem targetItem = item;
    String? initialSeasonKey;

    if (item.targetType == 'episode' && item.targetRatingKey != null) {
      targetItem = PlexMediaItem(
        ratingKey: item.targetRatingKey!,
        key: '/library/metadata/${item.targetRatingKey}',
        title: item.title,
        type: 'episode',
        thumb: item.thumb,
        grandparentTitle: item.grandparentTitle ?? item.title,
        grandparentThumb: item.grandparentThumb ?? item.thumb,
      );
    } else if (item.targetType == 'season' && item.targetSeasonKey != null) {
      initialSeasonKey = item.targetSeasonKey;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: targetItem,
          initialSeasonKey: initialSeasonKey,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_focusNodes.containsKey(index)) {
            _focusNodes[index]?.requestFocus();
          }
        });
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
              currentIndex: 3,
              server: widget.server,
              clientId: widget.clientId,
            )
          : null,
      body: SafeArea(
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
                                onPressed: _loadRecentlyAdded,
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
                          ? const Center(
                              child: Text(
                                'No recently added items found.',
                                style: TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
                              ),
                            )
                          : GridView.builder(
                              clipBehavior: Clip.hardEdge,
                              padding: EdgeInsets.only(
                                left: isCompact ? 14 : 32,
                                right: isCompact ? 14 : 32,
                                top: isCompact ? 68 : 92,
                                bottom: isCompact ? 24 : 140,
                              ),
                              gridDelegate: isCompact
                                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.52,
                                    )
                                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 165,
                                      childAspectRatio: 0.56,
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
                                      autofocus: index == (_lastSelectedIndex ?? 0),
                                      width: constraints.maxWidth,
                                      margin: EdgeInsets.zero,
                                      onTap: () => _openDetails(item, index),
                                    );
                                  },
                                );
                              },
                            ),
            ),

            // Pinned Top Bar (Always on top)
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
                    const PlixBackButton(autofocus: false),
                    SizedBox(width: isCompact ? 10 : 20),
                    Icon(
                      widget.library.isMovie ? Icons.movie_outlined : Icons.tv_outlined,
                      color: PlixTheme.plexGold,
                      size: isCompact ? 22 : 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recently Added in ${widget.library.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: isCompact ? 16 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_isLoading && _items.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: PlixTheme.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: PlixTheme.cardBorder),
                        ),
                        child: Text(
                          '${_items.length}',
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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
    );
  }
}
