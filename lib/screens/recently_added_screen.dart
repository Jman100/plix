import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import 'details_screen.dart';

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
    return Scaffold(
      backgroundColor: PlixTheme.background,
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
                              padding: const EdgeInsets.only(left: 32, right: 32, top: 92, bottom: 140),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 165,
                                childAspectRatio: 2 / 3.7,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 18,
                              ),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return MediaCard(
                                  item: item,
                                  mediaService: _mediaService,
                                  focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                                  autofocus: index == (_lastSelectedIndex ?? 0),
                                  width: 140,
                                  onTap: () => _openDetails(item, index),
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  children: [
                    const PlixBackButton(autofocus: false),
                    const SizedBox(width: 20),
                    Icon(
                      widget.library.isMovie ? Icons.movie_outlined : Icons.tv_outlined,
                      color: PlixTheme.plexGold,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Recently Added in ${widget.library.title}',
                      style: const TextStyle(
                        color: PlixTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (!_isLoading && _items.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: PlixTheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: PlixTheme.cardBorder),
                        ),
                        child: Text(
                          '${_items.length} items',
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
