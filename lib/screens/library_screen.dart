import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/plix_device_helper.dart';
import '../services/plix_image_cache.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_bottom_nav.dart';
import 'details_screen.dart';

class LibraryScreen extends StatefulWidget {
  final PlexLibrary library;
  final PlexServer server;
  final String clientId;

  const LibraryScreen({
    super.key,
    required this.library,
    required this.server,
    required this.clientId,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibrarySortOption {
  nameAsc,
  nameDesc,
  yearDesc,
  yearAsc,
  dateAdded,
}

class _LibraryScreenState extends State<LibraryScreen> {
  late PlexMediaService _mediaService;
  List<PlexMediaItem> _items = [];
  List<PlexMediaItem> _allItems = [];
  String? _selectedCategory;
  late final FocusNode _backButtonFocusNode = FocusNode(
    debugLabel: 'back_button',
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  late final FocusNode _categoriesButtonFocusNode = FocusNode(
    debugLabel: 'categories_button',
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  late final FocusNode _sortButtonFocusNode = FocusNode(
    debugLabel: 'sort_button',
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  late final FocusNode _refreshButtonFocusNode = FocusNode(
    debugLabel: 'refresh_button',
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  bool _isLoading = true;
  String? _errorMessage;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};
  final ScrollController _gridScrollController = ScrollController();
  _LibrarySortOption _sortOption = _LibrarySortOption.nameAsc;
  Timer? _focusAdjustTimer;
  static const List<String> _alphabetLetters = [
    '#',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];
  final Map<String, FocusNode> _alphabetFocusNodes = {};
  String? _activeAlphabetLetter;

  @override
  void initState() {
    super.initState();
    for (final letter in _alphabetLetters) {
      _alphabetFocusNodes[letter] = FocusNode(debugLabel: 'alpha_');
    }
    _categoriesButtonFocusNode.addListener(() {
      if (_categoriesButtonFocusNode.hasFocus && _activeAlphabetLetter != null && mounted) {
        setState(() => _activeAlphabetLetter = null);
      }
    });
    final effectiveServer = widget.library.server ?? widget.server;
    _mediaService = PlexMediaService(server: effectiveServer);
    _loadItems();
  }

  @override
  void dispose() {
    _focusAdjustTimer?.cancel();
    _gridScrollController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    for (final node in _alphabetFocusNodes.values) {
      node.dispose();
    }
    _alphabetFocusNodes.clear();
    _backButtonFocusNode.dispose();
    _categoriesButtonFocusNode.dispose();
    _sortButtonFocusNode.dispose();
    _refreshButtonFocusNode.dispose();
    PlixImageCache.trim();
    super.dispose();
  }

  int _gridCrossAxisCount(BuildContext context, bool isCompact) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCompact) {
      final available = width - 14 - 36;
      return (available / 120).floor().clamp(3, 7);
    }
    // Available width excludes left padding (24) and right alphabet rail area (54)
    final available = width - 24 - 54;
    return (available / (148 + 16)).ceil();
  }

  int _firstRowItemCount(bool isCompact) {
    return _gridCrossAxisCount(context, isCompact);
  }

  static String _getItemLetter(PlexMediaItem item) {
    final title = item.title.trimLeft();
    if (title.isEmpty) return '#';
    final first = title[0].toUpperCase();
    if (first.compareTo('A') >= 0 && first.compareTo('Z') <= 0) {
      return first;
    }
    return '#';
  }

  int? _findFirstIndexForLetter(String letter) {
    if (_items.isEmpty) return null;
    for (int i = 0; i < _items.length; i++) {
      if (_getItemLetter(_items[i]) == letter) {
        return i;
      }
    }
    if (_sortOption == _LibrarySortOption.nameAsc) {
      if (letter == '#') return 0;
      for (int i = 0; i < _items.length; i++) {
        final itemLetter = _getItemLetter(_items[i]);
        if (itemLetter != '#' && itemLetter.compareTo(letter) > 0) {
          return i;
        }
      }
      return _items.length - 1;
    }
    return null;
  }

  double _calculateRowHeight(BuildContext context, bool isCompact) {
    final cols = _gridCrossAxisCount(context, isCompact);
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisExtent = width - (isCompact ? 34.0 : 50.0) - (isCompact ? 14.0 : 24.0);
    final crossAxisSpacing = isCompact ? 10.0 : 16.0;
    final mainAxisSpacing = isCompact ? 12.0 : 18.0;
    final childAspectRatio = isCompact ? 0.51 : 0.52;
    final usableCrossAxisExtent = crossAxisExtent - crossAxisSpacing * (cols - 1);
    final childCrossAxisExtent = usableCrossAxisExtent / cols;
    final childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
    return childMainAxisExtent + mainAxisSpacing;
  }

  void _jumpToLetter(String letter) {
    final targetIndex = _findFirstIndexForLetter(letter);
    if (targetIndex == null) return;

    final isCompact = PlixDeviceHelper.isCompact(context);
    final cols = _gridCrossAxisCount(context, isCompact);
    final rowHeight = _calculateRowHeight(context, isCompact);
    final rowIndex = targetIndex ~/ cols;
    final topPadding = _selectedCategory != null
        ? (isCompact ? 54.0 : 68.0)
        : (isCompact ? 14.0 : 20.0);
    final maxScroll = _gridScrollController.hasClients
        ? _gridScrollController.position.maxScrollExtent
        : double.infinity;
    final targetOffset = (topPadding + (rowIndex * rowHeight)).clamp(0.0, maxScroll);

    if (_gridScrollController.hasClients) {
      _gridScrollController.jumpTo(targetOffset);
    }
    _lastSelectedIndex = targetIndex;
    setState(() => _activeAlphabetLetter = null);

    void focusTargetCard([int retry = 0]) {
      if (!mounted) return;
      final node = _focusNodes.putIfAbsent(targetIndex, () => FocusNode(debugLabel: 'card_'));
      node.requestFocus();
      if (node.context != null && node.context!.mounted) {
        Scrollable.ensureVisible(
          node.context!,
          alignment: 0.1,
          duration: Duration.zero,
        );
      } else if (retry < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusTargetCard(retry + 1);
        });
      } else {
        // Fallback: If target card isn't mounted yet, focus any mounted card in view
        // so focus NEVER gets stuck on the alphabet rail
        for (final entry in _focusNodes.entries) {
          if (entry.value.context != null && entry.value.context!.mounted) {
            _lastSelectedIndex = entry.key;
            entry.value.requestFocus();
            break;
          }
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusTargetCard();
    });
  }

  void _returnFocusToGrid() {
    setState(() => _activeAlphabetLetter = null);
    if (_items.isEmpty) return;

    final targetIndex = (_lastSelectedIndex ?? 0).clamp(0, _items.length - 1);
    _lastSelectedIndex = targetIndex;

    void focusCard([int retry = 0]) {
      if (!mounted) return;
      final node = _focusNodes.putIfAbsent(targetIndex, () => FocusNode(debugLabel: 'card_'));
      node.requestFocus();
      if (node.context != null && node.context!.mounted) {
        Scrollable.ensureVisible(node.context!, alignment: 0.1);
      } else if (retry < 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) => focusCard(retry + 1));
      }
    }

    focusCard();
  }
  void _focusAlphabetForIndex(int index) {
    _lastSelectedIndex = index;
    final item = _items[index];
    final letter = _getItemLetter(item);
    final targetNode = _alphabetFocusNodes[letter] ?? _alphabetFocusNodes['#'];
    setState(() => _activeAlphabetLetter = letter);
    targetNode?.requestFocus();
  }

  void _handleItemFocus(int index, bool isCompact) {
    if (isCompact) return;
    _focusAdjustTimer?.cancel();
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
        _focusAdjustTimer = Timer(const Duration(milliseconds: 80), scrollToTop);
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
      _focusAdjustTimer = Timer(const Duration(milliseconds: 80), adjustVisible);
    });
  }


  List<PlexMediaItem> _filterByCategory(List<PlexMediaItem> items) {
    if (_selectedCategory == null) return List.from(items);
    return items.where((it) {
      return it.genres.any((g) => g.toLowerCase() == _selectedCategory!.toLowerCase());
    }).toList();
  }

  List<String> get _availableCategories {
    final catSet = <String>{};
    for (final it in _allItems) {
      for (final g in it.genres) {
        final trimmed = g.trim();
        if (trimmed.isNotEmpty) catSet.add(trimmed);
      }
    }
    final list = catSet.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _showCategoriesDialog() {
    final categories = _availableCategories;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No categories or genres found for this library.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return _CategoryDialogContent(
          categories: categories,
          selectedCategory: _selectedCategory,
          allItems: _allItems,
          onSelect: (cat) {
            Navigator.of(ctx).pop();
            setState(() {
              _selectedCategory = cat;
              _items = _filterByCategory(_allItems);
            });
            _applySort();
          },
        );
      },
    );
  }

  void _showSortDialog() {
    final sortOptions = [
      {'opt': _LibrarySortOption.nameAsc, 'title': 'Name (A to Z)'},
      {'opt': _LibrarySortOption.nameDesc, 'title': 'Name (Z to A)'},
      {'opt': _LibrarySortOption.yearDesc, 'title': 'Release Year (Newest)'},
      {'opt': _LibrarySortOption.yearAsc, 'title': 'Release Year (Oldest)'},
      {'opt': _LibrarySortOption.dateAdded, 'title': 'Date Added (Recently Added)'},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return _SortDialogContent(
          options: sortOptions,
          currentSort: _sortOption,
          onSelect: (opt) {
            Navigator.of(ctx).pop();
            setState(() {
              _sortOption = opt;
            });
            _applySort();
          },
        );
      },
    );
  }

  void _applySort() {
    setState(() {
      switch (_sortOption) {
        case _LibrarySortOption.nameAsc:
          _items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          break;
        case _LibrarySortOption.nameDesc:
          _items.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
          break;
        case _LibrarySortOption.yearDesc:
          _items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
          break;
        case _LibrarySortOption.yearAsc:
          _items.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
          break;
        case _LibrarySortOption.dateAdded:
          _items.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
          break;
      }
    });
  }

  Future<void> _loadItems({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_mediaService.server.activeConnectionUri == null ||
          _mediaService.server.activeConnectionUri!.isEmpty) {
        final serverService = PlexServerService(authService: PlexAuthService());
        await serverService.testAndResolveBestConnection(_mediaService.server);
      }
      final items = await _mediaService.getLibraryItems(widget.library.key, libraryType: widget.library.type, refresh: refresh);
      if (mounted) {
        setState(() {
          _allItems = items;
          _items = _filterByCategory(items);
          _isLoading = false;
        });
        _applySort();
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
          _errorMessage = 'Failed to load library items: $e';
        });
      }
    }
  }

  void _onItemTap(PlexMediaItem item, int index) {
    _lastSelectedIndex = index;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: item,
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
      appBar: _AppBarWithUpKeyBlocked(
        appBar: AppBar(
          leading: IconButton(
            focusNode: _backButtonFocusNode,
            icon: const BackButtonIcon(),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        title: Text(widget.library.title),
        actions: [
          IconButton(
            focusNode: _categoriesButtonFocusNode,
            icon: Icon(
              _selectedCategory != null ? Icons.category_rounded : Icons.category_outlined,
              color: _selectedCategory != null ? PlixTheme.plexGold : Colors.white,
            ),
            tooltip: _selectedCategory != null ? 'Category: $_selectedCategory' : 'Categories',
            onPressed: _showCategoriesDialog,
          ),
          IconButton(
            focusNode: _sortButtonFocusNode,
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort library',
            onPressed: _showSortDialog,
          ),
          IconButton(
            focusNode: _refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadItems(refresh: true),
          ),
        ],
      ),
      ),
      bottomNavigationBar: (isCompact && !isTv)
          ? PlixBottomNav(
              currentIndex: 3,
              server: widget.server,
              clientId: widget.clientId,
            )
          : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No media found in this library.',
                        style: TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
                      ),
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          right: isCompact ? 34.0 : 50.0,
                          child: CustomScrollView(
                            controller: _gridScrollController,
                            cacheExtent: 150.0,
                            clipBehavior: Clip.none,
                            slivers: [
                              if (_selectedCategory != null)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: isCompact ? 14 : 24,
                                      right: 14,
                                      top: isCompact ? 10 : 16,
                                      bottom: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: PlixTheme.plexGold.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Category: ${_selectedCategory ?? ""}',
                                                style: TextStyle(color: PlixTheme.plexGold, fontSize: 13, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedCategory = null;
                                                    _items = _filterByCategory(_allItems);
                                                  });
                                                  _applySort();
                                                },
                                                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${_items.length} items',
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              SliverPadding(
                                padding: EdgeInsets.only(
                                  left: isCompact ? 14 : 24,
                                  right: 0,
                                  top: _selectedCategory != null ? (isCompact ? 8 : 12) : (isCompact ? 14 : 20),
                                  bottom: isCompact ? 24 : 140,
                                ),
                                sliver: SliverGrid(
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _gridCrossAxisCount(context, isCompact),
                                    crossAxisSpacing: isCompact ? 10 : 16,
                                    mainAxisSpacing: isCompact ? 12 : 18,
                                    childAspectRatio: isCompact ? 0.51 : 0.52,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final item = _items[index];
                                      final cols = _gridCrossAxisCount(context, isCompact);
                                      final isRightEdge = ((index + 1) % cols == 0) || (index == _items.length - 1);
                                      return LayoutBuilder(
                                        builder: (context, constraints) {
                                          return MediaCard(
                                            item: item,
                                            mediaService: _mediaService,
                                            focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                                            width: constraints.maxWidth,
                                            margin: EdgeInsets.zero,
                                            autofocus: !isCompact && index == (_lastSelectedIndex ?? 0),
                                            enableHighlight: !isCompact,
                                            onFocusChange: (focused) {
                                              if (focused) _handleItemFocus(index, isCompact);
                                            },
                                            onTap: () => _onItemTap(item, index),
                                            onRight: isRightEdge ? () => _focusAlphabetForIndex(index) : null,
                                          );
                                        },
                                      );
                                    },
                                    childCount: _items.length,
                                    addAutomaticKeepAlives: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: isCompact ? 6 : 10,
                          bottom: isCompact ? 6 : 8,
                          right: isCompact ? 4 : 8,
                          child: _buildAlphabetColumn(isCompact),
                        ),
                        if (_activeAlphabetLetter != null)
                          _buildActiveLetterBadge(isCompact),
                      ],
                    ),
    );
  }

  Widget _buildAlphabetColumn(bool isCompact) {
    final availableLetters = _items.map(_getItemLetter).toSet();

    return Container(
      width: isCompact ? 28 : 34,
      padding: EdgeInsets.symmetric(
        vertical: isCompact ? 4 : 6,
        horizontal: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < _alphabetLetters.length; i++)
            Expanded(
              child: _AlphabetLetterButton(
                letter: _alphabetLetters[i],
                hasItems: availableLetters.contains(_alphabetLetters[i]),
                focusNode: _alphabetFocusNodes[_alphabetLetters[i]]!,
                isCompact: isCompact,
                blockDown: i == _alphabetLetters.length - 1,
                onUp: i == 0
                    ? () {
                        setState(() => _activeAlphabetLetter = null);
                        _categoriesButtonFocusNode.requestFocus();
                      }
                    : null,
                onFocus: (letter) {
                  setState(() => _activeAlphabetLetter = letter);
                },
                onLeft: _returnFocusToGrid,
                onSelect: (letter) {
                  _jumpToLetter(letter);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveLetterBadge(bool isCompact) {
    if (_activeAlphabetLetter == null) return const SizedBox.shrink();

    return Positioned(
      right: isCompact ? 40 : 54,
      top: 0,
      bottom: isCompact ? 6 : 8,
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B2E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: PlixTheme.plexGold.withOpacity(0.85),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.65),
                blurRadius: 18,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: PlixTheme.plexGold.withOpacity(0.25),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            _activeAlphabetLetter!,
            style: TextStyle(
              color: PlixTheme.plexGold,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlphabetLetterButton extends StatefulWidget {
  final String letter;
  final bool hasItems;
  final FocusNode focusNode;
  final bool isCompact;
  final bool blockDown;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onFocus;
  final VoidCallback onLeft;
  final VoidCallback? onUp;

  const _AlphabetLetterButton({
    required this.letter,
    required this.hasItems,
    required this.focusNode,
    this.isCompact = false,
    this.blockDown = false,
    required this.onSelect,
    required this.onFocus,
    required this.onLeft,
    this.onUp,
  });

  @override
  State<_AlphabetLetterButton> createState() => _AlphabetLetterButtonState();
}

class _AlphabetLetterButtonState extends State<_AlphabetLetterButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_AlphabetLetterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      final focused = widget.focusNode.hasFocus;
      if (_isFocused != focused) {
        setState(() => _isFocused = focused);
        if (focused) widget.onFocus(widget.letter);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeft();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.blockDown) {
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA ||
              event.logicalKey == LogicalKeyboardKey.gameButtonSelect ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onSelect(widget.letter);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => widget.onSelect(widget.letter),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(
              vertical: widget.isCompact ? 0.5 : 1.0,
              horizontal: 1.0,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _isFocused
                  ? PlixTheme.plexGold
                  : _isHovered
                      ? Colors.white.withOpacity(0.18)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Text(
              widget.letter,
              style: TextStyle(
                color: _isFocused
                    ? Colors.black
                    : widget.hasItems
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white.withOpacity(0.25),
                fontSize: 11,
                fontWeight: _isFocused ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class _CategoryDialogContent extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final List<PlexMediaItem> allItems;
  final ValueChanged<String?> onSelect;

  const _CategoryDialogContent({
    required this.categories,
    required this.selectedCategory,
    required this.allItems,
    required this.onSelect,
  });

  @override
  State<_CategoryDialogContent> createState() => _CategoryDialogContentState();
}

class _CategoryDialogContentState extends State<_CategoryDialogContent> {
  final FocusNode _allCategoriesFocusNode = FocusNode();
  final Map<String, FocusNode> _categoryFocusNodes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.selectedCategory == null) {
        _allCategoriesFocusNode.requestFocus();
        Scrollable.ensureVisible(context, alignment: 0.5);
      } else {
        final node = _categoryFocusNodes[widget.selectedCategory!.toLowerCase()];
        if (node != null) {
          node.requestFocus();
          if (node.context != null) {
            Scrollable.ensureVisible(node.context!, alignment: 0.5);
          }
        } else {
          _allCategoriesFocusNode.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    _allCategoriesFocusNode.dispose();
    for (final node in _categoryFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PlixTheme.cardBorder, width: 1.5),
      ),
      title: Row(
        children: [
          Icon(Icons.category_rounded, color: PlixTheme.plexGold, size: 22),
          const SizedBox(width: 10),
          const Text('Filter by Category', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                focusNode: _allCategoriesFocusNode,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: widget.selectedCategory == null ? PlixTheme.plexGold.withOpacity(0.18) : Colors.transparent,
                leading: Icon(Icons.apps_rounded, color: widget.selectedCategory == null ? PlixTheme.plexGold : Colors.white70),
                title: const Text('All Categories', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                trailing: widget.selectedCategory == null ? Icon(Icons.check_rounded, color: PlixTheme.plexGold) : null,
                onTap: () => widget.onSelect(null),
              ),
              const Divider(color: Colors.white12),
              for (final cat in widget.categories) ...[
                Builder(
                  builder: (tileCtx) {
                    final count = widget.allItems.where((it) => it.genres.any((g) => g.toLowerCase() == cat.toLowerCase())).length;
                    final isSel = widget.selectedCategory?.toLowerCase() == cat.toLowerCase();
                    final node = _categoryFocusNodes.putIfAbsent(cat.toLowerCase(), () => FocusNode());
                    return ListTile(
                      focusNode: node,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: isSel ? PlixTheme.plexGold.withOpacity(0.18) : Colors.transparent,
                      title: Text(cat, style: TextStyle(color: isSel ? PlixTheme.plexGold : Colors.white, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$count', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (isSel) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_rounded, color: PlixTheme.plexGold, size: 18),
                          ],
                        ],
                      ),
                      onTap: () => widget.onSelect(cat),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

class _SortDialogContent extends StatefulWidget {
  final List<Map<String, dynamic>> options;
  final _LibrarySortOption currentSort;
  final ValueChanged<_LibrarySortOption> onSelect;

  const _SortDialogContent({
    required this.options,
    required this.currentSort,
    required this.onSelect,
  });

  @override
  State<_SortDialogContent> createState() => _SortDialogContentState();
}

class _SortDialogContentState extends State<_SortDialogContent> {
  final Map<_LibrarySortOption, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusNodes[widget.currentSort] ?? _focusNodes[widget.options.first['opt'] as _LibrarySortOption];
      if (node != null) {
        node.requestFocus();
        if (node.context != null) {
          Scrollable.ensureVisible(node.context!, alignment: 0.5);
        }
      }
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PlixTheme.cardBorder, width: 1.5),
      ),
      title: Row(
        children: [
          Icon(Icons.sort_rounded, color: PlixTheme.plexGold, size: 22),
          const SizedBox(width: 10),
          const Text('Sort Library', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in widget.options) ...[
                Builder(
                  builder: (tileCtx) {
                    final opt = item['opt'] as _LibrarySortOption;
                    final title = item['title'] as String;
                    final isSel = widget.currentSort == opt;
                    final node = _focusNodes.putIfAbsent(opt, () => FocusNode());
                    return ListTile(
                      focusNode: node,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: isSel ? PlixTheme.plexGold.withOpacity(0.18) : Colors.transparent,
                      title: Text(title, style: TextStyle(color: isSel ? PlixTheme.plexGold : Colors.white, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      trailing: isSel ? Icon(Icons.check_rounded, color: PlixTheme.plexGold, size: 18) : null,
                      onTap: () => widget.onSelect(opt),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}


class _AppBarWithUpKeyBlocked extends StatelessWidget implements PreferredSizeWidget {
  final AppBar appBar;

  const _AppBarWithUpKeyBlocked({required this.appBar});

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: appBar,
    );
  }
}
