import 'dart:async';
import 'package:flutter/material.dart';
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
  final FocusNode _categoriesButtonFocusNode = FocusNode();
  bool _isLoading = true;
  String? _errorMessage;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};
  final ScrollController _gridScrollController = ScrollController();
  _LibrarySortOption _sortOption = _LibrarySortOption.nameAsc;
  Timer? _focusAdjustTimer;

  @override
  void initState() {
    super.initState();
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
    PlixImageCache.trim();
    super.dispose();
  }

  int _firstRowItemCount(bool isCompact) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCompact) {
      return (width / 130).floor().clamp(3, 7);
    }
    // Matches SliverGridDelegateWithMaxCrossAxisExtent's column calculation.
    final available = width - 48;
    return (available / (165 + 16)).ceil();
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
      appBar: AppBar(
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
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort library',
            onPressed: _showSortDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadItems(refresh: true),
          ),
        ],
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
                  : CustomScrollView(
                      controller: _gridScrollController,
                      cacheExtent: 150.0,
                      clipBehavior: Clip.none,
                      slivers: [
                        if (_selectedCategory != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: isCompact ? 14 : 24,
                                right: isCompact ? 14 : 24,
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
                                          'Category: $_selectedCategory',
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
                            right: isCompact ? 14 : 24,
                            top: _selectedCategory != null ? (isCompact ? 8 : 12) : (isCompact ? 14 : 20),
                            bottom: isCompact ? 24 : 140,
                          ),
                              sliver: SliverGrid(
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
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final item = _items[index];
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
