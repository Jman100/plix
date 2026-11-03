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
  static final Map<String, List<PlexMediaItem>> _cachedRecentlyAdded = {};
  static List<PlexMediaItem> _cachedContinueWatching = [];

  late PlexMediaService _mediaService;
  String _clientId = '';

  List<PlexServer> _allServers = [];
  List<PlexServer> _activeServers = [];
  bool get isMultiServer {
    final activeServerCount = _libraries.map((l) => l.serverId).where((s) => s != null && s.isNotEmpty).toSet().length;
    if (activeServerCount > 0) {
      return activeServerCount > 1;
    }
    return _allServers.length > 1 || _activeServers.length > 1;
  }
  List<PlexLibrary> _libraries = [];
  List<PlexMediaItem> _continueWatching = [];
  final Map<String, List<PlexMediaItem>> _recentlyAddedByLibrary = {};

  PlexMediaItem? _heroItem;
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
// Hero action buttons removed to make room for Title Art
  final FocusNode _sidebarHomeFocusNode = FocusNode();
  final FocusNode _sidebarSettingsFocusNode = FocusNode();
  final FocusNode _sidebarSwitchServerFocusNode = FocusNode();
  final FocusNode _sidebarSignOutFocusNode = FocusNode();
  final FocusNode _firstContinueWatchingFocusNode = FocusNode();
  final Map<String, FocusNode> _viewMoreFocusNodes = {};
  final Map<String, GlobalKey<_HomeRowSectionState>> _rowSectionKeys = {};
  final Map<String, int> _rowLastFocusedIndices = {};
  FocusNode? _lastFocusedContentNode;
  String? _lastFocusedRowId;

  String? _heroViewMoreTitle;


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
    if (!(Platform.isWindows || Platform.isLinux)) return;
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

    final heroServer = currentHeroItem.server ?? widget.server;
    final heroService = PlexMediaService(server: heroServer);

    final cached = heroService.getDetailedCachedMetadata(fetchKey);
    if (cached != null) {
      if (isSeasonTarget) {
        _heroItem = cached.copyWith(
          title: currentHeroItem.title,
          grandparentTitle: currentHeroItem.grandparentTitle,
          addedSubtitle: currentHeroItem.addedSubtitle,
          targetType: 'season',
          targetSeasonKey: currentHeroItem.targetSeasonKey,
          targetRatingKey: currentHeroItem.targetRatingKey,
          server: heroServer,
          clearDuration: true,
        );
      } else {
        _heroItem = cached.copyWith(server: heroServer);
      }
    }

    _heroMetadataDebounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        var full = await heroService.getItemMetadata(fetchKey);
        // For episodes, resolve grandparent show logo and backdrop art if missing
        if ((full.isEpisode || currentHeroItem.isEpisode) &&
            (full.clearLogo == null || full.clearLogo!.isEmpty)) {
          final showKey = full.grandparentRatingKey ?? currentHeroItem.grandparentRatingKey;
          if (showKey != null && showKey.isNotEmpty) {
            try {
              final show = await heroService.getItemMetadata(showKey);
              if (show.clearLogo != null && show.clearLogo!.isNotEmpty) {
                full = full.copyWith(
                  clearLogo: show.clearLogo,
                  art: full.art ?? show.art,
                );
              }
            } catch (_) {}
          }
        }
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
                server: heroServer,
                clearDuration: true,
              );
            } else {
              _heroItem = full.copyWith(server: heroServer);
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
  bool _isWelcomeTourOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mediaService = PlexMediaService(server: widget.server);
    _allServers = [widget.server];

    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAutoUpdate();
      _checkFirstTimeWelcomeTour();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ThemeMusicService.instance.stopImmediate();
      _checkForAutoUpdate();
    }
  }

  Future<void> _checkFirstTimeWelcomeTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFreshPending = prefs.getBool('plix_fresh_install_pending_tour') ?? false;
      final tourAlreadyShown = prefs.getBool('plix_welcome_tour_shown') ?? false;

      // Strictly for fresh installs after signing in for the first time.
      // Never show for existing users, updates, or subsequent launches.
      if (!isFreshPending || tourAlreadyShown) {
        if (!tourAlreadyShown) {
          await prefs.setBool('plix_welcome_tour_shown', true);
        }
        await prefs.remove('plix_fresh_install_pending_tour');
        await prefs.remove('plix_is_fresh_install');
        return;
      }

      // Mark tour as permanently shown and remove pending flags immediately
      await prefs.setBool('plix_welcome_tour_shown', true);
      await prefs.remove('plix_fresh_install_pending_tour');
      await prefs.remove('plix_is_fresh_install');

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      setState(() {
        _isWelcomeTourOpen = true;
      });
      FocusManager.instance.primaryFocus?.unfocus();

      try {
        await showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (ctx) => const _WelcomeTourDialog(),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isWelcomeTourOpen = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              if (_continueWatching.isNotEmpty) {
                if (_rowSectionKeys['continue_watching']?.currentState != null) {
                  _rowSectionKeys['continue_watching']!.currentState!.focusAt(0);
                } else if (_firstContinueWatchingFocusNode.canRequestFocus) {
                  _firstContinueWatchingFocusNode.requestFocus();
                }
              } else if (_activeRowIds.isNotEmpty) {
                _rowSectionKeys[_activeRowIds.first]?.currentState?.focusAt(0);
              }
            }
          });
        }
      }
    } catch (_) {}
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
                  if (_rowSectionKeys['continue_watching']?.currentState != null) {
                    _rowSectionKeys['continue_watching']!.currentState!.focusAt(0);
                  } else if (_firstContinueWatchingFocusNode.canRequestFocus) {
                    _firstContinueWatchingFocusNode.requestFocus();
                  }
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



  @override
  void dispose() {
    _heroHoverTimer?.cancel();
    _mobileHeroTimer?.cancel();
    _heroMetadataDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    _sidebarHomeFocusNode.dispose();
    _sidebarSettingsFocusNode.dispose();
    _sidebarSwitchServerFocusNode.dispose();
    _sidebarSignOutFocusNode.dispose();
    _firstContinueWatchingFocusNode.dispose();
    for (final node in _viewMoreFocusNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  bool _isItemInFavoritedLibraries(PlexMediaItem item) {
    if (_libraries.isEmpty) return false;

    final itemServerId = item.serverId ?? item.server?.clientIdentifier;

    // Filter libraries to only those on the same server (if serverId is known)
    final serverLibs = (itemServerId != null && itemServerId.isNotEmpty)
        ? _libraries.where((l) => l.serverId == itemServerId).toList()
        : _libraries;

    if (serverLibs.isEmpty) return false;

    for (final lib in serverLibs) {
      // 1. Direct match via librarySectionId (Plex & Jellyfin)
      if (item.librarySectionId != null && item.librarySectionId!.isNotEmpty) {
        final normItemKey = item.librarySectionId!.replaceAll('-', '').replaceAll('_', '').toLowerCase();
        final normLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
        if (item.librarySectionId == lib.key || normItemKey == normLibKey) {
          return true;
        }
      }

      // 2. Match via ancestorIds (Jellyfin hierarchy)
      if (item.ancestorIds.isNotEmpty) {
        final normalizedLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
        for (final ancestor in item.ancestorIds) {
          final normalizedAncestor = ancestor.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          if (normalizedAncestor == normalizedLibKey) {
            return true;
          }
        }
      }

      // 3. Fallback match via librarySectionTitle if on the same server
      if (item.librarySectionTitle != null && item.librarySectionTitle!.isNotEmpty &&
          item.librarySectionTitle!.toLowerCase() == lib.title.toLowerCase()) {
        return true;
      }

      // 4. If this server only has ONE favorited library, and item came from this server:
      // Match if media types are compatible (e.g. movie in movie library, episode/show in show library)
      if (serverLibs.length == 1) {
        final singleLib = serverLibs.first;
        if (singleLib.isMovie && item.isMovie) return true;
        if (singleLib.isShow && (item.isEpisode || item.isShow)) return true;
        if (!singleLib.isMovie && !singleLib.isShow) return true;
      }
    }

    return false;
  }

  Future<void> _initData() async {
    ThemeMusicService.instance.stopImmediate();
    _lastFocusedContentNode = null;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _clientId = await widget.authService.getClientIdentifier();
      final token = await widget.authService.getSavedToken() ?? '';
      final servers = await widget.serverService.fetchServers(token);
      _allServers = servers;

      // Determine servers that actually have favorited libraries to avoid hitting unused servers
      final favoriteIds = await widget.serverService.getFavoriteLibraryIds();
      final relevantServerIds = <String>{};
      if (favoriteIds != null && favoriteIds.isNotEmpty) {
        for (final fav in favoriteIds) {
          final serverId = fav.contains(':')
              ? fav.split(':').first
              : (fav.contains('_') ? fav.split('_').first : fav);
          relevantServerIds.add(serverId);
        }
      }

      // Include all servers with favorited libraries, plus any saved Jellyfin servers, and current server
      final activeServers = servers.where((s) {
        if (relevantServerIds.isEmpty) return true;
        return relevantServerIds.contains(s.clientIdentifier) ||
            s.isJellyfin ||
            s.clientIdentifier == widget.server.clientIdentifier;
      }).toList();

      // Resolve connection tests for active servers concurrently
      await Future.wait(activeServers.map((s) async {
        try {
          await widget.serverService.testAndResolveBestConnection(s);
        } catch (_) {}
      }));
      _activeServers = activeServers;

      // First, quickly display cached items if available so the UI renders immediately!
      if (_cachedContinueWatching.isNotEmpty && _continueWatching.isEmpty) {
        final cached = _libraries.isNotEmpty
            ? _cachedContinueWatching.where(_isItemInFavoritedLibraries).toList()
            : _cachedContinueWatching;
        if (cached.isNotEmpty) {
          _continueWatching = List.from(cached);
          _heroItem = _continueWatching.first;
          _precacheUpcomingLogos(_continueWatching);
        }
      }
      if (_cachedRecentlyAdded.isNotEmpty && _recentlyAddedByLibrary.isEmpty) {
        _recentlyAddedByLibrary.addAll(_cachedRecentlyAdded);
      }
      if (_continueWatching.isNotEmpty || _recentlyAddedByLibrary.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }

      // Gather libraries across active servers concurrently (8s timeout with cache fallback)
      final allLibrariesLists = await Future.wait(activeServers.map((server) async {
        final isOnline = server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty;
        if (isOnline) {
          try {
            final libs = await PlexMediaService(server: server).getLibraries().timeout(const Duration(seconds: 8));
            await widget.serverService.cacheServerLibraries(server.clientIdentifier, libs);
            return libs;
          } catch (_) {
            return await widget.serverService.getCachedServerLibraries(server.clientIdentifier, server);
          }
        } else {
          return await widget.serverService.getCachedServerLibraries(server.clientIdentifier, server);
        }
      }));

      final List<PlexLibrary> allLibraries = [];
      for (final list in allLibrariesLists) {
        allLibraries.addAll(list);
      }

      List<PlexLibrary> userLibraries;
      if (favoriteIds != null && favoriteIds.isNotEmpty) {
        userLibraries = allLibraries.where((l) {
          return favoriteIds.contains(l.compositeId) ||
              favoriteIds.contains('${l.serverId}_${l.key}') ||
              favoriteIds.contains('${l.serverId}:${l.key}');
        }).toList();
        if (userLibraries.isEmpty && allLibraries.isNotEmpty) {
          userLibraries = allLibraries;
        }
      } else {
        userLibraries = allLibraries;
      }

      // Apply saved library custom order
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList('plix_multi_server_library_order');
      if (savedOrder != null && savedOrder.isNotEmpty) {
        final Map<String, int> orderMap = {
          for (int i = 0; i < savedOrder.length; i++) savedOrder[i]: i,
        };
        userLibraries.sort((a, b) {
          final aOrder = orderMap[a.compositeId] ?? 999999;
          final bOrder = orderMap[b.compositeId] ?? 999999;
          if (aOrder != bOrder) return aOrder.compareTo(bOrder);
          final sA = (a.serverName ?? '').toLowerCase();
          final sB = (b.serverName ?? '').toLowerCase();
          final cmp = sA.compareTo(sB);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      } else {
        userLibraries.sort((a, b) {
          final sA = (a.serverName ?? '').toLowerCase();
          final sB = (b.serverName ?? '').toLowerCase();
          final cmp = sA.compareTo(sB);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      }

      final serverMap = {for (final s in servers) s.clientIdentifier: s};
      _libraries = userLibraries.map((l) {
        final s = l.server ?? serverMap[l.serverId];
        final isOnline = s != null && s.activeConnectionUri != null && s.activeConnectionUri!.isNotEmpty;
        return l.copyWith(server: s, isServerOnline: isOnline);
      }).toList();

      final onlineServers = activeServers.where((s) => s.activeConnectionUri != null && s.activeConnectionUri!.isNotEmpty).toList();
      final onlineLibs = userLibraries.where((l) {
        final s = l.server ?? serverMap[l.serverId];
        return s != null && s.activeConnectionUri != null && s.activeConnectionUri!.isNotEmpty;
      }).map((l) {
        final s = l.server ?? serverMap[l.serverId]!;
        return l.copyWith(server: s, isServerOnline: true);
      }).toList();

      // Gather Continue Watching only from servers that have favorited libraries
      final cwServers = onlineServers.where((s) {
        return _libraries.any((lib) => lib.serverId == s.clientIdentifier);
      }).toList();
      final targetCwServers = cwServers.isNotEmpty ? cwServers : onlineServers;

      final cwFuture = Future.wait(targetCwServers.map((s) async {
        try {
          final serverLibKeys = _libraries
              .where((l) => l.serverId == s.clientIdentifier)
              .map((l) => l.key)
              .toList();
          return await PlexMediaService(server: s)
              .getContinueWatching(libraryKeys: serverLibKeys)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          return <PlexMediaItem>[];
        }
      }));

      final recentFuture = Future.wait(onlineLibs.map((lib) async {
        try {
          final items = await PlexMediaService(server: lib.server!)
              .getRecentlyAdded(lib.key, limit: 15, libraryType: lib.type)
              .timeout(const Duration(seconds: 8));
          if (items.isNotEmpty) {
            _recentlyAddedByLibrary[lib.compositeId] = items.take(15).toList();
            _cachedRecentlyAdded[lib.compositeId] = items.take(15).toList();
            if (mounted) {
              setState(() {
                _heroItem ??= items.first;
              });
            }
          }
        } catch (_) {}
      }));

      final results = await Future.wait([cwFuture, recentFuture]);
      final cwLists = results[0] as List<List<PlexMediaItem>>;
      final continueWatching = <PlexMediaItem>[];
      for (final list in cwLists) {
        continueWatching.addAll(list);
      }
      final filteredContinueWatching = continueWatching.where(_isItemInFavoritedLibraries).toList();
      filteredContinueWatching.sort((a, b) => (b.lastViewedAt ?? 0).compareTo(a.lastViewedAt ?? 0));
      _continueWatching = filteredContinueWatching;
      _cachedContinueWatching = List.from(filteredContinueWatching);
      _precacheUpcomingLogos(_continueWatching);

      if (_continueWatching.isNotEmpty) {
        _heroItem = _continueWatching.first;
        if (_heroItem!.ratingKey.isNotEmpty) {
          _fetchHeroFullMetadata(_heroItem!);
        }
      } else if (_heroItem == null) {
        for (final lib in _libraries) {
          final recents = _recentlyAddedByLibrary[lib.compositeId];
          if (recents != null && recents.isNotEmpty) {
            _heroItem = recents.first;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _startMobileHeroTimer();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isUpdateDialogOpen || _isWelcomeTourOpen || ModalRoute.of(context)?.isCurrent != true) return;
          if (PlixDeviceHelper.isPhone(context)) return;
          if (!mounted) return;
          final currentFocus = FocusScope.of(context).focusedChild;
          final hasActiveFocus = currentFocus != null &&
              currentFocus != FocusScope.of(context) &&
              currentFocus.hasFocus;
          if (hasActiveFocus) return;

          if (_continueWatching.isNotEmpty) {
            if (_rowSectionKeys['continue_watching']?.currentState != null) {
              _rowSectionKeys['continue_watching']!.currentState!.focusAt(0);
            } else if (_firstContinueWatchingFocusNode.canRequestFocus) {
              _firstContinueWatchingFocusNode.requestFocus();
            }
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
      final keys = reordered.map((l) => l.compositeId).toList();
      await prefs.setStringList('plix_multi_server_library_order', keys);
    } catch (_) {}
  }

  List<String> get _activeRowIds {
    final list = <String>[];
    if (_continueWatching.isNotEmpty) list.add('continue_watching');
    for (final lib in _libraries) {
      if (_recentlyAddedByLibrary[lib.compositeId]?.isNotEmpty == true) {
        list.add('lib_${lib.compositeId}');
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
      return;
    }

    if (targetIdx >= 0 && targetIdx < rowIds.length) {
      final targetRowId = rowIds[targetIdx];
      final targetItemIndex = _rowLastFocusedIndices[targetRowId] ?? 0;
      if (targetRowId == 'continue_watching') {
        _lastFocusedRowId = 'continue_watching';
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rowSectionKeys['continue_watching']?.currentState?.focusAt(targetItemIndex);
          if (!_firstContinueWatchingFocusNode.hasFocus) {
            _firstContinueWatchingFocusNode.requestFocus();
          }
        });
        return;
      }
      _rowSectionKeys[targetRowId]?.currentState?.focusAt(targetItemIndex);
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

  Timer? _heroDebounceTimer;

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

    _heroDebounceTimer?.cancel();
    if (rowChanged) {
      setState(() {
        _heroItem = item;
      });
      if (item.ratingKey.isNotEmpty) {
        _fetchHeroFullMetadata(item);
      }
    } else {
      _heroDebounceTimer = Timer(const Duration(milliseconds: 140), () {
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
    final itemServer = item.server ?? widget.server;
    final itemService = PlexMediaService(server: itemServer);

    if (item.targetType == 'episode' && item.targetRatingKey != null) {
      try {
        final ep = await itemService.getItemMetadata(item.targetRatingKey!);
        targetItem = ep.copyWith(server: itemServer);
      } catch (_) {
        targetItem = item.copyWith(server: itemServer);
      }
    } else {
      targetItem = item.copyWith(server: itemServer);
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
          server: itemServer,
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
    bool keepSidebarFocus = false,
  }) async {
    try {
      List<PlexServer> targetServers = List.from(_activeServers);
      if (targetServers.isEmpty) {
        final token = await widget.authService.getSavedToken() ?? '';
        final fetched = await widget.serverService.fetchServers(token);
        await Future.wait(fetched.map((s) async {
          try {
            await widget.serverService.testAndResolveBestConnection(s);
          } catch (_) {}
        }));
        targetServers = fetched;
        _activeServers = targetServers;
      }

      final Map<String, PlexServer> serverMap = {
        for (final s in targetServers)
          if (s.activeConnectionUri != null && s.activeConnectionUri!.isNotEmpty)
            s.clientIdentifier: s,
      };
      for (final lib in _libraries) {
        if (lib.server != null &&
            lib.server!.activeConnectionUri != null &&
            lib.server!.activeConnectionUri!.isNotEmpty) {
          serverMap[lib.server!.clientIdentifier] = lib.server!;
        }
      }
      if (widget.server.activeConnectionUri != null &&
          widget.server.activeConnectionUri!.isNotEmpty) {
        serverMap[widget.server.clientIdentifier] = widget.server;
      }
      final onlineServers = serverMap.values.toList();

      final cwServers = onlineServers.where((s) {
        return _libraries.any((lib) => lib.serverId == s.clientIdentifier);
      }).toList();
      final targetCwServers = cwServers.isNotEmpty ? cwServers : onlineServers;

      final cwLists = await Future.wait(targetCwServers.map((s) async {
        try {
          final serverLibKeys = _libraries
              .where((l) => l.serverId == s.clientIdentifier)
              .map((l) => l.key)
              .toList();
          return await PlexMediaService(server: s)
              .getContinueWatching(libraryKeys: serverLibKeys);
        } catch (_) {
          return <PlexMediaItem>[];
        }
      }));
      final cw = <PlexMediaItem>[];
      for (final list in cwLists) {
        cw.addAll(list);
      }
      final filteredCw = cw.where(_isItemInFavoritedLibraries).toList();
      filteredCw.sort((a, b) => (b.lastViewedAt ?? 0).compareTo(a.lastViewedAt ?? 0));

      if (mounted) {
        final oldFirst = _continueWatching.firstOrNull;
        final newFirst = filteredCw.firstOrNull;
        final newFirstKey = newFirst?.ratingKey;
        final continueWatchingChanged = oldFirst == null ||
            newFirst == null ||
            oldFirst.ratingKey != newFirst.ratingKey ||
            oldFirst.targetRatingKey != newFirst.targetRatingKey ||
            (oldFirst.viewOffset ?? -1) != (newFirst.viewOffset ?? -1);
        final didItemMoveToFront = openedRatingKey != null &&
            newFirstKey != null &&
            newFirstKey != previousFirstKey &&
            (newFirstKey == openedRatingKey || filteredCw.any((it) => it.ratingKey == openedRatingKey && it.ratingKey == newFirstKey));

        // After playback, the active Continue Watching item may be a later
        // episode (or even a different show). Keep the hero in sync with it.
        final shouldUpdateHero = openedRatingKey != null &&
            filteredCw.isNotEmpty &&
            continueWatchingChanged;
        final shouldFocusFirst = forceFocusFirst || didItemMoveToFront || shouldUpdateHero;

        _cachedContinueWatching = List.from(filteredCw);
        setState(() {
          _continueWatching = filteredCw;
          if ((shouldFocusFirst || shouldUpdateHero) && filteredCw.isNotEmpty) {
            _heroItem = filteredCw.first;
          } else if (_heroItem != null) {
            final match = filteredCw.where((item) => item.ratingKey == _heroItem!.ratingKey);
            if (match.isNotEmpty) {
              _heroItem = match.first;
            }
          }
        });

        _startMobileHeroTimer();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isUpdateDialogOpen || _isWelcomeTourOpen || ModalRoute.of(context)?.isCurrent != true) return;
          if (PlixDeviceHelper.isPhone(context)) return;
          if (!mounted) return;
          // Never steal focus if user currently has focus in sidebar nav or on a sidebar item!
          if (keepSidebarFocus || _sidebarSettingsFocusNode.hasFocus || _isSidebarFocused || _sidebarHomeFocusNode.hasFocus) {
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

      // Concurrently update recently added in background without delaying Continue Watching
      final recentlyAddedMap = <String, List<PlexMediaItem>>{};
      final recentlyAddedFutures = _libraries.where((l) => l.isServerOnline && l.server != null).map((lib) async {
        try {
          final items = await PlexMediaService(server: lib.server!).getRecentlyAdded(
            lib.key,
            limit: 15,
            libraryType: lib.type,
          );
          recentlyAddedMap[lib.compositeId] = items.take(15).toList();
        } catch (_) {}
      });
      await Future.wait(recentlyAddedFutures);

      if (mounted && recentlyAddedMap.isNotEmpty) {
        setState(() {
          _recentlyAddedByLibrary.addAll(recentlyAddedMap);
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
          server: item.server ?? widget.server,
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerSelectScreen(
          servers: servers,
          authService: widget.authService,
          serverService: widget.serverService,
          currentServer: widget.server,
        ),
      ),
    );
    if (mounted) {
      _initData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sidebarSwitchServerFocusNode.requestFocus();
        }
      });
    }
  }

  void _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => const _SignOutDialog(),
    );

    if (confirmed != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sidebarSignOutFocusNode.canRequestFocus) {
          _sidebarSignOutFocusNode.requestFocus();
        }
      });
      return;
    }

    await widget.authService.logout();
    await widget.serverService.clearAllServers();
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
          server: lib.server ?? widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      _refreshContinueWatching(forceFocusFirst: false);
    });
  }

  void _openRecentlyAdded(PlexLibrary lib) {
    final focusNode = _viewMoreFocusNodes[lib.compositeId];
    NativePlayerService().stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentlyAddedScreen(
          library: lib,
          server: lib.server ?? widget.server,
          clientId: _clientId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _heroViewMoreTitle = null;
          final items = _recentlyAddedByLibrary[lib.compositeId];
          if (items != null && items.isNotEmpty) {
            _heroItem = items.first;
          }
        });
        _refreshContinueWatching(forceFocusFirst: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (focusNode != null && focusNode.canRequestFocus) {
            focusNode.requestFocus();
          }
        });
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
      _initData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sidebarSettingsFocusNode.requestFocus();
        }
      });
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
          // Customize servers button
          InkWell(
            onTap: _switchServer,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: PlixTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: PlixTheme.cardBorder,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: PlixTheme.plexGold),
                  SizedBox(width: 6),
                  Text(
                    'Customize Servers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
    final heroService = item.server != null ? PlexMediaService(server: item.server!) : _mediaService;
    final posterUrl = heroService.buildImageUrl(
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
          padding: const EdgeInsets.only(top: 26, bottom: 2),
          child: SizedBox(
            height: 166,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 36),
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
                const SizedBox(height: 8),
                const Text(
                  'Browse all items in this library',
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_heroItem == null) return const SizedBox.shrink();

    final item = _heroItem!;
    final heroService = item.server != null ? PlexMediaService(server: item.server!) : _mediaService;
    final isEpisode = item.isEpisode || item.targetType == 'episode';
    final hasLogo = item.clearLogo != null && item.clearLogo!.isNotEmpty;
    final logoUrl = hasLogo ? heroService.buildLogoUrl(item.clearLogo!) : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 2),
        child: SizedBox(
          height: 166,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 90,
                child: isEpisode
                    ? (hasLogo ? _buildEpisodeTitleWithLogo(item, logoUrl) : _buildEpisodeFallbackTitle(item))
                    : (hasLogo ? _buildMovieTitleWithLogo(item, logoUrl) : _buildMovieFallbackTitle(item)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    if (item.year != null) ...[
                      Text(
                        item.year.toString(),
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (!item.isShow &&
                        !item.isSeason &&
                        item.targetType != 'season' &&
                        item.formattedDuration.isNotEmpty) ...[
                      Text(
                        item.formattedDuration,
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (item.contentRating != null) ...[
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
                          item.contentRating!,
                          style: const TextStyle(
                            color: PlixTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (item.formattedResolution.isNotEmpty)
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
                          item.formattedResolution,
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (item.isHdr) ...[
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
                          item.hdrBadge.isNotEmpty ? item.hdrBadge : 'HDR10',
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
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SizedBox(
                  height: 40,
                  child: Text(
                    item.summary,
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
            ],
          ),
        ),
      ),
    );
  }

  void _precacheUpcomingLogos(List<PlexMediaItem> items) {
    if (!mounted || items.isEmpty) return;
    for (final it in items.take(12)) {
      if (it.clearLogo != null && it.clearLogo!.isNotEmpty) {
        final serverToUse = it.server ?? widget.server;
        final service = PlexMediaService(server: serverToUse);
        final url = service.buildLogoUrl(it.clearLogo!);
        if (url.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
        }
      }
    }
  }

  Widget _buildEpisodeTitleWithLogo(PlexMediaItem item, String logoUrl) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 58,
          child: Align(
            alignment: Alignment.centerLeft,
            child: CachedNetworkImage(
              key: ValueKey(logoUrl),
              imageUrl: logoUrl,
              memCacheWidth: 600,
              memCacheHeight: 200,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (context, url) => const SizedBox.shrink(),
              imageBuilder: (context, imageProvider) => Align(
                alignment: Alignment.centerLeft,
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
              ),
              errorWidget: (context, url, error) => _buildEpisodeFallbackTitle(item),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 26,
          child: Text(
            item.heroMainTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeFallbackTitle(PlexMediaItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 22,
          child: Text(
            item.heroTopTitle ?? item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: PlixTheme.plexGold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: Text(
            item.heroMainTitle,
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
    );
  }

  Widget _buildMovieTitleWithLogo(PlexMediaItem item, String logoUrl) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: CachedNetworkImage(
          key: ValueKey(logoUrl),
          imageUrl: logoUrl,
          memCacheWidth: 600,
          memCacheHeight: 200,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => const SizedBox.shrink(),
          imageBuilder: (context, imageProvider) => Align(
            alignment: Alignment.centerLeft,
            child: Image(
              image: imageProvider,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
          errorWidget: (context, url, error) => _buildMovieFallbackTitle(item),
        ),
      ),
    );
  }

  Widget _buildMovieFallbackTitle(PlexMediaItem item) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        item.heroMainTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: PlixTheme.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final heroService = _heroItem?.server != null ? PlexMediaService(server: _heroItem!.server!) : _mediaService;
    final heroBackdropUrl = _heroItem != null
        ? heroService.buildImageUrl(
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
                            layoutBuilder: (currentChild, previousChildren) => Stack(
                              fit: StackFit.expand,
                              alignment: Alignment.topCenter,
                              children: [
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            ),
                            child: SizedBox.expand(
                              key: ValueKey(heroBackdropUrl),
                              child: CachedNetworkImage(
                                imageUrl: heroBackdropUrl,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: heroDecodeWidth,
                                memCacheHeight: heroDecodeHeight,
                              ),
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
                            margin: const EdgeInsets.only(left: 40, right: 40, top: 8, bottom: 4),
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
          excluding: _isUpdateDialogOpen || _isWelcomeTourOpen,
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
          child: Stack(
            children: [
              Positioned.fill(
                left: 72,
                child: RepaintBoundary(
                  child: mainContentArea,
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: RepaintBoundary(
                  child: SidebarNav(
                    currentServer: widget.server,
                    libraries: _libraries,
                    activeDestination: NavDestination.home,
                    homeFocusNode: _sidebarHomeFocusNode,
                    settingsFocusNode: _sidebarSettingsFocusNode,
                    switchServerFocusNode: _sidebarSwitchServerFocusNode,
                    signOutFocusNode: _sidebarSignOutFocusNode,
                    onLibrariesReordered: _saveLibraryOrder,
                    onFocusChange: (focused) => _isSidebarFocused = focused,
                    onOpenSettings: _openSettings,
                    onDestinationSelected: (dest) {
                      if (dest == NavDestination.home) {
                        _refreshContinueWatching(forceFocusFirst: false);
                        if (_continueWatching.isNotEmpty) {
                          if (_rowSectionKeys['continue_watching']?.currentState != null) {
                            _rowSectionKeys['continue_watching']!.currentState!.focusAt(0);
                          } else if (_firstContinueWatchingFocusNode.canRequestFocus) {
                            _firstContinueWatchingFocusNode.requestFocus();
                          }
                        } else {
                          final rowIds = _activeRowIds;
                          if (rowIds.isNotEmpty) {
                            _rowSectionKeys[rowIds.first]?.currentState?.focusAt(0);
                          }
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

                      if (_continueWatching.isNotEmpty) {
                        _rowSectionKeys['continue_watching']?.currentState?.focusAt(0);
                        return;
                      }
                      final rowIds = _activeRowIds;
                      if (rowIds.isNotEmpty) {
                        final targetRow = rowIds.first;
                        final targetIdx = _rowLastFocusedIndices[targetRow] ?? 0;
                        _rowSectionKeys[targetRow]?.currentState?.focusAt(targetIdx);
                      }
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
            hasTopServerName: isMultiServer,
            autofocusFirst: false,
            isFirstRow: true,
            firstItemFocusNode: _firstContinueWatchingFocusNode,
            onLeftAtFirst: () => _sidebarHomeFocusNode.requestFocus(),
            onRowUp: () {},
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
                if (_recentlyAddedByLibrary[lib.compositeId]?.isNotEmpty == true)
                  Builder(builder: (context) {
                    final isTopRecentlyAdded = !firstRowFound;
                    firstRowFound = true;
                    final viewMoreNode = _viewMoreFocusNodes.putIfAbsent(lib.compositeId, () => FocusNode());
                    final rowId = 'lib_${lib.compositeId}';
                    final serverLabel = (isMultiServer && lib.serverName != null && lib.serverName!.isNotEmpty) ? ' (${lib.serverName})' : '';
                    return _HomeRowSection(
                      key: _rowSectionKeys.putIfAbsent(rowId, () => GlobalKey<_HomeRowSectionState>()),
                      rowId: rowId,
                      title: 'Recently Added in ${lib.title}$serverLabel',
                      icon: lib.isMovie
                          ? Icons.movie_outlined
                          : Icons.tv_outlined,
                      onViewMore: () => _openRecentlyAdded(lib),
                      viewMoreFocusNode: viewMoreNode,
                      items: _recentlyAddedByLibrary[lib.compositeId]!.take(15).toList(),
                      mediaService: lib.server != null ? PlexMediaService(server: lib.server!) : _mediaService,
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
  final bool hasTopServerName;

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
    this.hasTopServerName = false,
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
              height: widget.rowId == 'continue_watching'
                  ? (widget.hasTopServerName ? (isCompact ? 10 : 14) : (isCompact ? 8 : 10))
                  : (isCompact ? 8 : 8),
            ),
            SizedBox(
              height: widget.hasTopServerName ? (isCompact ? 268 : 252) : (isCompact ? 245 : 230),
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
                    final itemService = (item.server != null && item.server != widget.mediaService.server)
                        ? PlexMediaService(server: item.server!)
                        : widget.mediaService;
                    final serverName = item.server?.name ?? (item.server?.isJellyfin == true ? 'Jellyfin' : 'Plex');
                    return MediaCard(
                      key: ValueKey('${item.server?.clientIdentifier ?? "srv"}_${item.ratingKey}_${item.viewOffset ?? 0}'),
                      enableHighlight: !isCompact || isHighlightedCard,
                      isForcedHighlighted: isHighlightedCard,
                      item: item,
                      mediaService: itemService,
                      topServerName: widget.hasTopServerName ? serverName : null,
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
            if ((Platform.isWindows || Platform.isLinux) && mounted) {
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
class _SignOutDialog extends StatefulWidget {
  const _SignOutDialog();

  @override
  State<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<_SignOutDialog> {
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _signOutFocusNode = FocusNode();

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _signOutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PlixTheme.cardBorder, width: 1.2),
      ),
      title: const Row(
        children: [
          Icon(Icons.logout_rounded, color: Colors.white70, size: 24),
          SizedBox(width: 10),
          Text(
            'Sign Out',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: const Text(
        'Are you sure you want to sign out? This will sign you out of all connected servers.',
        style: TextStyle(
          color: PlixTheme.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlixButton(
                focusNode: _signOutFocusNode,
                label: 'Sign Out',
                isPrimary: false,
                autofocus: false,
                backgroundColor: PlixTheme.surface,
                highlightColor: PlixTheme.cardFocused,
                borderColor: PlixTheme.cardBorder,
                textColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onUp: () {},
                onDown: () => _cancelFocusNode.requestFocus(),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 12),
              PlixButton(
                focusNode: _cancelFocusNode,
                label: 'Cancel',
                isPrimary: false,
                autofocus: true,
                backgroundColor: PlixTheme.surface,
                highlightColor: PlixTheme.cardFocused,
                borderColor: PlixTheme.cardBorder,
                textColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onUp: () => _signOutFocusNode.requestFocus(),
                onDown: () {},
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _WelcomeTourDialog extends StatefulWidget {
  const _WelcomeTourDialog();

  @override
  State<_WelcomeTourDialog> createState() => _WelcomeTourDialogState();
}

class _WelcomeTourDialogState extends State<_WelcomeTourDialog> {
  final FocusNode _getStartedFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _getStartedFocusNode.canRequestFocus) {
        _getStartedFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _getStartedFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;
    final isMobile = !isTv && (isCompact || Platform.isAndroid || Platform.isIOS);

    return PopScope(
      canPop: true,
      child: FocusScope(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : (isTv ? 48 : 40),
            vertical: isCompact ? 20 : 28,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isTv ? 800 : (isCompact ? 380 : 580),
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            decoration: BoxDecoration(
              color: PlixTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PlixTheme.cardBorder, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 20 : (isTv ? 28 : 28),
                      vertical: isCompact ? 16 : (isTv ? 16 : 20),
                    ),
                    decoration: BoxDecoration(
                      color: PlixTheme.background.withOpacity(0.5),
                      border: Border(bottom: BorderSide(color: PlixTheme.cardBorder)),
                    ),
                    child: Row(
                      children: [
                        PlixAppLogo(size: isTv ? 38 : 44, glow: true, borderRadius: 10),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  PlixWordmark(fontSize: isTv ? 22 : 24),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: PlixTheme.plexGold.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      isTv ? 'TV EDITION' : (isMobile ? 'MOBILE' : 'DESKTOP'),
                                      style: TextStyle(
                                        color: PlixTheme.plexGold,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isTv
                                    ? 'Welcome to your big-screen media client.'
                                    : (isMobile
                                        ? 'Welcome to your personal media player.'
                                        : 'Welcome to your desktop media client.'),
                                style: const TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Feature highlights:
                  // For TV: ALL features fit on screen at once in a 2x2 grid. NO scrolling list!
                  if (isTv)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildFeatureCard(
                                  icon: Icons.palette_rounded,
                                  accentColor: PlixTheme.plexGold,
                                  title: 'Atmosphere Themes & Styles',
                                  description:
                                      '16 atmosphere presets—from crystal Liquid Glass to Midnight, Aurora, and Abyssal Depth—plus custom accent colors.',
                                  isTv: true,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _buildFeatureCard(
                                  icon: Icons.dns_rounded,
                                  accentColor: const Color(0xFF8E51DC),
                                  title: 'Unified Multi-Server Experience',
                                  description:
                                      'Connect multiple Plex and Jellyfin servers simultaneously. Blend your favorite libraries and Continue Watching.',
                                  isTv: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildFeatureCard(
                                  icon: Icons.tv_rounded,
                                  accentColor: Colors.amberAccent,
                                  title: 'Living Room D-Pad Navigation',
                                  description:
                                      'Optimized directional remote controls with focus retention, quick scrub progress bar, and instant track selectors.',
                                  isTv: true,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _buildFeatureCard(
                                  icon: Icons.high_quality_rounded,
                                  accentColor: Colors.lightBlueAccent,
                                  title: '4K HDR & Direct Audio Passthrough',
                                  description:
                                      'Direct Play high-bitrate 4K HDR10 and Dolby Vision streams with bitstream audio passthrough for receiver surround sound.',
                                  isTv: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    // Mobile / Desktop: Clean column
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 20 : 28,
                          vertical: 20,
                        ),
                        child: Column(
                          children: [
                            _buildFeatureCard(
                              icon: Icons.palette_rounded,
                              accentColor: PlixTheme.plexGold,
                              title: 'Atmosphere Themes & Visual Styles',
                              description:
                                  'Customize your look with 16 atmosphere presets—from crystal Liquid Glass to Midnight, Aurora, and Abyssal Depth—plus custom accent colors.',
                            ),
                            const SizedBox(height: 14),
                            _buildFeatureCard(
                              icon: Icons.dns_rounded,
                              accentColor: const Color(0xFF8E51DC),
                              title: 'Unified Multi-Server Experience',
                              description:
                                  'Connect multiple Plex and Jellyfin servers simultaneously. Blend your favorite libraries and Continue Watching in one place.',
                            ),
                            const SizedBox(height: 14),
                            if (isMobile) ...[
                              _buildFeatureCard(
                                icon: Icons.swipe_vertical_rounded,
                                accentColor: Colors.cyanAccent,
                                title: 'Swipe Gestures for Brightness & Volume',
                                description:
                                    'Swipe vertically on the left side of the player to adjust screen brightness, and on the right side to adjust volume smoothly.',
                              ),
                              const SizedBox(height: 14),
                              _buildFeatureCard(
                                icon: Icons.picture_in_picture_alt_rounded,
                                accentColor: Colors.greenAccent,
                                title: 'Picture-in-Picture (PiP) Multitasking',
                                description:
                                    'Keep watching in a floating player overlay while browsing other apps or checking messages.',
                              ),
                            ] else ...[
                              _buildFeatureCard(
                                icon: Icons.keyboard_rounded,
                                accentColor: Colors.tealAccent,
                                title: 'Keyboard Shortcuts & Quick Controls',
                                description:
                                    'Full keyboard navigation, Spacebar play/pause, arrow scrubbing, and double-click fullscreen toggles.',
                              ),
                              const SizedBox(height: 14),
                              _buildFeatureCard(
                                icon: Icons.high_quality_rounded,
                                accentColor: Colors.deepPurpleAccent,
                                title: 'Direct Hardware Playback',
                                description:
                                    'Seamless hardware-accelerated playback supporting native direct streams and multi-codec audio channels.',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // Bottom Button with locked focus
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 20 : 28,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: PlixTheme.background.withOpacity(0.3),
                      border: Border(top: BorderSide(color: PlixTheme.cardBorder)),
                    ),
                    child: PlixButton(
                      focusNode: _getStartedFocusNode,
                      autofocus: true,
                      blockUp: true,
                      blockDown: true,
                      blockLeft: true,
                      blockRight: true,
                      label: 'Get Started',
                      isPrimary: true,
                      backgroundColor: PlixTheme.plexGold,
                      highlightColor: const Color(0xFFFFB82E),
                      borderColor: PlixTheme.plexGold,
                      textColor: Colors.black,
                      fontSize: 15,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String description,
    bool isTv = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isTv ? 12 : 14),
      decoration: BoxDecoration(
        color: PlixTheme.cardFocused.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PlixTheme.cardBorder.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: isTv ? 20 : 22),
          ),
          SizedBox(width: isTv ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: isTv ? 13 : 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: isTv ? 11.5 : 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
