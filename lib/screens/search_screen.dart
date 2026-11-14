import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/native_player_service.dart';
import '../services/plex_media_service.dart';
import '../services/plix_device_helper.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_tv_text_field.dart';
import 'details_screen.dart';
import '../widgets/plix_bottom_nav.dart';

class SearchScreen extends StatefulWidget {
  final PlexServer server;
  final List<PlexServer>? servers;
  final String clientId;
  final bool? isMultiServer;

  const SearchScreen({
    super.key,
    required this.server,
    this.servers,
    required this.clientId,
    this.isMultiServer,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _searchScore(PlexMediaItem item, String query) {
    final normQ = query.trim().toLowerCase();
    final strippedQ = PlexMediaItem.normalizeSortTitle(normQ).toLowerCase();
    final title = item.title.trim().toLowerCase();
    final sortTitle = item.sortTitle.trim().toLowerCase();
    final series = (item.grandparentTitle ?? '').trim().toLowerCase();
    final seriesSort = PlexMediaItem.normalizeSortTitle(series).toLowerCase();

    // Exact matches (ignoring or including "the")
    if (sortTitle == strippedQ || title == normQ || title == strippedQ || sortTitle == normQ) {
      return (item.isMovie || item.isShow) ? 0 : 1;
    }
    // Starts with query
    if (sortTitle.startsWith(strippedQ) || title.startsWith(normQ) || title.startsWith(strippedQ)) {
      return (item.isMovie || item.isShow) ? 2 : 3;
    }
    // Series title exact match (for episodes/seasons)
    if (seriesSort == strippedQ || series == normQ || series == strippedQ) {
      return 4;
    }
    // Series title starts with query
    if (seriesSort.startsWith(strippedQ) || series.startsWith(normQ) || series.startsWith(strippedQ)) {
      return 5;
    }
    // Contains query
    if (sortTitle.contains(strippedQ) || title.contains(normQ) || title.contains(strippedQ)) {
      return (item.isMovie || item.isShow) ? 6 : 7;
    }
    if (seriesSort.contains(strippedQ) || series.contains(normQ) || series.contains(strippedQ)) {
      return 8;
    }
    return 10;
  }

  late PlexMediaService _mediaService;
  final NativePlayerService _playerService = NativePlayerService();

  String _query = '';
  List<PlexMediaItem> _results = [];
  bool _isSearching = false;
  bool _isListening = false;
  bool _isEditingKeyboard = false;
  int _searchGeneration = 0;
  bool _hasMultiServerFavorites = false;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Header focus nodes
  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _homeButtonFocus = FocusNode();
  final FocusNode _micButtonFocus = FocusNode();
  final FocusNode _clearButtonFocus = FocusNode();

  final List<FocusNode> _resultFocusNodes = [];

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);

    if (widget.isMultiServer != null) {
      _hasMultiServerFavorites = widget.isMultiServer!;
    }
    _checkMultiServer();

    _textFieldFocusNode.addListener(_handleTextFieldFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFieldFocusNode.requestFocus();
      }
    });
  }

  void _handleTextFieldFocusChange() {
    if (!_textFieldFocusNode.hasFocus && _isEditingKeyboard) {
      setState(() {
        _isEditingKeyboard = false;
      });
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  Future<void> _checkMultiServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favs = prefs.getStringList('plix_favorite_library_composite_ids');
      if (favs != null && favs.isNotEmpty) {
        final serverIds = favs
            .map((f) => f.contains(':') ? f.split(':').first : (f.contains('_') ? f.split('_').first : f))
            .where((s) => s.isNotEmpty)
            .toSet();
        if (mounted) {
          setState(() {
            _hasMultiServerFavorites = serverIds.length > 1;
          });
        }
        return;
      }
    } catch (_) {}
    if (widget.servers != null && widget.servers!.length > 1) {
      if (mounted) {
        setState(() {
          _hasMultiServerFavorites = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _textFieldFocusNode.removeListener(_handleTextFieldFocusChange);
    _textController.dispose();
    _textFieldFocusNode.dispose();
    _scrollController.dispose();
    _backButtonFocus.dispose();
    _homeButtonFocus.dispose();
    _micButtonFocus.dispose();
    _clearButtonFocus.dispose();
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    _resultFocusNodes.clear();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_query.trim().isEmpty) {
      for (final node in _resultFocusNodes) {
        node.dispose();
      }
      _resultFocusNodes.clear();
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  Future<void> _performSearch() async {
    final queryText = _query.trim();
    if (queryText.isEmpty) {
      if (mounted) setState(() => _isSearching = false);
      return;
    }

    final generation = ++_searchGeneration;

    try {
      final targetServers = (widget.servers != null && widget.servers!.isNotEmpty)
          ? widget.servers!
          : [widget.server];

      for (final s in targetServers) {
        if (s.activeConnectionUri == null || s.activeConnectionUri!.isEmpty) {
          if (s.connections.isNotEmpty) {
            s.activeConnectionUri = s.connections.first.uri;
          }
        }
      }

      final resultsLists = await Future.wait(
        targetServers.map((srv) async {
          try {
            final items = await PlexMediaService(server: srv).search(queryText);
            return items.map((item) {
              if (item.server == null || item.serverId == null) {
                return item.copyWith(
                  server: item.server ?? srv,
                  serverId: item.serverId ?? srv.clientIdentifier,
                );
              }
              return item;
            }).toList();
          } catch (_) {
            return <PlexMediaItem>[];
          }
        }),
      );

      final items = <PlexMediaItem>[];
      final seen = <String>{};
      for (final list in resultsLists) {
        for (final item in list) {
          final key = '${item.serverId ?? item.server?.clientIdentifier ?? ''}_${item.ratingKey}';
          if (seen.add(key)) {
            items.add(item);
          }
        }
      }

      items.sort((a, b) {
        final scoreA = _searchScore(a, queryText);
        final scoreB = _searchScore(b, queryText);
        if (scoreA != scoreB) return scoreA.compareTo(scoreB);
        return a.sortTitle.toLowerCase().compareTo(b.sortTitle.toLowerCase());
      });

      if (mounted && generation == _searchGeneration) {
        for (final node in _resultFocusNodes) {
          node.dispose();
        }
        _resultFocusNodes.clear();
        for (int i = 0; i < items.length; i++) {
          _resultFocusNodes.add(FocusNode());
        }

        setState(() {
          _results = items;
          _isSearching = false;
        });

        // Automatically focus the first result when search finishes
        if (items.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _results.isNotEmpty) {
              if (_isEditingKeyboard) {
                setState(() => _isEditingKeyboard = false);
                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }
              _focusFirstResult();
            }
          });
        }
      }
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        for (final node in _resultFocusNodes) {
          node.dispose();
        }
        _resultFocusNodes.clear();
        setState(() {
          _results = [];
          _isSearching = false;
        });
      }
    }
  }

  void _handleClear() {
    _textController.clear();
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    _resultFocusNodes.clear();
    setState(() {
      _query = '';
      _results = [];
      _isSearching = false;
      _isEditingKeyboard = false;
    });
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (mounted) {
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
            _textController.text = _query;
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

  void _scrollToRow(int row) {
    if (!_scrollController.hasClients) return;
    if (row <= 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // Each row is approximately 293px tall + 16px spacing = ~309px per row.
    final targetOffset = row * 310.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _focusFirstResult() {
    if (_results.isNotEmpty && _resultFocusNodes.isNotEmpty) {
      _scrollToRow(0);
      _resultFocusNodes[0].requestFocus();
    }
  }

  void _openItem(PlexMediaItem item) {
    final effectiveServer = item.server ?? widget.server;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: item,
          server: effectiveServer,
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
              // 1. Full Screen Search Results (scrolled items slide UNDER the sticky top bar)
              Positioned.fill(
                top: _results.isNotEmpty ? 102 : 72,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32),
                  child: _buildResultsSection(isCompact: isCompact),
                ),
              ),

              // 2. Sticky Top Bar (pinned to top with solid background, on top of scrolling results)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: PlixTheme.background,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(isTv: isTv, isCompact: isCompact),
                      if (_results.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            left: isCompact ? 16 : 48,
                            right: isCompact ? 16 : 48,
                            bottom: 8,
                          ),
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

  Widget _buildTopBar({required bool isTv, required bool isCompact}) {
    return Container(
      color: PlixTheme.background,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 12),
      child: Row(
        children: [
          if (!Platform.isAndroid || PlixDeviceHelper.isTelevision || MediaQuery.of(context).orientation == Orientation.landscape) ...[
            PlixBackButton(
              focusNode: _backButtonFocus,
              onRight: () => _homeButtonFocus.requestFocus(),
              onDown: _results.isNotEmpty ? _focusFirstResult : () => _textFieldFocusNode.requestFocus(),
            ),
            const SizedBox(width: 10),
            PlixHomeButton(
              focusNode: _homeButtonFocus,
              onLeft: () => _backButtonFocus.requestFocus(),
              onRight: () => _textFieldFocusNode.requestFocus(),
              onDown: _results.isNotEmpty ? _focusFirstResult : () => _textFieldFocusNode.requestFocus(),
            ),
            SizedBox(width: isCompact ? 12 : 20),
          ],

          // Search Input Bar
          Expanded(
            child: AnimatedBuilder(
              animation: _textFieldFocusNode,
              builder: (context, _) {
                final isFocused = _textFieldFocusNode.hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 48,
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  decoration: BoxDecoration(
                    color: PlixTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: isFocused ? 2.0 : 1.5,
                    ),
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: PlixTheme.plexGold.withOpacity(0.35),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: isFocused ? PlixTheme.plexGold : PlixTheme.textMuted,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PlixTvTextField(
                          controller: _textController,
                          focusNode: _textFieldFocusNode,
                          hintText: 'Search movies, TV shows, episodes...',
                          style: const TextStyle(
                            color: PlixTheme.textPrimary,
                            fontSize: 16,
                          ),
                          hintStyle: const TextStyle(
                            color: PlixTheme.textMuted,
                            fontSize: 16,
                          ),
                          imeAction: 'search',
                          onChanged: (val) {
                            _query = val;
                            _onQueryChanged();
                          },
                          onSubmitted: (val) {
                            _query = val;
                            _textFieldFocusNode.unfocus();
                            if (_query.trim().isNotEmpty) {
                              setState(() => _isSearching = true);
                              _performSearch();
                            } else {
                              for (final node in _resultFocusNodes) {
                                node.dispose();
                              }
                              _resultFocusNodes.clear();
                              setState(() {
                                _results = [];
                                _isSearching = false;
                              });
                            }
                          },
                          onLeft: () => _homeButtonFocus.requestFocus(),
                          onRight: () {
                            if (_query.isNotEmpty) {
                              _clearButtonFocus.requestFocus();
                            } else if (!(Platform.isWindows || Platform.isLinux)) {
                              _micButtonFocus.requestFocus();
                            }
                          },
                          onDown: () {
                            if (_results.isNotEmpty) {
                              _focusFirstResult();
                            }
                          },
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
                          onLeft: () => _textFieldFocusNode.requestFocus(),
                          onRight: !(Platform.isWindows || Platform.isLinux)
                              ? () => _micButtonFocus.requestFocus()
                              : null,
                          onDown: _results.isNotEmpty ? _focusFirstResult : null,
                        ),
                      ],
                    ],
                  ),
                );
              },
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
              onLeft: () => _query.isNotEmpty ? _clearButtonFocus.requestFocus() : _textFieldFocusNode.requestFocus(),
              onDown: _results.isNotEmpty ? _focusFirstResult : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsSection({required bool isCompact}) {
    if (_isSearching) {
      return Align(
        alignment: const Alignment(0, -0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      return Align(
        alignment: const Alignment(0, -0.45),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.search_rounded,
                size: 56,
                color: PlixTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 14),
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
              const Text(
                'Type in the search box above to search movies, TV shows, and episodes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PlixTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Align(
        alignment: const Alignment(0, -0.45),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 56,
                color: PlixTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 14),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = isCompact
            ? (constraints.maxWidth / 115).floor().clamp(3, 7)
            : (constraints.maxWidth / 140).floor().clamp(4, 12);

        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: isCompact ? 10 : 14,
          mainAxisSpacing: isCompact ? 12 : 16,
          childAspectRatio: 0.47,
        );

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 60),
          clipBehavior: Clip.none,
          cacheExtent: 1500,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          gridDelegate: gridDelegate,
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final item = _results[index];
            final focusNode = (index < _resultFocusNodes.length)
                ? _resultFocusNodes[index]
                : FocusNode();
            final serverName = item.server?.name ?? (item.server?.isJellyfin == true ? 'Jellyfin' : 'Plex');

            final int row = index ~/ crossAxisCount;
            final int col = index % crossAxisCount;

            return LayoutBuilder(
              builder: (context, cardConstraints) {
                return MediaCard(
                  key: ValueKey('search_card_${item.ratingKey}_$index'),
                  item: item,
                  mediaService: (item.server != null && item.server != _mediaService.server)
                      ? PlexMediaService(server: item.server!)
                      : _mediaService,
                  topServerName: _hasMultiServerFavorites ? serverName : null,
                  showResolutionBadge: true,
                  focusNode: focusNode,
                  width: cardConstraints.maxWidth,
                  margin: EdgeInsets.zero,
                  onFocusWithNode: (node, focused) {
                    if (focused && node.context != null) {
                      Scrollable.ensureVisible(
                        node.context!,
                        alignment: 0.15,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  onUp: () {
                    if (row == 0) {
                      _scrollToRow(0);
                      _textFieldFocusNode.requestFocus();
                    } else if (row == 1) {
                      _scrollToRow(0);
                      final targetIndex = index - crossAxisCount;
                      if (targetIndex >= 0 && targetIndex < _resultFocusNodes.length) {
                        _resultFocusNodes[targetIndex].requestFocus();
                      }
                    } else {
                      _scrollToRow(row - 1);
                      final targetIndex = index - crossAxisCount;
                      if (targetIndex >= 0 && targetIndex < _resultFocusNodes.length) {
                        _resultFocusNodes[targetIndex].requestFocus();
                      }
                    }
                  },
                  onDown: () {
                    final targetIndex = index + crossAxisCount;
                    if (targetIndex < _results.length) {
                      _scrollToRow(row + 1);
                      if (targetIndex < _resultFocusNodes.length) {
                        _resultFocusNodes[targetIndex].requestFocus();
                      }
                    } else if (index < _results.length - 1) {
                      final targetRow = (_results.length - 1) ~/ crossAxisCount;
                      _scrollToRow(targetRow);
                      _resultFocusNodes[_results.length - 1].requestFocus();
                    }
                  },
                  onLeft: col > 0
                      ? () {
                          final targetIndex = index - 1;
                          if (targetIndex >= 0 && targetIndex < _resultFocusNodes.length) {
                            _resultFocusNodes[targetIndex].requestFocus();
                          }
                        }
                      : null,
                  onRight: (col < crossAxisCount - 1 && index + 1 < _results.length)
                      ? () {
                          final targetIndex = index + 1;
                          if (targetIndex < _resultFocusNodes.length) {
                            _resultFocusNodes[targetIndex].requestFocus();
                          }
                        }
                      : null,
                  onTap: () => _openItem(item),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TvIconButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDown;
  final Color? highlightColor;
  final String tooltip;
  final double size;
  final double iconSize;

  const _TvIconButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
    this.onLeft,
    this.onRight,
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
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
               event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.space ||
               event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
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
