import 'dart:io';
import 'dart:math' as math;
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
  bool _isReorderMode = false;
  final Map<String, FocusNode> _itemFocusNodes = {};

  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _watchlistFocusNode = FocusNode();
  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _switchServerFocusNode = FocusNode();
  final FocusNode _signOutFocusNode = FocusNode();
  final FocusNode _reorderToggleFocusNode = FocusNode();

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
    _reorderToggleFocusNode.dispose();
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
        _activeReorderKey = lib.key;
      });
      widget.onLibrariesReordered?.call(List.from(_orderedLibraries));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _itemFocusNodes[lib.key]?.requestFocus();
        }
      });
    }
  }

  void _toggleReorderMode() {
    setState(() {
      _isReorderMode = !_isReorderMode;
      if (!_isReorderMode) {
        _activeReorderKey = null;
      }
    });
  }

  void _handleLibraryTap(PlexLibrary lib) {
    if (!_isReorderMode) {
      widget.onLibrarySelected(lib);
      return;
    }
    if (_activeReorderKey == lib.key) {
      setState(() => _activeReorderKey = null);
    } else {
      setState(() => _activeReorderKey = lib.key);
      _itemFocusNodes[lib.key]?.requestFocus();
    }
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
                        if (effectiveExpanded) {
                          _reorderToggleFocusNode.requestFocus();
                        } else {
                          _itemFocusNodes[_orderedLibraries.first.key]?.requestFocus();
                        }
                      } else {
                        _settingsFocusNode.requestFocus();
                      }
                    },
                    onNavigateRight: widget.onNavigateRight,
                    onTap: () => widget.onDestinationSelected(NavDestination.watchlist),
                  ),

                  // Libraries section header
                  if (_orderedLibraries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
                      child: effectiveExpanded
                          ? Row(
                              children: [
                                const Text(
                                  'LIBRARIES',
                                  style: TextStyle(
                                    color: PlixTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Divider(
                                    color: PlixTheme.cardBorder,
                                    height: 1,
                                    thickness: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _ReorderToggleButton(
                                  focusNode: _reorderToggleFocusNode,
                                  isActive: _isReorderMode,
                                  onToggle: _toggleReorderMode,
                                  onUp: () => _watchlistFocusNode.requestFocus(),
                                  onDown: () {
                                    if (_orderedLibraries.isNotEmpty) {
                                      _itemFocusNodes[_orderedLibraries.first.key]
                                          ?.requestFocus();
                                    } else {
                                      _settingsFocusNode.requestFocus();
                                    }
                                  },
                                  onNavigateRight: widget.onNavigateRight,
                                ),
                              ],
                            )
                          : const Divider(
                              color: PlixTheme.cardBorder,
                              height: 1,
                              thickness: 1,
                            ),
                    ),

                  // Dynamic library entries. In reorder mode: select to pick up,
                  // move with up/down, select again to drop.
                  for (int i = 0; i < _orderedLibraries.length; i++)
                    _NavItem(
                      key: ValueKey('nav_${_orderedLibraries[i].key}'),
                      focusNode: _itemFocusNodes.putIfAbsent(_orderedLibraries[i].key, () => FocusNode()),
                      icon: _orderedLibraries[i].isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                      label: _orderedLibraries[i].title,
                      isSelected: widget.activeDestination == NavDestination.library &&
                          widget.selectedLibrary?.key == _orderedLibraries[i].key,
                      isExpanded: effectiveExpanded,
                      isReorderMode: _isReorderMode,
                      isReorderPicked: _activeReorderKey == _orderedLibraries[i].key,
                      onUp: () {
                        if (_isReorderMode && _activeReorderKey == _orderedLibraries[i].key) {
                          _moveLibrary(_orderedLibraries[i], -1);
                          return;
                        }
                        if (i == 0) {
                          if (effectiveExpanded) {
                            _reorderToggleFocusNode.requestFocus();
                          } else {
                            _watchlistFocusNode.requestFocus();
                          }
                        } else {
                          _itemFocusNodes[_orderedLibraries[i - 1].key]?.requestFocus();
                        }
                      },
                      onDown: () {
                        if (_isReorderMode && _activeReorderKey == _orderedLibraries[i].key) {
                          _moveLibrary(_orderedLibraries[i], 1);
                          return;
                        }
                        if (i == _orderedLibraries.length - 1) {
                          _settingsFocusNode.requestFocus();
                        } else {
                          _itemFocusNodes[_orderedLibraries[i + 1].key]?.requestFocus();
                        }
                      },
                      onNavigateRight: widget.onNavigateRight,
                      onTap: () => _handleLibraryTap(_orderedLibraries[i]),
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
  final bool isReorderMode;
  final bool isReorderPicked;
  final VoidCallback onTap;
  final VoidCallback? onNavigateRight;
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
    this.isReorderMode = false,
    this.isReorderPicked = false,
    required this.onTap,
    this.onNavigateRight,
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
    final picked = widget.isReorderPicked;
    final reorderFocused = widget.isReorderMode && (_isFocused || _isHovered);
    final isHighlighted = _isFocused || _isHovered || picked;
    final activeColor = widget.isSelected ? PlixTheme.plexGold : PlixTheme.textSecondary;
    final fgColor = picked
        ? PlixTheme.plexGold
        : isHighlighted
            ? Colors.black
            : activeColor;
    final bgColor = picked
        ? PlixTheme.plexGold.withOpacity(0.16)
        : isHighlighted
            ? PlixTheme.plexGold
            : Colors.transparent;
    final shadows = picked
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.65),
              blurRadius: 22,
              offset: const Offset(0, 10),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: PlixTheme.plexGold.withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ]
        : reorderFocused
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: PlixTheme.plexGold.withOpacity(0.25),
                  blurRadius: 9,
                  spreadRadius: 1,
                ),
              ]
            : null;

    return AnimatedSlide(
      offset: Offset(0, picked ? -0.05 : reorderFocused ? -0.02 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: picked ? 1.09 : reorderFocused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        child: Focus(
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: shadows,
                ),
                child: CustomPaint(
                  foregroundPainter: picked
                      ? _DottedBorderPainter(color: PlixTheme.plexGold)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  final Color color;

  const _DottedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const strokeWidth = 2.0;
    const radius = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      math.max(0, size.width - strokeWidth),
      math.max(0, size.height - strokeWidth),
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 2.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 6.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ReorderToggleButton extends StatefulWidget {
  final FocusNode focusNode;
  final bool isActive;
  final VoidCallback onToggle;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback? onNavigateRight;

  const _ReorderToggleButton({
    required this.focusNode,
    required this.isActive,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    this.onNavigateRight,
  });

  @override
  State<_ReorderToggleButton> createState() => _ReorderToggleButtonState();
}

class _ReorderToggleButtonState extends State<_ReorderToggleButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ReorderToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      _isFocused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final iconColor = isHighlighted
        ? Colors.black
        : (widget.isActive ? PlixTheme.plexGold : PlixTheme.textMuted);
    final backgroundColor = isHighlighted
        ? PlixTheme.plexGold
        : (widget.isActive ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent);

    return Focus(
      focusNode: widget.focusNode,
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
            widget.onNavigateRight?.call();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onToggle();
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
