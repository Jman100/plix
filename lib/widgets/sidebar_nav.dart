import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_server.dart';
import '../services/plix_device_helper.dart';

enum NavDestination {
  home,
  watchlist,
  search,
  library,
  settings,
  switchServer,
  signOut,
}

class SidebarNav extends StatefulWidget {
  final PlexServer? currentServer;
  final List<PlexLibrary> libraries;
  final PlexLibrary? selectedLibrary;
  final NavDestination activeDestination;
  final ValueChanged<NavDestination> onDestinationSelected;
  final ValueChanged<PlexLibrary> onLibrarySelected;
  final VoidCallback onSignOut;
  final VoidCallback onSwitchServer;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onNavigateRight;
  final FocusNode? homeFocusNode;
  final ValueChanged<bool>? onFocusChange;

  final ValueChanged<List<PlexLibrary>>? onLibrariesReordered;

  const SidebarNav({
    super.key,
    required this.currentServer,
    required this.libraries,
    this.selectedLibrary,
    required this.activeDestination,
    required this.onDestinationSelected,
    required this.onLibrarySelected,
    required this.onSignOut,
    required this.onSwitchServer,
    this.onOpenSettings,
    this.onNavigateRight,
    this.homeFocusNode,
    this.onFocusChange,
    this.onLibrariesReordered,
  });

  @override
  State<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends State<SidebarNav> {
  bool _isExpanded = false;
  late List<PlexLibrary> _orderedLibraries;
  String? _activeReorderKey;
  final Map<String, FocusNode> _reorderFocusNodes = {};
  final Map<String, FocusNode> _itemFocusNodes = {};

  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _watchlistFocusNode = FocusNode();
  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _switchServerFocusNode = FocusNode();
  final FocusNode _signOutFocusNode = FocusNode();

  void _scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0.0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _orderedLibraries = List.from(widget.libraries);
  }

  @override
  void didUpdateWidget(covariant SidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.libraries != oldWidget.libraries) {
      _orderedLibraries = List.from(widget.libraries);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _watchlistFocusNode.dispose();
    _settingsFocusNode.dispose();
    _switchServerFocusNode.dispose();
    _signOutFocusNode.dispose();
    for (final node in _reorderFocusNodes.values) {
      node.dispose();
    }
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _moveLibrary(PlexLibrary lib, int delta) {
    final idx = _orderedLibraries.indexOf(lib);
    if (idx == -1) return;
    final target = idx + delta;
    if (target >= 0 && target < _orderedLibraries.length) {
      setState(() {
        final item = _orderedLibraries.removeAt(idx);
        _orderedLibraries.insert(target, item);
        if (Platform.isWindows) {
          _activeReorderKey = null;
        } else {
          _activeReorderKey = lib.key;
        }
      });
      widget.onLibrariesReordered?.call(List.from(_orderedLibraries));
      if (!Platform.isWindows) {
        _reorderFocusNodes[lib.key]?.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _reorderFocusNodes[lib.key]?.requestFocus();
          }
        });
      } else {
        _reorderFocusNodes[lib.key]?.unfocus();
      }
    }
  }

  void _reorderLibraryToIndex(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || fromIndex >= _orderedLibraries.length) return;
    if (toIndex < 0 || toIndex >= _orderedLibraries.length) return;
    setState(() {
      final item = _orderedLibraries.removeAt(fromIndex);
      _orderedLibraries.insert(toIndex, item);
      _activeReorderKey = null;
    });
    for (final node in _reorderFocusNodes.values) {
      node.unfocus();
    }
    widget.onLibrariesReordered?.call(List.from(_orderedLibraries));
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLandscape = !Platform.isWindows &&
        !PlixDeviceHelper.isTelevision &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    final effectiveExpanded = isMobileLandscape || _isExpanded;
    final width = effectiveExpanded ? 245.0 : 72.0;

    return MouseRegion(
      onEnter: (_) {
        if (Platform.isWindows) {
          setState(() {
            _isExpanded = true;
          });
          _scrollToTop();
          widget.onFocusChange?.call(true);
        }
      },
      onExit: (_) {
        if (Platform.isWindows) {
          setState(() {
            _isExpanded = false;
          });
          widget.onFocusChange?.call(false);
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasNavFocus) {
          if (!Platform.isWindows) {
            setState(() {
              _isExpanded = hasNavFocus;
            });
            if (hasNavFocus) {
              _scrollToTop();
            }
            widget.onFocusChange?.call(hasNavFocus);
          }
        },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: width,
        color: PlixTheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header / Logo with Server Name beside it when expanded
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (!effectiveExpanded)
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: PlixTheme.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4)),
                      ),
                      child: Center(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                text: 'p',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Trebuchet MS',
                                ),
                              ),
                              TextSpan(
                                text: 'x',
                                style: TextStyle(
                                  color: PlixTheme.plexGold,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Trebuchet MS',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (effectiveExpanded) ...[
                    RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'pli',
                            style: TextStyle(
                              color: PlixTheme.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Trebuchet MS',
                              letterSpacing: 0.5,
                            ),
                          ),
                          TextSpan(
                            text: 'x',
                            style: TextStyle(
                              color: PlixTheme.plexGold,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Trebuchet MS',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.currentServer != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 16,
                        color: PlixTheme.cardBorder,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.currentServer!.isJellyfin ? Icons.hub_rounded : Icons.dns,
                              size: 13,
                              color: widget.currentServer!.isJellyfin ? const Color(0xFF00A4DC) : PlixTheme.plexGold,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                widget.currentServer!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            const Divider(color: PlixTheme.cardBorder, height: 1),

            // Navigation Items (Home, Search, Watchlist, Libraries, Settings, Switch Server, Sign Out)
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _NavItem(
                    focusNode: widget.homeFocusNode ?? _itemFocusNodes.putIfAbsent('home', () => FocusNode()),
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isSelected: widget.activeDestination == NavDestination.home,
                    isExpanded: effectiveExpanded,
                    blockUp: true,
                    onDown: () => _searchFocusNode.requestFocus(),
                    onFocusChange: (focused) {
                      if (focused) _scrollToTop();
                    },
                    onNavigateRight: widget.onNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.home),
                  ),

                  _NavItem(
                    focusNode: _searchFocusNode,
                    icon: Icons.search_rounded,
                    label: 'Search',
                    isSelected: widget.activeDestination == NavDestination.search,
                    isExpanded: effectiveExpanded,
                    onUp: () {
                      (widget.homeFocusNode ?? _itemFocusNodes['home'])?.requestFocus();
                      _scrollToTop();
                    },
                    onDown: () => _watchlistFocusNode.requestFocus(),
                    onNavigateRight: widget.onNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.search),
                  ),

                  _NavItem(
                    focusNode: _watchlistFocusNode,
                    icon: Icons.bookmark_rounded,
                    label: 'Watchlist',
                    isSelected: widget.activeDestination == NavDestination.watchlist,
                    isExpanded: effectiveExpanded,
                    onUp: () => _searchFocusNode.requestFocus(),
                    onDown: () {
                      if (_orderedLibraries.isNotEmpty) {
                        _itemFocusNodes[_orderedLibraries.first.key]?.requestFocus();
                      } else {
                        _settingsFocusNode.requestFocus();
                      }
                    },
                    onNavigateRight: widget.onNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.watchlist),
                  ),

                  // Dynamic library entries (Movies, TV Shows) with drag-and-drop & reorder handle
                  for (int i = 0; i < _orderedLibraries.length; i++)
                    DragTarget<int>(
                      key: ValueKey('drag_target_${_orderedLibraries[i].key}'),
                      onWillAcceptWithDetails: (details) => details.data != i,
                      onAcceptWithDetails: (details) {
                        _reorderLibraryToIndex(details.data, i);
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isDropTarget = candidateData.isNotEmpty;
                        return Container(
                          decoration: isDropTarget
                              ? BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: PlixTheme.plexGold,
                                      width: 3.0,
                                    ),
                                  ),
                                  color: PlixTheme.cardFocused.withOpacity(0.3),
                                )
                              : null,
                          child: Row(
                            key: ValueKey('lib_row_${_orderedLibraries[i].key}'),
                            children: [
                              if (effectiveExpanded)
                                Draggable<int>(
                                  data: i,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      width: 200,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: PlixTheme.cardFocused,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: PlixTheme.plexGold, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.6),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.drag_handle_rounded, color: PlixTheme.plexGold, size: 18),
                                          const SizedBox(width: 8),
                                          Icon(
                                            _orderedLibraries[i].isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                            color: PlixTheme.plexGold,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Flexible(
                                            child: Text(
                                              _orderedLibraries[i].title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.3,
                                    child: _ReorderHandle(
                                      key: ValueKey('reorder_${_orderedLibraries[i].key}'),
                                      focusNode: _reorderFocusNodes.putIfAbsent(_orderedLibraries[i].key, () => FocusNode()),
                                      isReordering: _activeReorderKey == _orderedLibraries[i].key,
                                      onUp: () => _moveLibrary(_orderedLibraries[i], -1),
                                      onDown: () => _moveLibrary(_orderedLibraries[i], 1),
                                      onRight: () {
                                        setState(() => _activeReorderKey = null);
                                        _itemFocusNodes[_orderedLibraries[i].key]?.requestFocus();
                                      },
                                      onSelect: () {
                                        setState(() => _activeReorderKey = null);
                                        _itemFocusNodes[_orderedLibraries[i].key]?.requestFocus();
                                      },
                                    ),
                                  ),
                                  child: _ReorderHandle(
                                    key: ValueKey('reorder_${_orderedLibraries[i].key}'),
                                    focusNode: _reorderFocusNodes.putIfAbsent(_orderedLibraries[i].key, () => FocusNode()),
                                    isReordering: _activeReorderKey == _orderedLibraries[i].key,
                                    onUp: () => _moveLibrary(_orderedLibraries[i], -1),
                                    onDown: () => _moveLibrary(_orderedLibraries[i], 1),
                                    onRight: () {
                                      setState(() => _activeReorderKey = null);
                                      _itemFocusNodes[_orderedLibraries[i].key]?.requestFocus();
                                    },
                                    onSelect: () {
                                      setState(() => _activeReorderKey = null);
                                      _itemFocusNodes[_orderedLibraries[i].key]?.requestFocus();
                                    },
                                  ),
                                ),
                              Expanded(
                                child: _NavItem(
                                  key: ValueKey('nav_${_orderedLibraries[i].key}'),
                                  focusNode: _itemFocusNodes.putIfAbsent(_orderedLibraries[i].key, () => FocusNode()),
                                  icon: _orderedLibraries[i].isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                  label: _orderedLibraries[i].title,
                                  isSelected: widget.activeDestination == NavDestination.library &&
                                      widget.selectedLibrary?.key == _orderedLibraries[i].key,
                                  isExpanded: effectiveExpanded,
                                  onUp: () {
                                    if (i == 0) {
                                      _watchlistFocusNode.requestFocus();
                                    } else {
                                      _itemFocusNodes[_orderedLibraries[i - 1].key]?.requestFocus();
                                    }
                                  },
                                  onDown: () {
                                    if (i == _orderedLibraries.length - 1) {
                                      _settingsFocusNode.requestFocus();
                                    } else {
                                      _itemFocusNodes[_orderedLibraries[i + 1].key]?.requestFocus();
                                    }
                                  },
                                  onNavigateLeft: effectiveExpanded ? () => _reorderFocusNodes[_orderedLibraries[i].key]?.requestFocus() : null,
                                  onNavigateRight: widget.onNavigateRight,
                                  onTap: () => widget.onLibrarySelected(_orderedLibraries[i]),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const Divider(color: PlixTheme.cardBorder, height: 20),

                  _NavItem(
                    focusNode: _settingsFocusNode,
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    isSelected: widget.activeDestination == NavDestination.settings,
                    isExpanded: effectiveExpanded,
                    onUp: () {
                      if (_orderedLibraries.isNotEmpty) {
                        _itemFocusNodes[_orderedLibraries.last.key]?.requestFocus();
                      } else {
                        _watchlistFocusNode.requestFocus();
                      }
                    },
                    onDown: () => _switchServerFocusNode.requestFocus(),
                    onNavigateRight: widget.onNavigateRight,
                    onTap: () {
                      if (widget.onOpenSettings != null) {
                        widget.onOpenSettings!();
                      } else {
                        widget.onDestinationSelected(NavDestination.settings);
                      }
                    },
                  ),

                  _NavItem(
                    focusNode: _switchServerFocusNode,
                    icon: Icons.swap_horiz_rounded,
                    label: 'Switch Server',
                    isSelected: widget.activeDestination == NavDestination.switchServer,
                    isExpanded: effectiveExpanded,
                    onUp: () => _settingsFocusNode.requestFocus(),
                    onDown: () => _signOutFocusNode.requestFocus(),
                    onNavigateRight: widget.onNavigateRight,
                    onTap: widget.onSwitchServer,
                  ),

                  _NavItem(
                    focusNode: _signOutFocusNode,
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    isSelected: widget.activeDestination == NavDestination.signOut,
                    isExpanded: effectiveExpanded,
                    onUp: () => _switchServerFocusNode.requestFocus(),
                    blockDown: true,
                    onNavigateRight: widget.onNavigateRight,
                    onTap: widget.onSignOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateLeft;
  final FocusNode? focusNode;
  final bool blockUp;
  final bool blockDown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final ValueChanged<bool>? onFocusChange;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    this.onNavigateRight,
    this.onNavigateLeft,
    this.focusNode,
    this.blockUp = false,
    this.blockDown = false,
    this.onUp,
    this.onDown,
    this.onFocusChange,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        final renderObject = context.findRenderObject() as RenderBox?;
        final scrollable = Scrollable.maybeOf(context);
        if (renderObject != null && scrollable != null) {
          final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
          if (scrollableBox != null) {
            final itemOffset = renderObject.localToGlobal(Offset.zero, ancestor: scrollableBox);
            final itemTop = itemOffset.dy;
            final itemBottom = itemTop + renderObject.size.height;
            final viewportHeight = scrollable.position.viewportDimension;
            final currentOffset = scrollable.position.pixels;

            // Only scroll down once the cursor is towards the bottom of the screen (> 80% of viewport)
            if (itemBottom > viewportHeight * 0.80) {
              final target = (currentOffset + (itemBottom - viewportHeight * 0.80)).clamp(0.0, scrollable.position.maxScrollExtent);
              scrollable.position.animateTo(
                target,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              );
            } else if (itemTop < 0) {
              // When moving back up, scroll up just enough to keep item visible
              final target = (currentOffset + itemTop).clamp(0.0, scrollable.position.maxScrollExtent);
              scrollable.position.animateTo(
                target,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              );
            }
          }
        }
      }
      widget.onFocusChange?.call(_focusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final activeColor = widget.isSelected ? PlixTheme.plexGold : PlixTheme.textSecondary;
    final fgColor = isHighlighted ? Colors.black : activeColor;
    final bgColor = isHighlighted ? PlixTheme.plexGold : Colors.transparent;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
              return KeyEventResult.handled;
            }
            if (widget.blockUp) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            if (widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            if (widget.blockDown) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            if (widget.onNavigateLeft != null) {
              widget.onNavigateLeft!();
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            if (widget.onNavigateRight != null) {
              widget.onNavigateRight!();
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent && (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovered) {
          if (Platform.isWindows && mounted) {
            setState(() => _isHovered = hovered);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: fgColor,
              ),
              if (widget.isExpanded) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 14,
                      fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderHandle extends StatefulWidget {
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRight;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final bool isReordering;

  const _ReorderHandle({
    super.key,
    required this.onUp,
    required this.onDown,
    required this.onRight,
    required this.onSelect,
    this.focusNode,
    this.isReordering = false,
  });

  @override
  State<_ReorderHandle> createState() => _ReorderHandleState();
}

class _ReorderHandleState extends State<_ReorderHandle> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ReorderHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _isFocused = _focusNode.hasFocus;
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = Platform.isWindows
        ? _isHovered
        : (_focusNode.hasFocus || _isFocused || widget.isReordering);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            widget.onUp();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onRight();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (Platform.isWindows && mounted) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if (Platform.isWindows && mounted) {
            setState(() => _isHovered = false);
          }
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 8, right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: isHighlighted ? PlixTheme.plexGold : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onUp,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 14,
                    color: isHighlighted ? Colors.black : PlixTheme.textMuted,
                  ),
                ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 14,
                  color: isHighlighted ? Colors.black : PlixTheme.textMuted,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDown,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: isHighlighted ? Colors.black : PlixTheme.textMuted,
                  ),
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
