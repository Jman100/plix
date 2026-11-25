import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/plex_server.dart';
import '../models/seerr_models.dart';
import '../services/native_player_service.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_server_service.dart';
import '../services/plix_device_helper.dart';
import '../services/seerr_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_bottom_nav.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_tv_text_field.dart';
import '../widgets/seerr_request_dialog.dart';

class RequestsScreen extends StatefulWidget {
  final PlexServer server;
  final List<PlexServer>? servers;
  final String clientId;

  const RequestsScreen({
    super.key,
    required this.server,
    this.servers,
    required this.clientId,
  });

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final NativePlayerService _playerService = NativePlayerService();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();

  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _homeButtonFocus = FocusNode();
  final FocusNode _micButtonFocus = FocusNode();
  final FocusNode _clearButtonFocus = FocusNode();
  final FocusNode _serverDropdownFocus = FocusNode();

  // Servers with Seerr configured
  List<PlexServer> _seerrServers = [];
  Map<String, String> _serverUrls = {};
  late PlexServer _selectedServer;
  String _selectedSeerrUrl = '';

  // Content state
  bool _isLoadingContent = true;
  String _query = '';
  bool _isSearching = false;
  bool _isListening = false;
  List<SeerrMediaItem> _searchResults = [];
  final List<FocusNode> _searchResultFocusNodes = [];

  List<SeerrMediaItem> _recentRequests = [];
  List<SeerrMediaItem> _trending = [];
  List<SeerrMediaItem> _upcomingMovies = [];
  List<SeerrMediaItem> _upcomingTv = [];

  // Focus nodes & scroll memory for rows
  final Map<String, List<FocusNode>> _rowFocusNodes = {
    'recent': [],
    'trending': [],
    'movies': [],
    'tv': [],
  };
  final Map<String, int> _lastFocusedIndexPerRow = {};
  final Map<String, ScrollController> _rowScrollControllers = {};

  @override
  void initState() {
    super.initState();
    _selectedServer = widget.server;
    _initServersAndLoad();

    _textFieldFocusNode.addListener(_handleTextFieldFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && PlixDeviceHelper.isTelevision && !(Platform.isWindows || Platform.isLinux)) {
        _textFieldFocusNode.requestFocus();
      }
    });
  }

  void _handleTextFieldFocusChange() {
    if (!_textFieldFocusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  @override
  void dispose() {
    _textFieldFocusNode.removeListener(_handleTextFieldFocusChange);
    _textController.dispose();
    _textFieldFocusNode.dispose();
    _scrollController.dispose();
    _searchScrollController.dispose();
    _backButtonFocus.dispose();
    _homeButtonFocus.dispose();
    _micButtonFocus.dispose();
    _clearButtonFocus.dispose();
    _serverDropdownFocus.dispose();
    _clearRowFocusNodes();
    for (final ctrl in _rowScrollControllers.values) {
      ctrl.dispose();
    }
    _rowScrollControllers.clear();
    _clearSearchResultFocusNodes();
    super.dispose();
  }

  void _clearSearchResultFocusNodes() {
    for (final node in _searchResultFocusNodes) {
      node.dispose();
    }
    _searchResultFocusNodes.clear();
  }

  void _clearRowFocusNodes() {
    for (final list in _rowFocusNodes.values) {
      for (final n in list) {
        n.dispose();
      }
      list.clear();
    }
    _lastFocusedIndexPerRow.clear();
  }

  Future<void> _initServersAndLoad() async {
    setState(() => _isLoadingContent = true);

    try {
      List<PlexServer> servers = widget.servers ?? [];
      if (servers.isEmpty) {
        final authService = PlexAuthService();
        final serverService = PlexServerService(authService: authService);
        final token = await authService.getSavedToken() ?? '';
        servers = await serverService.fetchServers(token);
      }
      if (servers.isEmpty && widget.server.clientIdentifier.isNotEmpty) {
        servers = [widget.server];
      }

      final seerrMap = <String, String>{};
      final validServers = <PlexServer>[];

      for (final s in servers) {
        final url = await SeerrService().getSeerrUrl(s.clientIdentifier);
        if (url != null && url.isNotEmpty) {
          seerrMap[s.clientIdentifier] = url;
          validServers.add(s);
        }
      }

      if (mounted) {
        setState(() {
          _seerrServers = validServers;
          _serverUrls = seerrMap;

          // Pick active server: either widget.server if valid, or first valid server
          if (validServers.any((s) => s.clientIdentifier == _selectedServer.clientIdentifier)) {
            _selectedSeerrUrl = seerrMap[_selectedServer.clientIdentifier] ?? '';
          } else if (validServers.isNotEmpty) {
            _selectedServer = validServers.first;
            _selectedSeerrUrl = seerrMap[_selectedServer.clientIdentifier] ?? '';
          }
        });

        await _loadAllRows();
      }
    } catch (e) {
      debugPrint('[RequestsScreen] init error: $e');
      if (mounted) setState(() => _isLoadingContent = false);
    }
  }

  Future<void> _loadAllRows() async {
    if (_selectedSeerrUrl.isEmpty) {
      setState(() => _isLoadingContent = false);
      return;
    }

    setState(() => _isLoadingContent = true);

    final sService = SeerrService();
    try {
      final results = await Future.wait([
        sService.getRecentRequests(_selectedServer, _selectedSeerrUrl),
        sService.getTrending(_selectedServer, _selectedSeerrUrl),
        sService.getUpcomingMovies(_selectedServer, _selectedSeerrUrl),
        sService.getUpcomingTv(_selectedServer, _selectedSeerrUrl),
      ]);

      if (mounted) {
        _clearRowFocusNodes();
        setState(() {
          _recentRequests = results[0];
          _trending = results[1];
          _upcomingMovies = results[2];
          _upcomingTv = results[3];
          _isLoadingContent = false;
        });
      }
    } catch (e) {
      debugPrint('[RequestsScreen] load rows error: $e');
      if (mounted) setState(() => _isLoadingContent = false);
    }
  }

  Future<void> _performSearch() async {
    final q = _query.trim();
    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      _clearSearchResultFocusNodes();
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await SeerrService().searchSeerr(_selectedServer, _selectedSeerrUrl, q);
      if (mounted) {
        _clearSearchResultFocusNodes();
        for (var i = 0; i < results.length; i++) {
          _searchResultFocusNodes.add(FocusNode());
        }
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchResults.isNotEmpty) {
            _focusFirstContentItem();
          }
        });
      }
    } catch (e) {
      debugPrint('[RequestsScreen] search error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _startVoiceSearch() async {
    if (_isListening) return;
    setState(() => _isListening = true);

    try {
      final recognized = await _playerService.startVoiceRecognition();
      if (mounted) {
        setState(() => _isListening = false);
        if (recognized.trim().isNotEmpty) {
          _textController.text = recognized.trim();
          _query = recognized.trim();
          _performSearch();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  final Map<String, GlobalKey> _rowGlobalKeys = {
    'recent': GlobalKey(),
    'trending': GlobalKey(),
    'movies': GlobalKey(),
    'tv': GlobalKey(),
  };

  List<String> get _activeRowKeys {
    final keys = <String>[];
    if (_recentRequests.isNotEmpty) keys.add('recent');
    if (_trending.isNotEmpty) keys.add('trending');
    if (_upcomingMovies.isNotEmpty) keys.add('movies');
    if (_upcomingTv.isNotEmpty) keys.add('tv');
    return keys;
  }

  void _scrollToRow(String rowKey) {
    final activeKeys = _activeRowKeys;
    final rowIdx = activeKeys.indexOf(rowKey);
    if (rowIdx == -1) return;

    if (rowIdx == 0) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final gKey = _rowGlobalKeys[rowKey];
    final rowCtx = gKey?.currentContext;
    if (rowCtx != null) {
      Scrollable.ensureVisible(
        rowCtx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToSearchRow(int row, double rowHeight) {
    if (!_searchScrollController.hasClients) return;
    if (row <= 0) {
      _searchScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final targetOffset = row * rowHeight;
    final maxScroll = _searchScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);
    _searchScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _openRequestDialog(SeerrMediaItem item) async {
    final success = await SeerrRequestDialog.show(
      context,
      server: _selectedServer,
      seerrUrl: _selectedSeerrUrl,
      item: item,
      clientId: widget.clientId,
      availableServers: widget.servers,
    );

    if (success == true && mounted) {
      // Refresh recent requests row
      final freshRequests = await SeerrService().getRecentRequests(
        _selectedServer,
        _selectedSeerrUrl,
      );
      if (mounted) {
        setState(() {
          _recentRequests = freshRequests;
        });
      }
    }
  }

  void _ensureHorizontalCardVisible(String rowKey, int index, double cardWidth) {
    final hCtrl = _rowScrollControllers[rowKey];
    if (hCtrl == null || !hCtrl.hasClients) return;
    const spacing = 14.0;
    final step = cardWidth + spacing;
    final itemLeft = index * step;
    final itemRight = itemLeft + cardWidth;
    final viewportWidth = hCtrl.position.viewportDimension;
    final curOffset = hCtrl.offset;

    double? target;
    if (itemLeft < curOffset) {
      target = itemLeft;
    } else if (itemRight > curOffset + viewportWidth) {
      target = itemRight - viewportWidth + 16.0;
    }
    if (target != null) {
      final clamped = target.clamp(0.0, hCtrl.position.maxScrollExtent);
      hCtrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _focusRow(String targetRowKey) {
    final targetNodes = _rowFocusNodes[targetRowKey] ?? [];
    if (targetNodes.isEmpty) return;

    final targetIdx = (_lastFocusedIndexPerRow[targetRowKey] ?? 0).clamp(0, targetNodes.length - 1);
    final targetNode = targetNodes[targetIdx];

    _scrollToRow(targetRowKey);
    if (targetNode.context != null && targetNode.canRequestFocus) {
      targetNode.requestFocus();
    } else {
      final hCtrl = _rowScrollControllers[targetRowKey];
      if (hCtrl != null && hCtrl.hasClients) {
        final cardStep = (PlixDeviceHelper.isCompact(context) ? 115.0 : 150.0) + 14.0;
        final offset = (targetIdx * cardStep).clamp(0.0, hCtrl.position.maxScrollExtent);
        hCtrl.jumpTo(offset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (targetNode.canRequestFocus && targetNode.context != null) {
            targetNode.requestFocus();
          } else if (targetNodes.first.canRequestFocus) {
            targetNodes.first.requestFocus();
          }
        });
      } else if (targetNodes.first.canRequestFocus) {
        targetNodes.first.requestFocus();
      }
    }

    // Ensure the top row heading isn't shifted under the sticky top bar by Flutter's showOnScreen
    if (_activeRowKeys.isNotEmpty && targetRowKey == _activeRowKeys.first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && _scrollController.offset > 0.0) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  void _focusFirstContentItem() {
    if (_query.trim().isNotEmpty) {
      if (_searchResultFocusNodes.isNotEmpty && _searchResultFocusNodes.first.canRequestFocus) {
        _scrollToSearchRow(0, 310.0);
        _searchResultFocusNodes.first.requestFocus();
      }
    } else {
      final active = _activeRowKeys;
      if (active.isNotEmpty) {
        _focusRow(active.first);
      }
    }
  }

  void _showServerPickerModal() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 440,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF14151C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: PlixTheme.cardBorder,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_rounded, color: PlixTheme.plexGold, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Select Request Server',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: PlixTheme.cardBorder, height: 1),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _seerrServers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, idx) {
                      final server = _seerrServers[idx];
                      final isSelected = server.clientIdentifier == _selectedServer.clientIdentifier;
                      return _ServerPickerTile(
                        server: server,
                        isSelected: isSelected,
                        autofocus: isSelected,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (!isSelected) {
                            setState(() {
                              _selectedServer = server;
                              _selectedSeerrUrl = _serverUrls[server.clientIdentifier] ?? '';
                            });
                            if (_query.trim().isNotEmpty) {
                              _performSearch();
                            } else {
                              _loadAllRows();
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleBack() {
    if (_query.trim().isNotEmpty || _searchResults.isNotEmpty) {
      _textController.clear();
      if (_searchScrollController.hasClients) {
        _searchScrollController.jumpTo(0.0);
      }
      setState(() {
        _query = '';
        _searchResults = [];
        _isSearching = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && PlixDeviceHelper.isTelevision && !(Platform.isWindows || Platform.isLinux)) {
          _textFieldFocusNode.requestFocus();
        }
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlixDeviceHelper.isTelevision && !(Platform.isWindows || Platform.isLinux);
    final isCompact = PlixDeviceHelper.isCompact(context);

    return PopScope(
      canPop: _query.trim().isEmpty && _searchResults.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        bottomNavigationBar: (isCompact && !isTv)
            ? PlixBottomNav(
                currentIndex: -1,
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
                _handleBack();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                // Content underneath sticky top bar
                Positioned.fill(
                  top: 84,
                  child: _query.trim().isNotEmpty
                      ? _buildSearchResultsView(isCompact)
                      : _buildDiscoveryRowsView(isCompact),
                ),

                // Sticky Top Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: PlixTheme.background,
                    child: _buildTopBar(isTv: isTv, isCompact: isCompact),
                  ),
                ),
              ],
            ),
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
              onPressed: _handleBack,
              onRight: () => _homeButtonFocus.requestFocus(),
              onDown: _focusFirstContentItem,
            ),
            const SizedBox(width: 10),
            PlixHomeButton(
              focusNode: _homeButtonFocus,
              onLeft: () => _backButtonFocus.requestFocus(),
              onRight: () => _textFieldFocusNode.requestFocus(),
              onDown: _focusFirstContentItem,
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
                    border: isFocused
                        ? (PlixTheme.isRainbowBorder
                            ? PlixTheme.rainbowOutlineBorder(width: 2.0)
                            : Border.all(color: PlixTheme.plexGold, width: 2.0))
                        : Border.all(color: PlixTheme.cardBorder, width: 1.5),
                    boxShadow: (isFocused && !PlixTheme.isRainbowBorder)
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
                          hintText: 'Search movies & series to request...',
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
                            if (val.isEmpty) {
                              setState(() {
                                _searchResults = [];
                                _isSearching = false;
                              });
                            }
                          },
                          onSubmitted: (val) {
                            _query = val;
                            _textFieldFocusNode.unfocus();
                            _performSearch();
                          },
                          onDown: _focusFirstContentItem,
                          onLeft: () => _homeButtonFocus.requestFocus(),
                          onRight: () {
                            if (_query.isNotEmpty) {
                              _clearButtonFocus.requestFocus();
                            } else if (_seerrServers.length > 1) {
                              _serverDropdownFocus.requestFocus();
                            }
                          },
                        ),
                      ),

                      // Clear query button
                      if (_query.isNotEmpty)
                        IconButton(
                          focusNode: _clearButtonFocus,
                          icon: const Icon(Icons.clear_rounded, color: PlixTheme.textSecondary, size: 20),
                          onPressed: () {
                            _textController.clear();
                            setState(() {
                              _query = '';
                              _searchResults = [];
                              _isSearching = false;
                            });
                            _textFieldFocusNode.requestFocus();
                          },
                        ),

                      // Voice search mic
                      if (!(Platform.isWindows || Platform.isLinux))
                        IconButton(
                          focusNode: _micButtonFocus,
                          icon: Icon(
                            _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: _isListening ? Colors.redAccent : PlixTheme.textSecondary,
                            size: 22,
                          ),
                          onPressed: _startVoiceSearch,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Server selector dropdown if user has >1 Seerr connection
          if (_seerrServers.length > 1) ...[
            const SizedBox(width: 12),
            Focus(
              focusNode: _serverDropdownFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _focusFirstContentItem();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    if (_query.isNotEmpty) {
                      _clearButtonFocus.requestFocus();
                    } else {
                      _textFieldFocusNode.requestFocus();
                    }
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    _showServerPickerModal();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: AnimatedBuilder(
                animation: _serverDropdownFocus,
                builder: (context, _) {
                  final isFocused = _serverDropdownFocus.hasFocus;
                  return InkWell(
                    onTap: _showServerPickerModal,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: PlixTheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: isFocused
                            ? (PlixTheme.isRainbowBorder
                                ? PlixTheme.rainbowOutlineBorder(width: 2.0)
                                : Border.all(color: PlixTheme.plexGold, width: 2.0))
                            : Border.all(color: PlixTheme.cardBorder, width: 1.2),
                        boxShadow: (isFocused && !PlixTheme.isRainbowBorder)
                            ? [
                                BoxShadow(
                                  color: PlixTheme.plexGold.withOpacity(0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedServer.isJellyfin ? Icons.cloud_outlined : Icons.live_tv_rounded,
                            size: 16,
                            color: PlixTheme.plexGold,
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(
                              _selectedServer.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: PlixTheme.textSecondary, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResultsView(bool isCompact) {
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(color: PlixTheme.plexGold),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 56, color: PlixTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              'No results found for "$_query"',
              style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Text(
              '${_searchResults.length} RESULTS',
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
                const spacing = 12.0;
                final totalWidth = constraints.maxWidth;
                final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || totalWidth >= 650;
                final int columns = isLandscape ? 6 : 3;
                final cardWidth = (totalWidth - (columns - 1) * spacing) / columns;
                final cardMainAxisExtent = (cardWidth * 1.5) + 42.0;
                final rowHeight = cardMainAxisExtent + 16.0;

                while (_searchResultFocusNodes.length < _searchResults.length) {
                  _searchResultFocusNodes.add(FocusNode());
                }

                return GridView.builder(
                  controller: _searchScrollController,
                  cacheExtent: 1500,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 32),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: cardMainAxisExtent,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final fNode = _searchResultFocusNodes[index];
                    final int row = index ~/ columns;

                    VoidCallback onUp;
                    if (row == 0) {
                      onUp = () {
                        _scrollToSearchRow(0, rowHeight);
                        _textFieldFocusNode.requestFocus();
                      };
                    } else {
                      onUp = () {
                        _scrollToSearchRow(row - 1, rowHeight);
                        final targetIndex = index - columns;
                        if (targetIndex >= 0 && targetIndex < _searchResultFocusNodes.length) {
                          _searchResultFocusNodes[targetIndex].requestFocus();
                        }
                      };
                    }

                    VoidCallback onDown;
                    if (index + columns < _searchResults.length) {
                      onDown = () {
                        _scrollToSearchRow(row + 1, rowHeight);
                        final targetIndex = index + columns;
                        if (targetIndex < _searchResultFocusNodes.length) {
                          _searchResultFocusNodes[targetIndex].requestFocus();
                        }
                      };
                    } else if (index < _searchResults.length - 1) {
                      onDown = () {
                        final targetRow = (_searchResults.length - 1) ~/ columns;
                        _scrollToSearchRow(targetRow, rowHeight);
                        _searchResultFocusNodes[_searchResults.length - 1].requestFocus();
                      };
                    } else {
                      onDown = () {}; // Block down past last row
                    }

                    final blockLeft = (index % columns == 0);
                    final blockRight = ((index + 1) % columns == 0 || index == _searchResults.length - 1);

                    return _SeerrPosterCard(
                      item: item,
                      focusNode: fNode,
                      onUp: onUp,
                      onDown: onDown,
                      blockLeft: blockLeft,
                      blockRight: blockRight,
                      onTap: () => _openRequestDialog(item),
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

  Widget _buildDiscoveryRowsView(bool isCompact) {
    if (_isLoadingContent) {
      return Center(
        child: CircularProgressIndicator(color: PlixTheme.plexGold),
      );
    }

    if (_selectedSeerrUrl.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off_rounded, size: 64, color: PlixTheme.textMuted),
            SizedBox(height: 16),
            Text(
              'No Seerr URL Configured',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Please configure a Seerr URL in Settings to use Requests.',
              style: TextStyle(color: PlixTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 32,
        16,
        isCompact ? 16 : 32,
        12,
      ),
      children: [
        // 1. Recent Requests (if any)
        if (_recentRequests.isNotEmpty) ...[
          _buildRowSection(
            title: 'Your Recent Requests',
            items: _recentRequests,
            rowKey: 'recent',
            isCompact: isCompact,
          ),
          const SizedBox(height: 28),
        ],

        // 2. Trending
        if (_trending.isNotEmpty) ...[
          _buildRowSection(
            title: 'Trending',
            items: _trending,
            rowKey: 'trending',
            isCompact: isCompact,
          ),
          const SizedBox(height: 28),
        ],

        // 3. Upcoming Movies
        if (_upcomingMovies.isNotEmpty) ...[
          _buildRowSection(
            title: 'Upcoming Movies',
            items: _upcomingMovies,
            rowKey: 'movies',
            isCompact: isCompact,
          ),
          const SizedBox(height: 28),
        ],

        // 4. Upcoming TV Series
        if (_upcomingTv.isNotEmpty) ...[
          _buildRowSection(
            title: 'Upcoming TV Series',
            items: _upcomingTv,
            rowKey: 'tv',
            isCompact: isCompact,
          ),
          const SizedBox(height: 36),
        ],
      ],
    );
  }

  Widget _buildRowSection({
    required String title,
    required List<SeerrMediaItem> items,
    required String rowKey,
    required bool isCompact,
  }) {
    final listNodes = _rowFocusNodes.putIfAbsent(rowKey, () => []);
    while (listNodes.length < items.length) {
      listNodes.add(FocusNode());
    }

    final cardWidth = isCompact ? 115.0 : 150.0;
    final cardHeight = isCompact ? 210.0 : 270.0;

    final activeKeys = _activeRowKeys;
    final rIdx = activeKeys.indexOf(rowKey);

    return KeyedSubtree(
      key: _rowGlobalKeys.putIfAbsent(rowKey, () => GlobalKey()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              controller: _rowScrollControllers.putIfAbsent(rowKey, () => ScrollController()),
              cacheExtent: 1500,
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                final node = listNodes[index];

                VoidCallback onUpAction;
                if (rIdx <= 0) {
                  onUpAction = () {
                    _textFieldFocusNode.requestFocus();
                    _scrollToRow(activeKeys.isNotEmpty ? activeKeys[0] : rowKey);
                  };
                } else {
                  onUpAction = () {
                    final prevRowKey = activeKeys[rIdx - 1];
                    _focusRow(prevRowKey);
                  };
                }

                VoidCallback onDownAction;
                if (rIdx >= 0 && rIdx < activeKeys.length - 1) {
                  onDownAction = () {
                    final nextRowKey = activeKeys[rIdx + 1];
                    _focusRow(nextRowKey);
                  };
                } else {
                  onDownAction = () {}; // Block moving down past the last row
                }

                return SizedBox(
                  width: cardWidth,
                  child: _SeerrPosterCard(
                    item: item,
                    focusNode: node,
                    onUp: onUpAction,
                    onDown: onDownAction,
                    scrollOnFocus: false,
                    onFocused: () {
                      _lastFocusedIndexPerRow[rowKey] = index;
                      _ensureHorizontalCardVisible(rowKey, index, cardWidth);
                    },
                    blockLeft: index == 0,
                    blockRight: index == items.length - 1,
                    onTap: () => _openRequestDialog(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SeerrPosterCard extends StatefulWidget {
  final SeerrMediaItem item;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onFocused;
  final bool scrollOnFocus;
  final bool blockLeft;
  final bool blockRight;

  const _SeerrPosterCard({
    required this.item,
    required this.focusNode,
    required this.onTap,
    this.onUp,
    this.onDown,
    this.onFocused,
    this.scrollOnFocus = true,
    this.blockLeft = false,
    this.blockRight = false,
  });

  @override
  State<_SeerrPosterCard> createState() => _SeerrPosterCardState();
}

class _SeerrPosterCardState extends State<_SeerrPosterCard> {
  bool _isHovered = false;

  Widget _buildNoPosterPlaceholder() {
    return Container(
      color: const Color(0xFF1B1D28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.item.isTv ? Icons.tv_off_rounded : Icons.movie_filter_rounded,
              size: 30,
              color: PlixTheme.textMuted.withOpacity(0.45),
            ),
            const SizedBox(height: 6),
            const Text(
              'No poster\navailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PlixTheme.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused && context.mounted) {
          widget.onFocused?.call();
          if (widget.scrollOnFocus) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.15,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
            );
          }
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.blockLeft) {
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.blockRight) {
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
               event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: widget.focusNode,
        builder: (context, _) {
          final isFocused = widget.focusNode.hasFocus;
          final isHighlighted = isFocused || _isHovered;

          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster with border & badge (smooth corners, no clip cutoff)
                  Expanded(
                    child: AnimatedContainer(
                      duration: PlixDeviceHelper.isTelevision ? Duration.zero : const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: PlixTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: isHighlighted
                            ? (PlixTheme.isRainbowBorder
                                ? PlixTheme.rainbowOutlineBorder(width: 3.0)
                                : Border.all(color: PlixTheme.plexGold, width: 3.0))
                            : Border.all(color: PlixTheme.cardBorder, width: 1.0),
                        boxShadow: (isHighlighted && !PlixTheme.isRainbowBorder)
                            ? [
                                BoxShadow(
                                  color: PlixTheme.plexGold.withOpacity(0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (widget.item.posterUrl.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: widget.item.posterUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _buildNoPosterPlaceholder(),
                              )
                            else
                              _buildNoPosterPlaceholder(),

                          // Media status badge (Available / Requested)
                          if (widget.item.hasRequestOrAvailable)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.item.isAnyAvailable
                                      ? Colors.green.shade800.withOpacity(0.9)
                                      : Colors.amber.shade900.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.item.isAnyAvailable ? 'Available' : 'Requested',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // Media type indicator
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                widget.item.isTv ? 'TV' : 'MOVIE',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                  // Title
                  Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isHighlighted
                          ? (PlixTheme.isRainbowBorder ? Colors.white : PlixTheme.plexGold)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  // Year
                  if (widget.item.year.isNotEmpty)
                    Text(
                      widget.item.year,
                      style: const TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ServerPickerTile extends StatefulWidget {
  final PlexServer server;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _ServerPickerTile({
    required this.server,
    required this.isSelected,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_ServerPickerTile> createState() => _ServerPickerTileState();
}

class _ServerPickerTileState extends State<_ServerPickerTile> {
  late final FocusNode _focusNode;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _focusNode,
        builder: (context, _) {
          final isFocused = _focusNode.hasFocus;
          final isHighlighted = isFocused || _isHovered;

          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? PlixTheme.surfaceLight.withOpacity(0.3)
                      : (widget.isSelected ? PlixTheme.surface : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                  border: isHighlighted
                      ? (PlixTheme.isRainbowBorder
                          ? PlixTheme.rainbowOutlineBorder(width: 2.0)
                          : Border.all(color: PlixTheme.plexGold, width: 2.0))
                      : Border.all(
                          color: widget.isSelected ? PlixTheme.plexGold.withOpacity(0.4) : PlixTheme.cardBorder,
                          width: 1.0,
                        ),
                  boxShadow: (isHighlighted && !PlixTheme.isRainbowBorder)
                      ? [
                          BoxShadow(
                            color: PlixTheme.plexGold.withOpacity(0.25),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.server.isJellyfin ? Icons.cloud_outlined : Icons.live_tv_rounded,
                      color: isHighlighted || widget.isSelected ? PlixTheme.plexGold : PlixTheme.textMuted,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.server.name,
                            style: TextStyle(
                              color: isHighlighted || widget.isSelected ? Colors.white : PlixTheme.textPrimary,
                              fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.server.isJellyfin ? 'Jellyfin Seerr' : 'Plex Seerr',
                            style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isSelected)
                      Icon(Icons.check_circle_rounded, color: PlixTheme.plexGold, size: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
