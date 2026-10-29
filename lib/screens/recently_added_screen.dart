import 'dart:io';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
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
  final FocusNode _backFocusNode = FocusNode();
  final FocusNode _homeFocusNode = FocusNode();
  final Map<int, FocusNode> _focusNodes = {};
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);
    _loadRecentlyAdded();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    _backFocusNode.dispose();
    _homeFocusNode.dispose();
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
                          : Padding(
                              padding: EdgeInsets.only(top: isCompact ? 88 : 92),
                              child: GridView.builder(
                              controller: _gridScrollController,
                              clipBehavior: Clip.none,
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
                                      childAspectRatio: 0.52,
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
                    if (!Platform.isAndroid || PlixDeviceHelper.isTelevision) ...[
                      PlixBackButton(
                        focusNode: _backFocusNode,
                        autofocus: false,
                        onRight: () => _homeFocusNode.requestFocus(),
                        onDown: () {
                          if (_items.isNotEmpty && _focusNodes.containsKey(0)) {
                            _focusNodes[0]?.requestFocus();
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      PlixHomeButton(
                        focusNode: _homeFocusNode,
                        onLeft: () => _backFocusNode.requestFocus(),
                        onDown: () {
                          if (_items.isNotEmpty && _focusNodes.containsKey(0)) {
                            _focusNodes[0]?.requestFocus();
                          }
                        },
                      ),
                      SizedBox(width: isCompact ? 10 : 20),
                    ],
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
