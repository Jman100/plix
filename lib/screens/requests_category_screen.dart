import 'dart:io';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/plex_server.dart';
import '../models/seerr_models.dart';
import '../services/plix_device_helper.dart';
import '../services/seerr_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/seerr_request_dialog.dart';
import 'requests_screen.dart';

enum SeerrCategory {
  recent,
  trending,
  movies,
  tv,
}

class RequestsCategoryScreen extends StatefulWidget {
  final SeerrCategory category;
  final String title;
  final PlexServer server;
  final List<PlexServer>? servers;
  final String seerrUrl;
  final String clientId;
  final List<SeerrMediaItem> initialItems;
  final ValueChanged<SeerrMediaItem>? onItemRequested;

  const RequestsCategoryScreen({
    super.key,
    required this.category,
    required this.title,
    required this.server,
    this.servers,
    required this.seerrUrl,
    required this.clientId,
    this.initialItems = const [],
    this.onItemRequested,
  });

  @override
  State<RequestsCategoryScreen> createState() => _RequestsCategoryScreenState();
}

class _RequestsCategoryScreenState extends State<RequestsCategoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _homeButtonFocus = FocusNode();
  final List<FocusNode> _itemFocusNodes = [];

  final List<SeerrMediaItem> _items = [];
  final Set<String> _seenKeys = {};

  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    if (widget.initialItems.isNotEmpty) {
      _appendUniqueItems(widget.initialItems);
      _currentPage = 1;
    } else {
      _isLoadingInitial = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialItems.isEmpty) {
        _loadNextPage();
      } else {
        _focusFirstItem();
        // Pre-fetch page 2 so scrolling/navigating down is instant
        _loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _backButtonFocus.dispose();
    _homeButtonFocus.dispose();
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    _itemFocusNodes.clear();
    super.dispose();
  }

  void _appendUniqueItems(List<SeerrMediaItem> incoming) {
    for (final item in incoming) {
      final key = '${item.mediaType}_${item.id}';
      if (_seenKeys.add(key)) {
        _items.add(item);
        _itemFocusNodes.add(FocusNode());
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    final seerr = SeerrService();
    SeerrPagedResult result;

    try {
      switch (widget.category) {
        case SeerrCategory.recent:
          result = await seerr.getRecentRequestsPage(
            widget.server,
            widget.seerrUrl,
            page: nextPage,
            take: 20,
          );
          break;
        case SeerrCategory.trending:
          result = await seerr.getTrendingPage(
            widget.server,
            widget.seerrUrl,
            page: nextPage,
          );
          break;
        case SeerrCategory.movies:
          result = await seerr.getUpcomingMoviesPage(
            widget.server,
            widget.seerrUrl,
            page: nextPage,
          );
          break;
        case SeerrCategory.tv:
          result = await seerr.getUpcomingTvPage(
            widget.server,
            widget.seerrUrl,
            page: nextPage,
          );
          break;
      }

      if (!mounted) return;
      final prevCount = _items.length;
      setState(() {
        _currentPage = nextPage;
        _appendUniqueItems(result.items);
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });

      if (prevCount == 0 && _items.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusFirstItem();
        });
      }
    } catch (e) {
      debugPrint('[RequestsCategoryScreen] loadNextPage error: $e');
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _focusFirstItem() {
    if (_itemFocusNodes.isNotEmpty && _itemFocusNodes.first.canRequestFocus) {
      _scrollToRow(0, 310.0);
      _itemFocusNodes.first.requestFocus();
    }
  }

  void _scrollToRow(int row, double rowHeight) {
    if (!_scrollController.hasClients) return;
    if (row <= 0) {
      if (_scrollController.offset > 0.0) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    // SliverPadding has top: 8.0 and mainAxisSpacing: 16.0, so row r starts at 8.0 + r * rowHeight.
    // Subtract 4px for focus border breathing room while keeping the previous row's years off-screen.
    final targetOffset = 8.0 + (row * rowHeight) - 4.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _openRequestDialog(SeerrMediaItem item) async {
    final success = await SeerrRequestDialog.show(
      context,
      server: widget.server,
      seerrUrl: widget.seerrUrl,
      item: item,
      clientId: widget.clientId,
      availableServers: widget.servers,
    );

    if (success == true && mounted) {
      setState(() {
        for (int i = 0; i < _items.length; i++) {
          final it = _items[i];
          if (it.id == item.id && it.mediaType.toLowerCase() == item.mediaType.toLowerCase()) {
            final nextStatus = (it.mediaStatus != null && it.mediaStatus! >= 2) ? it.mediaStatus : 2;
            _items[i] = it.copyWith(mediaStatus: nextStatus);
          }
        }
      });
      widget.onItemRequested?.call(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final showTopNavButtons =
        !Platform.isAndroid || PlixDeviceHelper.isTelevision || MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        body: Container(
          decoration: PlixTheme.backgroundDecoration,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Bar: Back / Home + Category Title (no search bar or server name)
                Padding(
                  padding: EdgeInsets.fromLTRB(isCompact ? 16 : 36, isCompact ? 12 : 24, isCompact ? 16 : 36, 12),
                  child: Row(
                    children: [
                      if (showTopNavButtons) ...[
                        PlixBackButton(
                          focusNode: _backButtonFocus,
                          onPressed: () => Navigator.of(context).pop(),
                          onRight: () => _homeButtonFocus.requestFocus(),
                          onDown: _focusFirstItem,
                        ),
                        const SizedBox(width: 10),
                        PlixHomeButton(
                          focusNode: _homeButtonFocus,
                          onLeft: () => _backButtonFocus.requestFocus(),
                          onDown: _focusFirstItem,
                        ),
                        SizedBox(width: isCompact ? 12 : 20),
                      ],
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Grid Content
                Expanded(
                  child: _isLoadingInitial
                      ? Center(
                          child: CircularProgressIndicator(color: PlixTheme.plexGold),
                        )
                      : _items.isEmpty
                          ? const Center(
                              child: Text(
                                'No items found in this category.',
                                style: TextStyle(color: PlixTheme.textMuted, fontSize: 15),
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 36),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const spacing = 12.0;
                                  final totalWidth = constraints.maxWidth;
                                  final isLandscape =
                                      MediaQuery.of(context).orientation == Orientation.landscape || totalWidth >= 650;
                                  final int columns = isLandscape ? 6 : 3;
                                  final cardWidth = (totalWidth - (columns - 1) * spacing) / columns;
                                  final cardMainAxisExtent = (cardWidth * 1.5) + 42.0;
                                  final rowHeight = cardMainAxisExtent + 16.0;
                                  final totalRows = (_items.length / columns).ceil();

                                  while (_itemFocusNodes.length < _items.length) {
                                    _itemFocusNodes.add(FocusNode());
                                  }

                                  return CustomScrollView(
                                    controller: _scrollController,
                                    cacheExtent: 1500,
                                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                    slivers: [
                                      SliverPadding(
                                        padding: const EdgeInsets.only(top: 8, bottom: 20),
                                        sliver: SliverGrid(
                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: columns,
                                            mainAxisExtent: cardMainAxisExtent,
                                            crossAxisSpacing: spacing,
                                            mainAxisSpacing: 16,
                                          ),
                                          delegate: SliverChildBuilderDelegate(
                                            (context, index) {
                                              final item = _items[index];
                                              final fNode = _itemFocusNodes[index];
                                              final int row = index ~/ columns;

                                              VoidCallback onUp;
                                              if (row == 0) {
                                                onUp = () {
                                                  _scrollToRow(0, rowHeight);
                                                  if (_backButtonFocus.canRequestFocus) {
                                                    _backButtonFocus.requestFocus();
                                                  }
                                                };
                                              } else {
                                                onUp = () {
                                                  _scrollToRow(row - 1, rowHeight);
                                                  final targetIndex = index - columns;
                                                  if (targetIndex >= 0 && targetIndex < _itemFocusNodes.length) {
                                                    _itemFocusNodes[targetIndex].requestFocus();
                                                  }
                                                };
                                              }

                                              VoidCallback onDown;
                                              if (index + columns < _items.length) {
                                                onDown = () {
                                                  _scrollToRow(row + 1, rowHeight);
                                                  final targetIndex = index + columns;
                                                  if (targetIndex < _itemFocusNodes.length) {
                                                    _itemFocusNodes[targetIndex].requestFocus();
                                                  }
                                                };
                                              } else if (index < _items.length - 1) {
                                                onDown = () {
                                                  final targetRow = (_items.length - 1) ~/ columns;
                                                  _scrollToRow(targetRow, rowHeight);
                                                  _itemFocusNodes[_items.length - 1].requestFocus();
                                                };
                                              } else {
                                                onDown = () {};
                                              }

                                              final blockLeft = (index % columns == 0);
                                              final blockRight =
                                                  ((index + 1) % columns == 0 || index == _items.length - 1);

                                              return SeerrPosterCard(
                                                item: item,
                                                focusNode: fNode,
                                                onUp: onUp,
                                                onDown: onDown,
                                                scrollOnFocus: false,
                                                blockLeft: blockLeft,
                                                blockRight: blockRight,
                                                onFocused: () {
                                                  if (row >= totalRows - 2 && _hasMore && !_isLoadingMore) {
                                                    _loadNextPage();
                                                  }
                                                },
                                                onTap: () => _openRequestDialog(item),
                                              );
                                            },
                                            childCount: _items.length,
                                          ),
                                        ),
                                      ),
                                      if (_isLoadingMore)
                                        SliverToBoxAdapter(
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 32),
                                            child: Center(
                                              child: SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: PlixTheme.plexGold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        const SliverToBoxAdapter(
                                          child: SizedBox(height: 16),
                                        ),
                                    ],
                                  );
                                },
                              ),
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
