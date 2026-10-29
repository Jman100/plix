import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/native_player_service.dart';
import '../services/plex_media_service.dart';
import '../services/plix_device_helper.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import 'details_screen.dart';
import '../widgets/plix_bottom_nav.dart';

class SearchScreen extends StatefulWidget {
  final PlexServer server;
  final String clientId;

  const SearchScreen({
    super.key,
    required this.server,
    required this.clientId,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late PlexMediaService _mediaService;
  final NativePlayerService _playerService = NativePlayerService();

  String _query = '';
  List<PlexMediaItem> _results = [];
  bool _isSearching = false;
  bool _isListening = false;
  Timer? _debounceTimer;

  // Windows Text Search controller and node
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();

  // Header focus nodes
  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _homeButtonFocus = FocusNode();
  final FocusNode _micButtonFocus = FocusNode();
  final FocusNode _clearButtonFocus = FocusNode();

  // Standard 4-row x 10-key QWERTY TV Keyboard Grid
  static const List<List<String>> _keyboardGrid = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', '\''],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'CLEAR', 'SPACE', 'BACK'],
  ];

  final Map<String, FocusNode> _keyFocusNodes = {};
  final Map<String, FocusNode> _resultFocusNodes = {};
  FocusNode? _lastFocusedKeyboardNode;

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);

    // Initialize all 40 key focus nodes
    for (final row in _keyboardGrid) {
      for (final key in row) {
        _keyFocusNodes[key] = FocusNode();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (Platform.isWindows) {
          _textFieldFocusNode.requestFocus();
        } else if (PlixDeviceHelper.isTelevision) {
          // Default TV cursor to the first letter 'Q'
          _keyFocusNodes['Q']?.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    _textFieldFocusNode.dispose();
    _backButtonFocus.dispose();
    _homeButtonFocus.dispose();
    _micButtonFocus.dispose();
    _clearButtonFocus.dispose();
    for (final node in _keyFocusNodes.values) {
      node.dispose();
    }
    for (final node in _resultFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();
    if (_query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  Future<void> _performSearch() async {
    final queryText = _query.trim();
    if (queryText.isEmpty) {
      if (mounted) setState(() => _isSearching = false);
      return;
    }

    try {
      final items = await _mediaService.search(queryText);
      if (mounted) {
        for (final item in items) {
          _resultFocusNodes.putIfAbsent(item.ratingKey, () => FocusNode());
        }
        setState(() {
          _results = items;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = [];
          _isSearching = false;
        });
      }
    }
  }

  void _handleKeyInput(String char) {
    setState(() {
      _query += char;
    });
    _onQueryChanged();
  }

  void _handleBackspace() {
    if (_query.isNotEmpty) {
      setState(() {
        _query = _query.substring(0, _query.length - 1);
      });
      _onQueryChanged();
    }
  }

  void _handleClear() {
    _textController.clear();
    setState(() {
      _query = '';
      _results = [];
      _isSearching = false;
    });
    if ((Platform.isWindows || Platform.isLinux) && mounted) {
      _textFieldFocusNode.requestFocus();
    }
  }

  Future<void> _startVoiceSearch() async {
    if (_isListening) return;
    setState(() => _isListening = true);

    try {
      final spokenText = await _playerService.startVoiceRecognition();
      if (mounted) {
        setState(() => _isListening = false);
        if (spokenText.trim().isNotEmpty) {
          setState(() {
            _query = spokenText.trim();
          });
          _performSearch();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusFirstResult();
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  void _focusFirstResult() {
    if (_results.isNotEmpty) {
      final firstKey = _results.first.ratingKey;
      _resultFocusNodes[firstKey]?.requestFocus();
    }
  }

  void _focusKeyboardReturn() {
    if (_lastFocusedKeyboardNode != null &&
        _lastFocusedKeyboardNode!.canRequestFocus) {
      _lastFocusedKeyboardNode!.requestFocus();
    } else {
      _keyFocusNodes['Q']?.requestFocus();
    }
  }

  void _openItem(PlexMediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: item,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlixDeviceHelper.isTelevision && !(Platform.isWindows || Platform.isLinux);
    final isCompact = PlixDeviceHelper.isCompact(context);

    return Scaffold(
      backgroundColor: PlixTheme.background,
      bottomNavigationBar: (isCompact && !isTv)
          ? PlixBottomNav(
              currentIndex: 2,
              server: widget.server,
              clientId: widget.clientId,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Back button, Search Query Box, Clear, Voice Mic
            _buildTopBar(isTv: isTv, isCompact: isCompact),

            const SizedBox(height: 12),

            // Content: On TV, keyboard + results; On phone/desktop, full-width results
            if (!isTv)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32),
                  child: _buildResultsSection(isFullWidth: true),
                ),
              )
            else
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: 10-key uniform QWERTY TV Keyboard
                    SizedBox(
                      width: 480,
                      child: _buildKeyboardSection(),
                    ),

                    // Divider between Keyboard and Results
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: PlixTheme.cardBorder,
                    ),

                    // Right: Search Results Grid in rows of 3 (2.5 rows visible)
                    Expanded(
                      child: _buildResultsSection(isFullWidth: false),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({required bool isTv, required bool isCompact}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 12),
      child: Row(
        children: [
          if (!Platform.isAndroid || PlixDeviceHelper.isTelevision) ...[
            PlixBackButton(
              focusNode: _backButtonFocus,
              onRight: () => _homeButtonFocus.requestFocus(),
              onDown: () => _keyFocusNodes['1']?.requestFocus(),
            ),
            const SizedBox(width: 10),
            PlixHomeButton(
              focusNode: _homeButtonFocus,
              onLeft: () => _backButtonFocus.requestFocus(),
              onDown: () => _keyFocusNodes['1']?.requestFocus(),
            ),
            SizedBox(width: isCompact ? 12 : 20),
          ],

          // Search Bar display
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 16, right: 6),
              decoration: BoxDecoration(
                color: PlixTheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: PlixTheme.cardBorder, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: PlixTheme.plexGold,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: !isTv
                        ? TextField(
                            controller: _textController,
                            focusNode: _textFieldFocusNode,
                            cursorColor: PlixTheme.plexGold,
                            autofocus: false,
                            style: const TextStyle(
                              color: PlixTheme.textPrimary,
                              fontSize: 16,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search movies, TV shows, episodes...',
                              hintStyle: TextStyle(
                                color: PlixTheme.textMuted,
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (val) {
                              _query = val;
                              _onQueryChanged();
                            },
                          )
                        : Text(
                            _query.isEmpty ? 'Search movies, TV shows, episodes...' : _query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _query.isEmpty ? PlixTheme.textMuted : PlixTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: _query.isEmpty ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                  ),
                  if (_query.isNotEmpty) ...[
                    _TvIconButton(
                      focusNode: _clearButtonFocus,
                      icon: Icons.close_rounded,
                      tooltip: 'Clear',
                      size: 32,
                      iconSize: 18,
                      onPressed: _handleClear,
                      onDown: () => _keyFocusNodes['5']?.requestFocus(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (!(Platform.isWindows || Platform.isLinux)) ...[
            SizedBox(width: isCompact ? 8 : 14),

            // Voice Search Mic Button
            _TvIconButton(
              focusNode: _micButtonFocus,
              icon: _isListening ? Icons.mic : Icons.mic_none_rounded,
              highlightColor: _isListening ? Colors.redAccent : PlixTheme.plexGold,
              tooltip: 'Voice Search',
              onPressed: _startVoiceSearch,
              onDown: () => _keyFocusNodes['0']?.requestFocus(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyboardSection() {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final char = event.character;
          if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
            _handleKeyInput(char.toUpperCase());
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _handleBackspace();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 8, top: 12, bottom: 20),
        child: Column(
          children: [
            // 4 Equal Rows of 10 Keys each
            for (int r = 0; r < _keyboardGrid.length; r++) ...[
              Row(
                children: [
                  for (int c = 0; c < _keyboardGrid[r].length; c++) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: _buildGridKey(r, c),
                      ),
                    ),
                  ],
                ],
              ),
              if (r < _keyboardGrid.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGridKey(int row, int col) {
    final keyId = _keyboardGrid[row][col];
    final node = _keyFocusNodes[keyId]!;

    String label = keyId;
    IconData? icon;
    VoidCallback onPressed;

    if (keyId == 'CLEAR') {
      label = '';
      icon = Icons.delete_outline_rounded;
      onPressed = _handleClear;
    } else if (keyId == 'SPACE') {
      label = '';
      icon = Icons.space_bar_rounded;
      onPressed = () => _handleKeyInput(' ');
    } else if (keyId == 'BACK') {
      label = '';
      icon = Icons.backspace_outlined;
      onPressed = _handleBackspace;
    } else {
      label = keyId;
      icon = null;
      onPressed = () => _handleKeyInput(keyId);
    }

    // Directional Navigation:
    // UP: if row == 0 -> go to top bar based on column. Else -> key directly above in same column.
    final VoidCallback onUp = row == 0
        ? () {
            if (col <= 3) {
              _backButtonFocus.requestFocus();
            } else if (col <= 7 && _query.isNotEmpty) {
              _clearButtonFocus.requestFocus();
            } else {
              _micButtonFocus.requestFocus();
            }
          }
        : () {
            final targetKey = _keyboardGrid[row - 1][col];
            _keyFocusNodes[targetKey]?.requestFocus();
          };

    // DOWN: if row == 3 -> stay on key (do NOT let cursor disappear!).
    // Else -> key directly below in same column.
    final VoidCallback onDown = row == _keyboardGrid.length - 1
        ? () {} // Handled: keeps cursor on the bottom row key!
        : () {
            final targetKey = _keyboardGrid[row + 1][col];
            _keyFocusNodes[targetKey]?.requestFocus();
          };

    // LEFT: if col == 0 -> stay on key. Else -> key directly to the left in same row.
    final VoidCallback onLeft = col == 0
        ? () {} // Handled: keeps cursor on leftmost key
        : () {
            final targetKey = _keyboardGrid[row][col - 1];
            _keyFocusNodes[targetKey]?.requestFocus();
          };

    // RIGHT: if col == 9 (last column) -> focus search results! Else -> key to the right.
    final VoidCallback onRight = col == _keyboardGrid[row].length - 1
        ? _focusFirstResult
        : () {
            final targetKey = _keyboardGrid[row][col + 1];
            _keyFocusNodes[targetKey]?.requestFocus();
          };

    return _KeyButton(
      focusNode: node,
      label: label,
      icon: icon,
      onPressed: onPressed,
      onUp: onUp,
      onDown: onDown,
      onLeft: onLeft,
      onRight: onRight,
      onFocusChanged: (focused) {
        if (focused) _lastFocusedKeyboardNode = node;
      },
    );
  }

  Widget _buildResultsSection({bool isFullWidth = false}) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Searching your library...',
              style: TextStyle(color: PlixTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_query.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.search_rounded,
                size: 64,
                color: PlixTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              const Text(
                'Search Movies & TV Shows',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFullWidth
                    ? 'Type in the search box above to search movies, TV shows, and episodes.'
                    : 'Type using the on-screen keyboard or press the microphone to search by voice.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PlixTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 56,
                color: PlixTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found for "$_query"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check the spelling or try searching for another title.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PlixTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(right: isFullWidth ? 0 : 28, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${_results.length} RESULTS',
              style: const TextStyle(
                color: PlixTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (isFullWidth) {
                  final availableWidth = constraints.maxWidth;
                  final crossAxisCount = (availableWidth / 150).floor().clamp(2, 10);
                  const spacing = 16.0;
                  final cellWidth = (availableWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
                  final cellHeight = cellWidth * 1.5 + 72.0;
                  final childAspectRatio = cellWidth / cellHeight;

                  return GridView.builder(
                    padding: const EdgeInsets.only(bottom: 40),
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return Center(
                        child: SizedBox(
                          width: cellWidth,
                          child: MediaCard(
                            key: ValueKey('search_card_${item.ratingKey}'),
                            item: item,
                            mediaService: _mediaService,
                            showResolutionBadge: true,
                            focusNode: _resultFocusNodes[item.ratingKey],
                            width: cellWidth,
                            onTap: () => _openItem(item),
                          ),
                        ),
                      );
                    },
                  );
                }

                // Rows of 3 with standard poster size matching everywhere else in the app (width: 130, aspect ratio: 2/3)
                const crossAxisCount = 3;
                const spacing = 16.0;
                final cellWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
                final cardWidth = cellWidth < 130.0 ? cellWidth : 130.0;
                final cellHeight = cardWidth * 1.5 + 64.0;
                final childAspectRatio = cellWidth / cellHeight;

                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: childAspectRatio,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final isLeftmost = (index % crossAxisCount) == 0;
                    final isTopRow = index < crossAxisCount;

                    return Center(
                      child: SizedBox(
                        width: cardWidth,
                        child: MediaCard(
                          key: ValueKey('search_card_${item.ratingKey}'),
                          item: item,
                          mediaService: _mediaService,
                          showResolutionBadge: true,
                          focusNode: _resultFocusNodes[item.ratingKey],
                          width: cardWidth,
                          onLeft: isLeftmost ? _focusKeyboardReturn : null,
                          onUp: isTopRow ? () => _micButtonFocus.requestFocus() : null,
                          onTap: () => _openItem(item),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final ValueChanged<bool>? onFocusChanged;

  const _KeyButton({
    required this.focusNode,
    required this.label,
    this.icon,
    required this.onPressed,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onFocusChanged,
  });

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      widget.onFocusChanged?.call(widget.focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isFocused ? PlixTheme.plexGold : PlixTheme.surface;
    final fgColor = _isFocused ? Colors.black : PlixTheme.textPrimary;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: widget.icon != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: widget.label.isEmpty ? 20 : 16, color: fgColor),
                      if (widget.label.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: fgColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  )
                : Text(
                    widget.label,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TvIconButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onDown;
  final Color? highlightColor;
  final String tooltip;
  final double size;
  final double iconSize;

  const _TvIconButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
    this.onDown,
    this.highlightColor,
    this.tooltip = '',
    this.size = 44,
    this.iconSize = 20,
  });

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.highlightColor ?? PlixTheme.plexGold;
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovered) {
            setState(() => _isHovered = hovered);
          },
          borderRadius: BorderRadius.circular(widget.size / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: isHighlighted ? activeColor : PlixTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isHighlighted ? activeColor : PlixTheme.cardBorder,
                width: 1.5,
              ),
              boxShadow: isHighlighted
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: isHighlighted ? Colors.black : activeColor,
            ),
          ),
        ),
      ),
    );
  }
}
