import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_server_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_button.dart';
import '../widgets/sidebar_nav.dart';
import 'auth_chooser_screen.dart';
import 'details_screen.dart';
import 'library_screen.dart';
import '../services/native_player_service.dart';
import 'player_screen.dart';
import 'recently_added_screen.dart';
import 'search_screen.dart';
import 'server_select_screen.dart';
import 'settings_screen.dart';
import 'watchlist_screen.dart';
import '../services/plix_device_helper.dart';
import '../services/plix_image_cache.dart';
import '../services/update_service.dart';

import '../services/theme_music_service.dart';
import '../widgets/brand_logo.dart';
import '../widgets/plix_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  final PlexServer server;
  final PlexAuthService authService;
  final PlexServerService serverService;

  const HomeScreen({
    super.key,
    required this.server,
    required this.authService,
    required this.serverService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late PlexMediaService _mediaService;
  String _clientId = '';

  List<PlexLibrary> _libraries = [];
  List<PlexMediaItem> _continueWatching = [];
  final Map<String, List<PlexMediaItem>> _recentlyAddedByLibrary = {};

  PlexMediaItem? _heroItem;
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _heroPlayFocusNode = FocusNode();
  final FocusNode _heroDetailsFocusNode = FocusNode();
  final FocusNode _sidebarHomeFocusNode = FocusNode();
  final FocusNode _firstContinueWatchingFocusNode = FocusNode();
  final Map<String, FocusNode> _viewMoreFocusNodes = {};
  final Map<String, GlobalKey<_HomeRowSectionState>> _rowSectionKeys = {};
  final Map<String, int> _rowLastFocusedIndices = {};
  FocusNode? _lastFocusedContentNode;
  String? _lastFocusedRowId;

  String? _heroViewMoreTitle;

  bool get _showHeroButtons {
    if (_heroViewMoreTitle != null) return false;
    if (_heroPlayFocusNode.hasFocus || _heroDetailsFocusNode.hasFocus) return true;
    if (_lastFocusedRowId == 'continue_watching') return true;
    if (_lastFocusedRowId == null && _continueWatching.isNotEmpty) return true;
    return false;
  }
  bool _isSidebarFocused = false;
  Timer? _heroMetadataDebounceTimer;
  Timer? _heroHoverTimer;
  Timer? _mobileHeroTimer;
  int _mobileHeroIndex = 0;

  void _startMobileHeroTimer() {
    _mobileHeroTimer?.cancel();
    if (!mounted) return;
    if (_continueWatching.isEmpty) return;
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;
    if (!isCompact || isTv) return;

    _mobileHeroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_continueWatching.isEmpty) return;

      setState(() {
        _mobileHeroIndex = (_mobileHeroIndex + 1) % _continueWatching.length;
        _heroItem = _continueWatching[_mobileHeroIndex];
      });
    });
  }

  void _onMediaTileHover(PlexMediaItem item, bool isHovered) {
    if (!Platform.isWindows) return;
    _heroHoverTimer?.cancel();
    _mobileHeroTimer?.cancel();
    if (isHovered) {
      _heroHoverTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _heroItem = item;
          });
          if (item.ratingKey.isNotEmpty) {
            _fetchHeroFullMetadata(item);
          }
        }
      });
    }
  }

  void _fetchHeroFullMetadata(PlexMediaItem currentHeroItem) {
    _heroMetadataDebounceTimer?.cancel();
    final isSeasonTarget = currentHeroItem.targetType == 'season';
    final fetchKey = isSeasonTarget ? currentHeroItem.ratingKey : (currentHeroItem.targetRatingKey ?? currentHeroItem.ratingKey);
    if (fetchKey.isEmpty) return;

    final cached = _mediaService.getDetailedCachedMetadata(fetchKey);
    if (cached != null) {
      if (isSeasonTarget) {
        _heroItem = cached.copyWith(
          title: currentHeroItem.title,
          grandparentTitle: currentHeroItem.grandparentTitle,
          addedSubtitle: currentHeroItem.addedSubtitle,
          targetType: 'season',
          targetSeasonKey: currentHeroItem.targetSeasonKey,
          targetRatingKey: currentHeroItem.targetRatingKey,
          clearDuration: true,
        );
      } else {
        _heroItem = cached;
      }
    }

    _heroMetadataDebounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final full = await _mediaService.getItemMetadata(fetchKey);
        if (mounted && (_heroItem?.ratingKey == currentHeroItem.ratingKey || _heroItem?.targetRatingKey == currentHeroItem.targetRatingKey)) {
          setState(() {
            if (isSeasonTarget) {
              _heroItem = full.copyWith(
                title: currentHeroItem.title,
                grandparentTitle: currentHeroItem.grandparentTitle,
                addedSubtitle: currentHeroItem.addedSubtitle,
                targetType: 'season',
                targetSeasonKey: currentHeroItem.targetSeasonKey,
                targetRatingKey: currentHeroItem.targetRatingKey,
                clearDuration: true,
              );
            } else {
              _heroItem = full;
            }
          });
        }
      } catch (_) {}
    });
  }
  DateTime? _lastBackPressTime;

  bool _handleBackPress() {
    if (!PlixDeviceHelper.isCompact(context) && !_isSidebarFocused) {
      _sidebarHomeFocusNode.requestFocus();
      return true;
    }

    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Press back again to exit',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 240,
          backgroundColor: PlixTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.white24),
          ),
        ),
      );
      return true;
    }

    SystemNavigator.pop();
    return true;
  }

  DateTime? _lastUpdateCheckTime;
  bool _isUpdateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mediaService = PlexMediaService(server: widget.server);
    _heroPlayFocusNode.addListener(_onHeroFocusChanged);
    _heroDetailsFocusNode.addListener(_onHeroFocusChanged);
    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAutoUpdate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ThemeMusicService.instance.stopImmediate();
      _checkForAutoUpdate();
    }
  }

  Future<void> _checkForAutoUpdate() async {
    try {
      final isEnabled = await UpdateService.isAutoCheckEnabled();
      if (!isEnabled) return;

      // Throttle automatic checks so we don't spam if resumed frequently
      final now = DateTime.now();
      if (_lastUpdateCheckTime != null &&
          now.difference(_lastUpdateCheckTime!) < const Duration(seconds: 30)) {
        return;
      }
      _lastUpdateCheckTime = now;

      final updateInfo = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (updateInfo != null && updateInfo.hasUpdate) {
        setState(() {
          _isUpdateDialogOpen = true;
        });
        FocusManager.instance.primaryFocus?.unfocus();
        try {
          await UpdateService.showUpdateDialog(context, updateInfo);
        } finally {
          if (mounted) {
            setState(() {
              _isUpdateDialogOpen = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                if (_continueWatching.isNotEmpty) {
                  _heroPlayFocusNode.requestFocus();
                } else if (_activeRowIds.isNotEmpty) {
                  _rowSectionKeys[_activeRowIds.first]?.currentState?.focusAt(0);
                }
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  void _onHeroFocusChanged() {
    if (_heroPlayFocusNode.hasFocus || _heroDetailsFocusNode.hasFocus) {
      _lastFocusedRowId = 'continue_watching';
      _lastFocusedContentNode = _heroPlayFocusNode.hasFocus ? _heroPlayFocusNode : _heroDetailsFocusNode;
      if (mounted) setState(() {});
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _heroHoverTimer?.cancel();
    _mobileHeroTimer?.cancel();
    _heroMetadataDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _heroPlayFocusNode.removeListener(_onHeroFocusChanged);
    _heroDetailsFocusNode.removeListener(_onHeroFocusChanged);
    _heroPlayFocusNode.dispose();
    _heroDetailsFocusNode.dispose();
    _sidebarHomeFocusNode.dispose();
    _firstContinueWatchingFocusNode.dispose();
    for (final node in _viewMoreFocusNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    ThemeMusicService.instance.stopImmediate();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _clientId = await widget.authService.getClientIdentifier();
      final libs = await _mediaService.getLibraries();

      // Apply saved library order
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedOrder = prefs.getStringList('library_order_${widget.server.clientIdentifier}');
        if (savedOrder != null && savedOrder.isNotEmpty) {
          final Map<String, int> orderMap = {
            for (int i = 0; i < savedOrder.length; i++) savedOrder[i]: i,
          };
          libs.sort((a, b) {
            final aOrder = orderMap[a.key] ?? 999;
            final bOrder = orderMap[b.key] ?? 999;
            return aOrder.compareTo(bOrder);
          });
        }
      } catch (_) {}

      final continueWatching = await _mediaService.getContinueWatching();

      _libraries = libs;
      _continueWatching = continueWatching;

      if (_continueWatching.isNotEmpty) {
        _heroItem = _continueWatching.first;
        if (_heroItem!.ratingKey.isNotEmpty) {
          _fetchHeroFullMetadata(_heroItem!);
        }
      }

      // Fetch recently added for each library (limit to 15 on home screen)
      for (final lib in libs) {
        final items = await _mediaService.getRecentlyAdded(
          lib.key,
          limit: 15,
          libraryType: lib.type,
        );
        _recentlyAddedByLibrary[lib.key] = items.take(15).toList();
        if (_heroItem == null && items.isNotEmpty) {
          _heroItem = items.first;
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _startMobileHeroTimer();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isUpdateDialogOpen || ModalRoute.of(context)?.isCurrent != true) return;
          if (PlixDeviceHelper.isPhone(context)) return;
          if (!mounted) return;
          if (_continueWatching.isNotEmpty) {
            _heroPlayFocusNode.requestFocus();
          } else {
            final rowIds = _activeRowIds;
            if (rowIds.isNotEmpty) {
              _rowSectionKeys[rowIds.first]?.currentState?.focusAt(0);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load home content: $e';
        });
      }
    }
  }

  Future<void> _saveLibraryOrder(List<PlexLibrary> reordered) async {
    setState(() {
      _libraries = List.from(reordered);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = reordered.map((l) => l.key).toList();
      await prefs.setStringList('library_order_${widget.server.clientIdentifier}', keys);
    } catch (_) {}
  }

  List<String> get _activeRowIds {
    final list = <String>[];
    if (_continueWatching.isNotEmpty) list.add('continue_watching');
    for (final lib in _libraries) {
      if (_recentlyAddedByLibrary[lib.key]?.isNotEmpty == true) {
        list.add('lib_${lib.key}');
      }
    }
    return list;
  }

  void _navigateRowVertical(String fromRowId, int delta) {
    final rowIds = _activeRowIds;
    final currentIdx = rowIds.indexOf(fromRowId);
    if (currentIdx == -1) return;

    final targetIdx = currentIdx + delta;
    if (delta < 0 && targetIdx < 0) {
      if (_showHeroButtons && _heroDetailsFocusNode.canRequestFocus) {
        _heroDetailsFocusNode.requestFocus();
      }
      return;
    }

    if (targetIdx >= 0 && targetIdx < rowIds.length) {
      final targetRowId = rowIds[targetIdx];
      final targetItemIndex = _rowLastFocusedIndices[targetRowId] ?? 0;
      _rowSectionKeys[targetRowId]?.currentState?.focusAt(targetItemIndex);
    }
  }

  void _navigateFromHeroDown() {
    if (_continueWatching.isNotEmpty) {
      final targetIdx = _rowLastFocusedIndices['continue_watching'] ?? 0;
      _rowSectionKeys['continue_watching']?.currentState?.focusAt(targetIdx);
    } else {
      final rowIds = _activeRowIds;
      if (rowIds.isNotEmpty) {
        final targetIdx = _rowLastFocusedIndices[rowIds.first] ?? 0;
        _rowSectionKeys[rowIds.first]?.currentState?.focusAt(targetIdx);
      }
    }
  }

  void _onViewMoreCardFocused(BuildContext rowContext, String rowId, FocusNode node, String title) {
    _lastFocusedContentNode = node;
    final rowChanged = _lastFocusedRowId != rowId;
    if (rowChanged) {
      _lastFocusedRowId = rowId;
    }
    _heroMetadataDebounceTimer?.cancel();
    setState(() {
      _heroViewMoreTitle = 'View More $title';
      _heroItem = null;
    });

    if (rowChanged) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onRowItemFocused(PlexMediaItem item, BuildContext rowContext, String rowId, [FocusNode? node, bool isFirstRow = false, int? itemIndex]) {
    _heroViewMoreTitle = null;
    if (node != null) {
      _lastFocusedContentNode = node;
    }
    if (itemIndex != null) {
      _rowLastFocusedIndices[rowId] = itemIndex;
    }
    final rowChanged = _lastFocusedRowId != rowId;
    if (rowChanged) {
      _lastFocusedRowId = rowId;
    }
    setState(() {
      _heroItem = item;
    });
    if (item.ratingKey.isNotEmpty) {
      _fetchHeroFullMetadata(item);
    }

    // Only scroll vertically when changing rows (not when navigating horizontally within the same row)
    if (rowChanged) {
      if (isFirstRow) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      } else {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (isFirstRow && _scrollController.hasClients && _scrollController.offset > 0.0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _openDetails(PlexMediaItem item) async {
    PlexMediaItem targetItem = item;
    String? seasonKey = item.targetSeasonKey;

    if (item.targetType == 'episode' && item.targetRatingKey != null) {
      try {
        final ep = await _mediaService.getItemMetadata(item.targetRatingKey!);
        targetItem = ep;
      } catch (_) {
        targetItem = item;
      }
    }

    if (!mounted) return;

    final previousFirstKey = _continueWatching.firstOrNull?.ratingKey;
    final openedRatingKey = item.ratingKey;

    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: targetItem,
          initialSeasonKey: seasonKey,
          server: widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(openedRatingKey: openedRatingKey, previousFirstKey: previousFirstKey);
    });
  }

  Future<void> _refreshContinueWatching({
    String? openedRatingKey,
    String? previousFirstKey,
    bool forceFocusFirst = false,
  }) async {
    try {
      final cwFuture = _mediaService.getContinueWatching();
      final recentlyAddedMap = <String, List<PlexMediaItem>>{};
      final recentlyAddedFutures = _libraries.map((lib) async {
        try {
          final items = await _mediaService.getRecentlyAdded(
            lib.key,
            limit: 15,
            libraryType: lib.type,
          );
          recentlyAddedMap[lib.key] = items.take(15).toList();
        } catch (_) {}
      });

      final cw = await cwFuture;
      await Future.wait(recentlyAddedFutures);

      if (mounted) {
        final oldFirst = _continueWatching.firstOrNull;
        final newFirst = cw.firstOrNull;
        final newFirstKey = newFirst?.ratingKey;
        final continueWatchingChanged = oldFirst == null ||
            newFirst == null ||
            oldFirst.ratingKey != newFirst.ratingKey ||
            oldFirst.targetRatingKey != newFirst.targetRatingKey ||
            (oldFirst.viewOffset ?? -1) != (newFirst.viewOffset ?? -1);
        final didItemMoveToFront = openedRatingKey != null &&
            newFirstKey != null &&
            newFirstKey != previousFirstKey &&
            (newFirstKey == openedRatingKey || cw.any((it) => it.ratingKey == openedRatingKey && it.ratingKey == newFirstKey));

        // After playback, the active Continue Watching item may be a later
        // episode (or even a different show). Keep the hero in sync with it.
        final shouldUpdateHero = openedRatingKey != null &&
            cw.isNotEmpty &&
            continueWatchingChanged;
        final shouldFocusFirst = forceFocusFirst || didItemMoveToFront || shouldUpdateHero;

        setState(() {
          _continueWatching = cw;
          if (recentlyAddedMap.isNotEmpty) {
            _recentlyAddedByLibrary.addAll(recentlyAddedMap);
          }
          if ((shouldFocusFirst || shouldUpdateHero) && cw.isNotEmpty) {
            _heroItem = cw.first;
          } else if (_heroItem != null) {
            final match = cw.where((item) => item.ratingKey == _heroItem!.ratingKey);
            if (match.isNotEmpty) {
              _heroItem = match.first;
            }
          }
        });

        _startMobileHeroTimer();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isUpdateDialogOpen || ModalRoute.of(context)?.isCurrent != true) return;
          if (PlixDeviceHelper.isPhone(context)) return;
          if (!mounted) return;
          // Never steal focus if user currently has focus in sidebar nav or on a sidebar item!
          if (_isSidebarFocused || _sidebarHomeFocusNode.hasFocus) {
            return;
          }
          if (shouldFocusFirst) {
            _firstContinueWatchingFocusNode.requestFocus();
          } else {
            if (_lastFocusedContentNode != null &&
                _lastFocusedContentNode!.canRequestFocus &&
                _lastFocusedContentNode!.context != null &&
                _lastFocusedContentNode!.context!.mounted) {
              _lastFocusedContentNode!.requestFocus();
            }
          }
        });
      }
    } catch (_) {}
  }

  void _quickPlay(PlexMediaItem item) {
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: item,
          server: widget.server,
          clientId: _clientId,
          initialPositionMs: item.viewOffset ?? 0,
        ),
      ),
    ).then((_) => _refreshContinueWatching(
          openedRatingKey: item.ratingKey,
          previousFirstKey: _continueWatching.firstOrNull?.ratingKey,
          forceFocusFirst: false,
        ));
  }

  void _switchServer() async {
    final token = await widget.authService.getSavedToken() ?? '';
    final servers = await widget.serverService.fetchServers(token);
    if (!mounted) return;
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerSelectScreen(
          servers: servers,
          authService: widget.authService,
          serverService: widget.serverService,
          currentServer: widget.server,
        ),
      ),
    );
  }

  void _signOut() async {
    await widget.authService.logout();
    if (widget.server.isJellyfin) {
      await widget.serverService.removeServer(widget.server.clientIdentifier);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AuthChooserScreen(
          authService: widget.authService,
          serverService: widget.serverService,
        ),
      ),
    );
  }

  void _openLibrary(PlexLibrary lib) {
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          library: lib,
          server: widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(forceFocusFirst: false);
    });
  }

  void _openRecentlyAdded(PlexLibrary lib) {
    final focusNode = _viewMoreFocusNodes[lib.key];
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentlyAddedScreen(
          library: lib,
          server: widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(forceFocusFirst: false);
      if (focusNode != null && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  void _openSearch() {
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          server: widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(forceFocusFirst: false);
    });
  }

  void _openWatchlist() {
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchlistScreen(
          server: widget.server,
          authService: widget.authService,
          serverService: widget.serverService,
          clientId: _clientId,
        ),
      ),
    ).then((_) async {
      // Let the watchlist route finish its pop animation and dispose its
      // images before Home starts loading its own artwork again. This is the
      // transition that triggered the TV OOM.
      await Future.delayed(const Duration(milliseconds: 350));
      PlixImageCache.trim();
      if (!mounted) return;
      _refreshContinueWatching(forceFocusFirst: false);
    });
  }

  void _openSettings() {
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          server: widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(forceFocusFirst: false);
    });
  }


  Widget _buildMobileTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: PlixTheme.background,
      child: Row(
        children: [
          const PlixAppLogo(size: 32, glow: true),
          const SizedBox(width: 8),
          const PlixWordmark(fontSize: 20),
          const Spacer(),
          // Server switcher pill
          InkWell(
            onTap: _switchServer,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: PlixTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.server.isJellyfin ? const Color(0xFF8E51DC) : const Color(0xFFE5A00D),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.server.isJellyfin)
                    const JellyfinLogo(size: 14, color: Color(0xFF8E51DC))
                  else
                    const PlexLogo(size: 14, color: Color(0xFFE5A00D)),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      widget.server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.white70),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            tooltip: 'Search',
            onPressed: _openSearch,
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildPhoneBottomNav() {
    return PlixBottomNav(
      currentIndex: 0,
      server: widget.server,
      authService: widget.authService,
      serverService: widget.serverService,
      clientId: _clientId,
      libraries: _libraries,
      onLibrariesReordered: _saveLibraryOrder,
      onHomeTap: _scrollToTop,
      onWatchlistTap: _openWatchlist,
      onSearchTap: _openSearch,
      onLibrariesTap: _showLibrariesSheet,
      onSettingsTap: _openSettings,
    );
  }

  void _showLibrariesSheet() {
    PlixBottomNav(
      currentIndex: 3,
      server: widget.server,
      authService: widget.authService,
      serverService: widget.serverService,
      clientId: _clientId,
      libraries: _libraries,
      onLibrariesReordered: _saveLibraryOrder,
    ).showLibrariesModal(context);
  }

  Widget _buildMobileHero(BuildContext context, String heroBackdropUrl) {
    if (_heroItem == null) return const SizedBox.shrink();
    final item = _heroItem!;
    final posterUrl = _mediaService.buildImageUrl(
      item.thumb ?? item.art,
      width: PlixImageCache.mobileHeroWidth,
      height: PlixImageCache.mobileHeroHeight,
    );
    final bgUrl = heroBackdropUrl.isNotEmpty ? heroBackdropUrl : posterUrl;
    final heroWidth = PlixImageCache.decodeWidth(
      context,
      MediaQuery.sizeOf(context).width - 32,
      cap: PlixImageCache.mobileHeroWidth,
    );
    final heroHeight = PlixImageCache.decodeHeight(
      context,
      290,
      cap: PlixImageCache.mobileHeroHeight,
    );

    return Container(
      height: 290,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: PlixTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (bgUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: bgUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: heroWidth,
                memCacheHeight: heroHeight,
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.95),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 18,
                  child: item.heroTopTitle != null && item.heroTopTitle!.isNotEmpty
                      ? Text(
                          item.heroTopTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 26,
                  child: Text(
                    item.heroMainTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 22,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (item.year != null) ...[
                          Text(
                            item.year.toString(),
                            style: const TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (!item.isShow && !item.isSeason && item.targetType != 'season' && item.formattedDuration.isNotEmpty) ...[
                          Text(
                            item.formattedDuration,
                            style: const TextStyle(
                              color: PlixTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (item.contentRating != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              border: Border.all(color: PlixTheme.cardBorder),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              item.contentRating!,
                              style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (item.formattedResolution.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: PlixTheme.plexGold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              item.formattedResolution,
                              style: TextStyle(
                                color: PlixTheme.plexGold,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (item.isHdr)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: PlixTheme.plexGold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: PlixTheme.plexGold.withOpacity(0.6)),
                            ),
                            child: Text(
                              item.hdrBadge.isNotEmpty ? item.hdrBadge : 'HDR10',
                              style: TextStyle(
                                color: PlixTheme.plexGold,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PlixTheme.plexGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text(
                          item.isInProgress
                              ? (item.formattedResumeTime.isNotEmpty
                                  ? 'Resume from ${item.formattedResumeTime}'
                                  : 'Resume')
                              : 'Watch Now',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () => _quickPlay(item),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      onPressed: () => _openDetails(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvHero() {
    if (_heroViewMoreTitle != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: SizedBox(
            height: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const SizedBox(height: 2),
                SizedBox(
                  height: 36,
                  child: Text(
                    _heroViewMoreTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_heroItem == null) return const SizedBox.shrink();
    final showButtons = _showHeroButtons;
    final resumeLabel = _heroItem!.isInProgress
        ? (_heroItem!.formattedResumeTime.isNotEmpty
            ? 'Resume from ${_heroItem!.formattedResumeTime}'
            : 'Resume')
        : 'Watch Now';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: Visibility(
                  visible: _heroItem!.heroTopTitle != null && _heroItem!.heroTopTitle!.isNotEmpty,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(
                    _heroItem!.heroTopTitle ?? '',
                    style: TextStyle(
                      color: PlixTheme.plexGold,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 36,
                child: Text(
                  _heroItem!.heroMainTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    if (_heroItem!.year != null) ...[
                      Text(
                        _heroItem!.year.toString(),
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (!_heroItem!.isShow &&
                        !_heroItem!.isSeason &&
                        _heroItem!.targetType != 'season' &&
                        _heroItem!.formattedDuration.isNotEmpty) ...[
                      Text(
                        _heroItem!.formattedDuration,
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_heroItem!.contentRating != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: PlixTheme.cardBorder),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _heroItem!.contentRating!,
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_heroItem!.formattedResolution.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PlixTheme.plexGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _heroItem!.formattedResolution,
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (_heroItem!.isHdr) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PlixTheme.plexGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: PlixTheme.plexGold.withOpacity(0.6),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _heroItem!.hdrBadge.isNotEmpty ? _heroItem!.hdrBadge : 'HDR10',
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SizedBox(
                  height: 32,
                  child: Text(
                    _heroItem!.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textSecondary,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              if (showButtons) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      PlixButton(
                        focusNode: _heroPlayFocusNode,
                        autofocus: _continueWatching.isNotEmpty,
                        isPrimary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: resumeLabel,
                        blockUp: true,
                        onUp: () {},
                        onLeft: () => _sidebarHomeFocusNode.requestFocus(),
                        onRight: () => _heroDetailsFocusNode.requestFocus(),
                        onDown: _navigateFromHeroDown,
                        onPressed: () => _quickPlay(_heroItem!),
                      ),
                      const SizedBox(width: 12),
                      PlixButton(
                        focusNode: _heroDetailsFocusNode,
                        isPrimary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: 'Details',
                        blockUp: true,
                        onUp: () {},
                        onLeft: () => _heroPlayFocusNode.requestFocus(),
                        onDown: _navigateFromHeroDown,
                        onPressed: () => _openDetails(_heroItem!),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final heroBackdropUrl = _heroItem != null
        ? _mediaService.buildImageUrl(
            _heroItem!.art ?? _heroItem!.thumb,
            width: 1920,
            height: 1080,
          )
        : '';
    final heroDecodeWidth = PlixImageCache.decodeWidth(
      context,
      MediaQuery.sizeOf(context).width,
      cap: PlixImageCache.backdropWidth,
    );
    final heroDecodeHeight = PlixImageCache.decodeHeight(
      context,
      480,
      cap: PlixImageCache.backdropHeight,
    );

    Widget mainContentArea = Stack(
      fit: StackFit.expand,
      children: [
        // Top Hero Backdrop Art (TV / Desktop landscape only; mobile uses featured card)
        if (!isCompact && heroBackdropUrl.isNotEmpty)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 480,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: CachedNetworkImage(
                              key: ValueKey(heroBackdropUrl),
                              imageUrl: heroBackdropUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              memCacheWidth: heroDecodeWidth,
                              memCacheHeight: heroDecodeHeight,
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  PlixTheme.background.withOpacity(0.2),
                                  PlixTheme.background.withOpacity(0.8),
                                  PlixTheme.background,
                                ],
                                stops: const [0.0, 0.65, 1.0],
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  PlixTheme.background.withOpacity(0.9),
                                  PlixTheme.background.withOpacity(0.4),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.45, 0.85],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Scrollable Rows
                  if (_isLoading)
                    Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                      ),
                    )
                  else if (_errorMessage != null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 16),
                          PlixButton(
                            label: 'Retry',
                            onPressed: _initData,
                          ),
                        ],
                      ),
                    )
                  else if (isCompact)
                    RefreshIndicator(
                      onRefresh: _initData,
                      color: PlixTheme.plexGold,
                      backgroundColor: PlixTheme.surface,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.only(top: 0, bottom: 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMobileHero(context, heroBackdropUrl),
                            const SizedBox(height: 16),
                            _buildRows(true),
                          ],
                        ),
                      ),
                    )
                  else
                    // TV & Desktop: Sticky Hero Section on Top, Scrollable Rows underneath
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_heroItem != null || _heroViewMoreTitle != null) ...[
                          _buildTvHero(),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.only(left: 40, right: 40, top: 14, bottom: 4),
                            color: Colors.white.withOpacity(0.08),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.only(top: 2, bottom: 32),
                            child: _buildRows(false),
                          ),
                        ),
                      ],
                    ),
                ],
              );

    if (isCompact) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _handleBackPress();
          }
        },
        child: Scaffold(
          backgroundColor: PlixTheme.background,
          bottomNavigationBar: _buildPhoneBottomNav(),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildMobileTopHeader(),
                Expanded(child: mainContentArea),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: PlixTheme.background,
        body: ExcludeFocus(
          excluding: _isUpdateDialogOpen,
          child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.goBack)) {
              _handleBackPress();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            children: [
              SidebarNav(
                currentServer: widget.server,
                libraries: _libraries,
                activeDestination: NavDestination.home,
                homeFocusNode: _sidebarHomeFocusNode,
                onLibrariesReordered: _saveLibraryOrder,
                onFocusChange: (focused) => setState(() => _isSidebarFocused = focused),
                onOpenSettings: _openSettings,
                onDestinationSelected: (dest) {
                  if (dest == NavDestination.home) {
                    _refreshContinueWatching(forceFocusFirst: false);
                    if (_lastFocusedContentNode != null &&
                        _lastFocusedContentNode!.canRequestFocus) {
                      _lastFocusedContentNode!.requestFocus();
                    } else if (_heroPlayFocusNode.canRequestFocus) {
                      _heroPlayFocusNode.requestFocus();
                    }
                  } else if (dest == NavDestination.search) {
                    _openSearch();
                  } else if (dest == NavDestination.watchlist) {
                    _openWatchlist();
                  }
                },
                onLibrarySelected: _openLibrary,
                onSwitchServer: _switchServer,
                onSignOut: _signOut,
                onNavigateRight: () {
                  if (_lastFocusedContentNode != null &&
                      _lastFocusedContentNode!.canRequestFocus &&
                      _lastFocusedContentNode!.context != null &&
                      _lastFocusedContentNode!.context!.mounted) {
                    _lastFocusedContentNode!.requestFocus();
                    return;
                  }
                  if (_heroPlayFocusNode.canRequestFocus &&
                      _heroPlayFocusNode.context != null &&
                      _heroPlayFocusNode.context!.mounted) {
                    _heroPlayFocusNode.requestFocus();
                    return;
                  }
                },
              ),
              Expanded(child: mainContentArea),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildRows(bool isCompact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Continue Watching
        if (_continueWatching.isNotEmpty)
          _HomeRowSection(
            key: _rowSectionKeys.putIfAbsent('continue_watching', () => GlobalKey<_HomeRowSectionState>()),
            highlightedItemId: isCompact ? _heroItem?.ratingKey : null,
            rowId: 'continue_watching',
            title: 'Continue Watching',
            icon: Icons.history_rounded,
            items: _continueWatching,
            mediaService: _mediaService,
            autofocusFirst: false,
            isFirstRow: true,
            firstItemFocusNode: _firstContinueWatchingFocusNode,
            onLeftAtFirst: () => _sidebarHomeFocusNode.requestFocus(),
            onRowUp: () => _heroPlayFocusNode.requestFocus(),
            onRowDown: () => _navigateRowVertical('continue_watching', 1),
            onItemFocused: _onRowItemFocused,
            onItemSelected: _openDetails,
            onItemHovered: _onMediaTileHover,
            isLastRow: _libraries.isEmpty,
          ),

        // Row 2+: Recently Added for each library
        () {
          bool firstRowFound = false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final lib in _libraries)
                if (_recentlyAddedByLibrary[lib.key]?.isNotEmpty == true)
                  Builder(builder: (context) {
                    final isTopRecentlyAdded = !firstRowFound;
                    firstRowFound = true;
                    final viewMoreNode = _viewMoreFocusNodes.putIfAbsent(lib.key, () => FocusNode());
                    final rowId = 'lib_${lib.key}';
                    return _HomeRowSection(
                      key: _rowSectionKeys.putIfAbsent(rowId, () => GlobalKey<_HomeRowSectionState>()),
                      rowId: rowId,
                      title: 'Recently Added in ${lib.title}',
                      icon: lib.isMovie
                          ? Icons.movie_outlined
                          : Icons.tv_outlined,
                      onViewMore: () => _openRecentlyAdded(lib),
                      viewMoreFocusNode: viewMoreNode,
                      items: _recentlyAddedByLibrary[lib.key]!.take(15).toList(),
                      mediaService: _mediaService,
                      autofocusFirst: _continueWatching.isEmpty && isTopRecentlyAdded,
                      isFirstRow: _continueWatching.isEmpty && isTopRecentlyAdded,
                      onLeftAtFirst: () => _sidebarHomeFocusNode.requestFocus(),
                      onRowUp: () {
                        if (_continueWatching.isEmpty && isTopRecentlyAdded) {
                          // Top row when continue watching is empty: stay or go left
                        } else {
                          _navigateRowVertical(rowId, -1);
                        }
                      },
                      onRowDown: () => _navigateRowVertical(rowId, 1),
                      onItemFocused: _onRowItemFocused,
                      onViewMoreFocused: _onViewMoreCardFocused,
                      onItemSelected: _openDetails,
                      onItemHovered: _onMediaTileHover,
                      isLastRow: lib == _libraries.last,
                    );
                  }),
            ],
          );
        }(),
        // Extra bottom spacing so the last row can scroll up directly underneath the hero section
        SizedBox(height: isCompact ? 24 : 320),
      ],
    );
  }

}

class _HomeRowSection extends StatefulWidget {
  final String rowId;
  final String title;
  final IconData icon;
  final VoidCallback? onViewMore;
  final FocusNode? viewMoreFocusNode;
  final List<PlexMediaItem> items;
  final PlexMediaService mediaService;
  final bool autofocusFirst;
  final bool isFirstRow;
  final FocusNode? firstItemFocusNode;
  final void Function(PlexMediaItem item, BuildContext rowContext, String rowId, [FocusNode? node, bool isFirstRow, int? itemIndex])
      onItemFocused;
  final void Function(BuildContext rowContext, String rowId, FocusNode node, String title)? onViewMoreFocused;
  final ValueChanged<PlexMediaItem> onItemSelected;
  final VoidCallback? onLeftAtFirst;
  final VoidCallback? onRowUp;
  final VoidCallback? onRowDown;
  final bool isLastRow;
  final String? highlightedItemId;

  final void Function(PlexMediaItem item, bool isHovered)? onItemHovered;

  const _HomeRowSection({
    super.key,
    required this.rowId,
    required this.title,
    required this.icon,
    this.onViewMore,
    this.viewMoreFocusNode,
    required this.items,
    required this.mediaService,
    this.autofocusFirst = false,
    this.isFirstRow = false,
    this.firstItemFocusNode,
    required this.onItemFocused,
    this.onViewMoreFocused,
    required this.onItemSelected,
    this.onItemHovered,
    this.onLeftAtFirst,
    this.onRowUp,
    this.onRowDown,
    this.isLastRow = false,
    this.highlightedItemId,
  });

  @override
  State<_HomeRowSection> createState() => _HomeRowSectionState();
}

class _HomeRowSectionState extends State<_HomeRowSection> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, FocusNode> _itemFocusNodes = {};

  FocusNode _focusNodeAt(int index) {
    if (index == 0 && widget.firstItemFocusNode != null) {
      return widget.firstItemFocusNode!;
    }
    if (widget.onViewMore != null && index == widget.items.length && widget.viewMoreFocusNode != null) {
      return widget.viewMoreFocusNode!;
    }
    return _itemFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final isCompact = PlixDeviceHelper.isCompact(context);
    final itemWidth = (isCompact ? 120.0 : 112.0) + 16.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final target = (index * itemWidth).clamp(0.0, maxScroll);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  void focusAt(int index) {
    final maxIdx = widget.items.length + (widget.onViewMore != null ? 0 : -1);
    if (maxIdx < 0) return;
    final clamped = index.clamp(0, maxIdx);
    final node = _focusNodeAt(clamped);
    if (node.canRequestFocus) {
      node.requestFocus();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onItemFocus(int index, PlexMediaItem item, BuildContext sectionContext, FocusNode node) {
    if (_scrollController.hasClients) {
      if (index == 0) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        final viewport = _scrollController.position.viewportDimension;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        final isCompact = PlixDeviceHelper.isCompact(context);
        final itemWidth = (isCompact ? 120.0 : 112.0) + 16.0;
        final itemLeft = (isCompact ? 16.0 : 40.0) + index * itemWidth;
        final itemRight = itemLeft + itemWidth;

        if (itemRight > currentScroll + viewport - 120) {
          final target = (itemRight - viewport + 160).clamp(0.0, maxScroll);
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        } else if (itemLeft < currentScroll + 120) {
          final target = (itemLeft - 120).clamp(0.0, maxScroll);
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
    widget.onItemFocused(item, sectionContext, widget.rowId, node, widget.isFirstRow, index);
  }

  void _onViewMoreFocus(int index, BuildContext sectionContext, FocusNode node) {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    if (widget.onViewMoreFocused != null) {
      widget.onViewMoreFocused!(sectionContext, widget.rowId, node, widget.title);
    } else if (widget.items.isNotEmpty) {
      widget.onItemFocused(widget.items.last, sectionContext, widget.rowId, node, widget.isFirstRow, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final hasViewMore = widget.onViewMore != null;
    final totalCount = widget.items.length + (hasViewMore ? 1 : 0);

    return Builder(
      builder: (sectionContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 40,
                vertical: isCompact ? 8 : 4,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: PlixTheme.plexGold, size: isCompact ? 20 : 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: PlixTheme.textPrimary,
                      fontSize: isCompact ? 20 : 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (hasViewMore) ...[
                    const Spacer(),
                    InkWell(
                      onTap: widget.onViewMore,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'See all',
                              style: TextStyle(
                                color: PlixTheme.plexGold,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, color: PlixTheme.plexGold, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: isCompact ? 245 : 230,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                cacheExtent: 3500,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32),
                itemCount: totalCount,
                itemBuilder: (context, index) {
                  if (index < widget.items.length) {
                    final item = widget.items[index];
                    final isFirst = index == 0;
                    final isLast = index == totalCount - 1;
                    final itemNode = _focusNodeAt(index);

                    final isHighlightedCard = isCompact && widget.highlightedItemId != null && item.ratingKey == widget.highlightedItemId;
                    return MediaCard(
                      enableHighlight: !isCompact || isHighlightedCard,
                      isForcedHighlighted: isHighlightedCard,
                      item: item,
                      mediaService: widget.mediaService,
                      autofocus: widget.autofocusFirst && isFirst,
                      focusNode: itemNode,
                      width: isCompact ? 120 : 112,
                      onLeft: isFirst ? widget.onLeftAtFirst : () => _focusNodeAt(index - 1).requestFocus(),
                      onRight: isLast ? () {} : () => _focusNodeAt(index + 1).requestFocus(),
                      onUp: widget.onRowUp,
                      onDown: widget.onRowDown,
                      blockRight: isLast,
                      blockDown: widget.isLastRow,
                      onHover: widget.onItemHovered != null
                          ? (hovered) => widget.onItemHovered!(item, hovered)
                          : null,
                      onFocusWithNode: (node, focused) {
                        if (focused) {
                          _onItemFocus(index, item, sectionContext, node);
                        }
                      },
                      onTap: () => widget.onItemSelected(item),
                    );
                  } else {
                    // View More tile at end of row
                    final viewMoreNode = _focusNodeAt(widget.items.length);
                    return _ViewMoreCard(
                      focusNode: viewMoreNode,
                      width: isCompact ? 120 : 112,
                      aspectRatio: 2 / 3,
                      blockRight: true,
                      blockDown: widget.isLastRow,
                      onLeft: widget.items.isNotEmpty ? () => _focusNodeAt(widget.items.length - 1).requestFocus() : null,
                      onUp: widget.onRowUp,
                      onDown: widget.onRowDown,
                      onFocused: () {
                        _onViewMoreFocus(widget.items.length, sectionContext, viewMoreNode);
                      },
                      onTap: widget.onViewMore!,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _ViewMoreCard extends StatefulWidget {
  final double width;
  final double aspectRatio;
  final bool blockRight;
  final bool blockDown;
  final FocusNode? focusNode;
  final VoidCallback? onLeft;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onFocused;
  final VoidCallback onTap;

  const _ViewMoreCard({
    required this.width,
    required this.aspectRatio,
    this.blockRight = true,
    this.blockDown = false,
    this.focusNode,
    this.onLeft,
    this.onUp,
    this.onDown,
    this.onFocused,
    required this.onTap,
  });

  @override
  State<_ViewMoreCard> createState() => _ViewMoreCardState();
}

class _ViewMoreCardState extends State<_ViewMoreCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        widget.onFocused?.call();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width / widget.aspectRatio;

    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.blockRight) {
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
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
      child: AnimatedScale(
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) {
            if (Platform.isWindows && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: widget.width,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: height,
                  width: widget.width,
                  decoration: BoxDecoration(
                    color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHighlighted ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: isHighlighted ? 3.0 : 1.0,
                    ),
                    boxShadow: isHighlighted
                        ? [
                            BoxShadow(
                              color: PlixTheme.plexGold.withOpacity(0.5),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isHighlighted ? PlixTheme.plexGold : Colors.white12,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            color: isHighlighted ? Colors.black : PlixTheme.plexGold,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'View More',
                          style: TextStyle(
                            color: isHighlighted ? PlixTheme.plexGold : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Browse all',
                  maxLines: 1,
                  style: TextStyle(
                    color: PlixTheme.textMuted,
                    fontSize: 12,
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