import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plix_image_cache.dart';
import '../services/theme_music_service.dart';
import '../widgets/cast_row.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_button.dart';
import '../widgets/plix_bottom_nav.dart';
import '../services/plix_device_helper.dart';
import '../services/native_player_service.dart';
import 'person_screen.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final PlexMediaItem initialItem;
  final PlexServer server;
  final String clientId;
  final String? initialSeasonKey;
  final String? initialEpisodeKey;

  const DetailsScreen({
    super.key,
    required this.initialItem,
    this.initialSeasonKey,
    this.initialEpisodeKey,
    required this.server,
    required this.clientId,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> with WidgetsBindingObserver {
  final Object _screenToken = Object();
  late PlexMediaService _mediaService;
  late PlexMediaItem _item;
  PlexMediaItem? _trailerItem;

  // TV Show specific state
  List<PlexMediaItem> _seasons = [];
  PlexMediaItem? _selectedSeason;
  List<PlexMediaItem> _episodes = [];
  bool _isLoadingEpisodes = false;
  List<MediaPerson> _people = const [];

  final FocusNode _firstEpisodeFocusNode = FocusNode();
  final FocusNode _firstSeasonFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _homeButtonFocusNode = FocusNode();
  final FocusNode _firstActionFocusNode = FocusNode();
  final FocusNode _showPlayFocusNode = FocusNode();
  final FocusNode _firstCastFocusNode = FocusNode();
  final FocusNode _seasonDropdownFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _actionRowKey = GlobalKey();
  final Map<String, FocusNode> _seasonFocusNodes = {};
  final Map<String, FocusNode> _episodeFocusNodes = {};
  String? _lastPlayedEpisodeKey;
  bool _isAnyEpisodeFocused = false;
  bool _isOnWatchlist = false;
  bool _isUpdatingWatchlist = false;
  bool _isLoadingDetails = true;

  FocusNode? get _selectedSeasonFocusNode {
    if (_selectedSeason == null) return _firstSeasonFocusNode;
    if (_seasonFocusNodes.containsKey(_selectedSeason!.ratingKey)) {
      return _seasonFocusNodes[_selectedSeason!.ratingKey];
    }
    for (final s in _seasons) {
      if (s.key == _selectedSeason!.key || s.ratingKey == _selectedSeason!.ratingKey) {
        return _seasonFocusNodes[s.ratingKey];
      }
    }
    return _seasonFocusNodes.values.firstOrNull ?? _firstSeasonFocusNode;
  }

  void _focusSelectedSeason() {
    if (!mounted) return;
    if (PlixDeviceHelper.isCompact(context)) {
      _seasonDropdownFocusNode.requestFocus();
    } else {
      final node = _selectedSeasonFocusNode;
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      }
    }
    if (_scrollController.hasClients && !Platform.isWindows) {
      _scrollController.animateTo(
        260.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _switchSeasonRelative(int delta) {
    if (_selectedSeason == null || _seasons.isEmpty) return;
    final currentIndex = _seasons.indexWhere(
      (s) => s.ratingKey == _selectedSeason!.ratingKey || s.key == _selectedSeason!.key,
    );
    if (currentIndex == -1) return;
    final targetIndex = currentIndex + delta;
    if (targetIndex >= 0 && targetIndex < _seasons.length) {
      final newSeason = _seasons[targetIndex];
      _loadEpisodesForSeason(newSeason, focusFirstEpisode: true);
    }
  }

  double? _nativeThumbnailAspectRatio;

  void _resolveThumbnailAspectRatio() {
    if (!_item.isEpisode) return;
    final thumbPath = _item.thumb ?? _item.art;
    if (thumbPath == null || thumbPath.isEmpty) return;
    final url = _mediaService.buildImageUrl(thumbPath);
    if (url.isEmpty) return;
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted) return;
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) {
          final ratio = w / h;
          final is43 = ratio <= 1.5;
          final resolved = is43 ? (4.0 / 3.0) : (16.0 / 9.0);
          if (_nativeThumbnailAspectRatio != resolved) {
            setState(() {
              _nativeThumbnailAspectRatio = resolved;
            });
          }
        }
      },
      onError: (_, __) {},
    );
    stream.addListener(listener);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _item = widget.initialItem;
    _mediaService = PlexMediaService(server: widget.server);
    _resolveThumbnailAspectRatio();
    _loadFullDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startThemeIfAllowed();
    });
  }

  String get _showRatingKey {
    if (_item.isEpisode) {
      final gp = _item.grandparentRatingKey;
      if (gp != null && gp.isNotEmpty) {
        return ThemeMusicService.normalizeKey(gp);
      }
      return ThemeMusicService.normalizeKey(_item.ratingKey);
    }
    if (_item.isSeason) {
      final p = _item.parentRatingKey;
      if (p != null && p.isNotEmpty) return ThemeMusicService.normalizeKey(p);
      return ThemeMusicService.normalizeKey(_item.ratingKey);
    }
    return ThemeMusicService.normalizeKey(_item.ratingKey);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) _startThemeIfAllowed();
    } else {
      _stopTheme(immediate: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeMusicService.instance.unregisterScreen(_screenToken);
    _scrollController.dispose();
    _firstEpisodeFocusNode.dispose();
    _firstSeasonFocusNode.dispose();
    _seasonDropdownFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _homeButtonFocusNode.dispose();
    _firstActionFocusNode.dispose();
    _showPlayFocusNode.dispose();
    _firstCastFocusNode.dispose();
    for (final node in _seasonFocusNodes.values) {
      node.dispose();
    }
    for (final node in _episodeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _startThemeIfAllowed() async {
    if (!mounted || (!_item.isShow && !_item.isEpisode)) return;
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final showKey = _showRatingKey;
    ThemeMusicService.instance.registerScreen(_screenToken, showKey);

    if (_item.theme == null || _item.theme!.isEmpty) {
      if (_mediaService.server.isJellyfin) {
        final targetId = _showRatingKey;
        try {
          final jfThemeUrl = await _mediaService.fetchThemeMusicUrl(targetId);
          if (jfThemeUrl != null && jfThemeUrl.isNotEmpty) {
            _item = _item.copyWith(theme: jfThemeUrl);
          }
        } catch (_) {}
      } else if (_item.grandparentRatingKey != null) {
        try {
          final show = await _mediaService.getItemMetadata(_item.grandparentRatingKey!);
          if (show.theme != null && show.theme!.isNotEmpty) {
            _item = _item.copyWith(theme: show.theme);
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    final themePath = _item.theme;
    if (themePath == null || themePath.isEmpty) return;

    await ThemeMusicService.instance.playThemeForShow(
      showKey: showKey,
      themePath: themePath,
      mediaService: _mediaService,
      clientId: widget.clientId,
    );
  }

  void _stopTheme({bool immediate = false}) {
    if (immediate) {
      ThemeMusicService.instance.stopImmediate();
    } else {
      ThemeMusicService.instance.fadeOutAndStop();
    }
  }

  PlexMediaItem get _effectiveWatchlistItem {
    if (_item.isEpisode || _item.isSeason) {
      final showKey = _item.grandparentRatingKey ?? _item.parentRatingKey;
      final showTitle = _item.grandparentTitle ?? _item.parentTitle;
      if (showKey != null || showTitle != null) {
        return PlexMediaItem(
          ratingKey: showKey ?? _item.ratingKey,
          key: showKey != null ? '/library/metadata/$showKey' : _item.key,
          title: showTitle ?? _item.title,
          type: 'show',
          thumb: _item.grandparentThumb ?? _item.parentThumb ?? _item.thumb,
          art: _item.art,
          grandparentRatingKey: _item.grandparentRatingKey,
          grandparentGuid: _item.grandparentGuid,
          guid: _item.grandparentGuid,
          year: _item.year,
        );
      }
    }
    return _item;
  }

  Future<void> _loadFullDetails({bool restoreFocus = false}) async {
    setState(() => _isLoadingDetails = true);
    try {
      final full = await _mediaService.getItemMetadata(_item.ratingKey);
      if (mounted) {
        setState(() {
          _item = full;
        });
        _resolveThumbnailAspectRatio();
      }
    } catch (_) {}

    // If item does not have a partKey (e.g. opened from Plex Watchlist), search local server for match
    if (_item.partKey == null || _item.partKey!.isEmpty) {
      try {
        final searchResults = await _mediaService.search(_item.title);
        for (final r in searchResults) {
          final isSameType = (_item.isMovie && r.isMovie) || (_item.isShow && r.isShow);
          if (!isSameType) continue;

          bool isMatch = false;
          if (_item.guid != null && r.guid != null && _item.guid!.isNotEmpty && r.guid!.isNotEmpty) {
            final cleanW = _item.guid!.trim().toLowerCase().split('?').first;
            final cleanR = r.guid!.trim().toLowerCase().split('?').first;
            if (cleanW == cleanR) isMatch = true;
          }
          if (!isMatch && _item.title.trim().toLowerCase() == r.title.trim().toLowerCase()) {
            if (_item.year == null || r.year == null || _item.year == r.year) {
              isMatch = true;
            }
          }

          if (isMatch) {
            final localFull = await _mediaService.getItemMetadata(r.ratingKey);
            if (mounted) {
              setState(() {
                _item = localFull;
              });
            }
            break;
          }
        }
      } catch (_) {}
    }

    // Cast and crew metadata. Episodes often omit their own Role tags, so
    // fall back to the parent show's cast list.
    try {
      var people = _item.people;
      if (people.isEmpty && _item.isEpisode) {
        final showKey = _item.grandparentRatingKey;
        if (showKey != null && showKey.isNotEmpty) {
          final show = await _mediaService.getItemMetadata(showKey);
          people = show.people;
        }
      }
      if (mounted && people.isNotEmpty) {
        setState(() {
          _people = people;
        });
      }
    } catch (_) {}

    // If item is a movie, attempt to load trailer
    if (_item.isMovie) {
      try {
        final userToken = await PlexAuthService().getSavedToken() ?? widget.server.accessToken;
        final trailer = await _mediaService.getMovieTrailer(
          _item.ratingKey,
          guid: _item.guid,
          userToken: userToken,
        );
        if (mounted && trailer != null) {
          setState(() {
            _trailerItem = trailer.copyWith(
              title: trailer.title.toLowerCase().contains(_item.title.toLowerCase())
                  ? trailer.title
                  : '${_item.title} - ${trailer.title}',
            );
          });
        }
      } catch (_) {}
    }

    if (_item.isShow) {
      try {
        final seasons = await _mediaService.getShowSeasons(_item.ratingKey);
        if (mounted) {
          for (final s in seasons) {
            _seasonFocusNodes.putIfAbsent(s.ratingKey, () => FocusNode());
          }

          PlexMediaItem? targetSeason = _selectedSeason;
          if (targetSeason == null && seasons.isNotEmpty) {
            if (widget.initialSeasonKey != null) {
              targetSeason = seasons.firstWhere(
                (s) => s.ratingKey == widget.initialSeasonKey || s.key == widget.initialSeasonKey,
                orElse: () => seasons.first,
              );
            } else {
              targetSeason = seasons.firstWhere(
                (s) => (s.viewOffset != null && s.viewOffset! > 0) || (s.viewCount != null && s.viewCount! > 0),
                orElse: () => seasons.first,
              );
            }
          }

          setState(() {
            _seasons = seasons;
            _selectedSeason = targetSeason ?? (seasons.isNotEmpty ? seasons.first : null);
          });

          if (_selectedSeason != null) {
            final targetEpToFocus =
                widget.initialEpisodeKey ?? ((!Platform.isWindows && restoreFocus) ? _lastPlayedEpisodeKey : null);
            _loadEpisodesForSeason(
              _selectedSeason!,
              focusEpisodeKey: targetEpToFocus,
              focusFirstEpisode: widget.initialEpisodeKey != null,
            );
            if (targetEpToFocus == null && (Platform.isWindows || (!restoreFocus && _lastPlayedEpisodeKey == null))) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _showPlayFocusNode.canRequestFocus) {
                  _showPlayFocusNode.requestFocus();
                }
              });
            }
          }
        }
      } catch (_) {}
    }

    // Check if item is on Watchlist
    try {
      final userToken = await PlexAuthService().getSavedToken() ?? widget.server.accessToken;
      final inWatchlist = await _mediaService.isInWatchlist(
        item: _effectiveWatchlistItem,
        userToken: userToken,
      );
      if (mounted) {
        setState(() {
          _isOnWatchlist = inWatchlist;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
        if (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          _startThemeIfAllowed();
        }
      }
    }
  }

  void _openEpisodeDetails(PlexMediaItem episode) {
    _lastPlayedEpisodeKey = episode.ratingKey;
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: episode,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        _loadFullDetails(restoreFocus: true);
      }
    });
  }

  void _playTrailer() {
    NativePlayerService().stop();
    if (_trailerItem == null) return;
    _stopTheme(immediate: true);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: _trailerItem!,
          server: widget.server,
          clientId: widget.clientId,
          initialPositionMs: 0,
        ),
      ),
    )
        .then((_) {
      _startThemeIfAllowed();
    });
  }

  String get _showPlayLabel {
    if (_episodes.isNotEmpty) {
      final targetEp = _episodes.firstWhere(
        (e) => e.isInProgress || !e.isWatched,
        orElse: () => _episodes.first,
      );
      if (targetEp.parentIndex != null && targetEp.index != null) {
        return 'Play S${targetEp.parentIndex}:E${targetEp.index}';
      }
    }
    return 'Play';
  }

  void _playShow() async {
    if (_episodes.isNotEmpty) {
      final targetEp = _episodes.firstWhere(
        (e) => e.isInProgress || !e.isWatched,
        orElse: () => _episodes.first,
      );
      _playMedia(item: targetEp, resumeMs: targetEp.viewOffset ?? 0);
    } else if (_seasons.isNotEmpty) {
      try {
        final eps = await _mediaService.getSeasonEpisodes(
          _seasons.first.ratingKey,
          seasonKey: _seasons.first.key,
          showRatingKey: _item.ratingKey,
        );
        if (eps.isNotEmpty && mounted) {
          final targetEp = eps.firstWhere(
            (e) => e.isInProgress || !e.isWatched,
            orElse: () => eps.first,
          );
          _playMedia(item: targetEp, resumeMs: targetEp.viewOffset ?? 0);
        }
      } catch (_) {}
    }
  }

  Future<void> _loadEpisodesForSeason(
    PlexMediaItem season, {
    bool focusFirstEpisode = false,
    String? focusEpisodeKey,
  }) async {
    setState(() {
      _isLoadingEpisodes = true;
      _selectedSeason = season;
    });

    try {
      final eps = await _mediaService.getSeasonEpisodes(
        season.ratingKey,
        seasonKey: season.key,
        showRatingKey: _item.ratingKey,
      );
      if (mounted) {
        for (final ep in eps) {
          _episodeFocusNodes.putIfAbsent(ep.ratingKey, () => FocusNode());
        }

        setState(() {
          _episodes = eps;
          _isLoadingEpisodes = false;
        });

        if (focusEpisodeKey != null && _episodeFocusNodes.containsKey(focusEpisodeKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _episodeFocusNodes[focusEpisodeKey]?.canRequestFocus == true) {
              _episodeFocusNodes[focusEpisodeKey]?.requestFocus();
            }
          });
        } else if (focusFirstEpisode && eps.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusFirstEpisode();
          });
        }

        // Hydrate episodes in background to obtain full stream/dynamic HDR metadata
        final currentSeasonKey = season.ratingKey;
        _mediaService.getItemsMetadata(eps.map((e) => e.ratingKey).toList()).then((fullEps) {
          if (!mounted || _selectedSeason?.ratingKey != currentSeasonKey) return;
          if (fullEps.isEmpty) return;
          final fullMap = {for (final f in fullEps) f.ratingKey: f};
          bool changed = false;
          final updated = _episodes.map((ep) {
            final full = fullMap[ep.ratingKey];
            if (full != null) {
              if (ep.hdrBadge != full.hdrBadge ||
                  ep.isHdr != full.isHdr ||
                  ep.formattedResolution != full.formattedResolution) {
                changed = true;
              }
              return full;
            }
            return ep;
          }).toList();

          if (changed && mounted && _selectedSeason?.ratingKey == currentSeasonKey) {
            setState(() {
              _episodes = updated;
            });
          }
        }).catchError((_) {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _episodes = [];
          _isLoadingEpisodes = false;
        });
      }
    }
  }

  void _focusFirstEpisode() {
    if (_episodes.isNotEmpty) {
      final firstKey = _episodes.first.ratingKey;
      _episodeFocusNodes[firstKey]?.requestFocus();
    }
  }

  void _playMedia({required PlexMediaItem item, int resumeMs = 0}) {
    NativePlayerService().stop();
    _lastPlayedEpisodeKey = item.ratingKey;
    _stopTheme(immediate: true);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: item,
          server: widget.server,
          clientId: widget.clientId,
          initialPositionMs: resumeMs,
        ),
      ),
    )
        .then((_) {
      // Refresh details and restore cursor to the played episode
      _loadFullDetails(restoreFocus: true);
    });
  }

  void _openPerson(MediaPerson person) {
    _stopTheme();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => PersonScreen(
          person: person,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    )
        .then((_) {
      _startThemeIfAllowed();
    });
  }

  void _focusFirstCast() {
    if (_people.isNotEmpty) {
      _firstCastFocusNode.requestFocus();
    }
  }

  void _focusActionRowFromCast() {
    if (_item.isShow) {
      _showPlayFocusNode.requestFocus();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    _firstActionFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!PlixDeviceHelper.isCompact(context) && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final actionContext = _actionRowKey.currentContext;
      if (actionContext != null) {
        Scrollable.ensureVisible(
          actionContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _toggleWatched() async {
    final success = _item.isWatched
        ? await _mediaService.markUnwatched(_item.ratingKey)
        : await _mediaService.markWatched(_item.ratingKey);

    if (success && mounted) {
      setState(() {
        _item = _item.copyWith(
          viewCount: _item.isWatched ? 0 : 1,
          viewOffset: 0,
        );
      });
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 220,
        backgroundColor: Colors.black.withOpacity(0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.6), width: 1.5),
        ),
      ),
    );
  }

  Future<void> _toggleWatchlist() async {
    if (_isUpdatingWatchlist) return;
    setState(() {
      _isUpdatingWatchlist = true;
    });

    try {
      final userToken = await PlexAuthService().getSavedToken() ?? widget.server.accessToken;
      final willAdd = !_isOnWatchlist;
      final target = _effectiveWatchlistItem;
      final success = willAdd
          ? await _mediaService.addToWatchlist(item: target, userToken: userToken)
          : await _mediaService.removeFromWatchlist(item: target, userToken: userToken);

      if (mounted) {
        if (success) {
          setState(() {
            _isOnWatchlist = willAdd;
            _isUpdatingWatchlist = false;
          });
          _showToast(willAdd ? 'Added to Watchlist' : 'Removed from Watchlist');
        } else {
          setState(() {
            _isUpdatingWatchlist = false;
          });
          _showToast('Could not update Watchlist');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isUpdatingWatchlist = false;
        });
        _showToast('Failed to update Watchlist');
      }
    }
  }

  void _goToSeries() {
    final rawShowKey = _item.grandparentRatingKey;
    if (rawShowKey == null || rawShowKey.isEmpty) return;
    final showKey = ThemeMusicService.normalizeKey(rawShowKey);
    final seriesItem = PlexMediaItem(
      ratingKey: showKey,
      key: '/library/metadata/$showKey',
      title: _item.grandparentTitle ?? 'Show Details',
      type: 'show',
      thumb: _item.grandparentThumb,
      art: _item.art,
      theme: _item.theme,
    );
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: seriesItem,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        _startThemeIfAllowed();
      }
    });
  }

  bool get _isLandscapeArtwork => _item.isEpisode;

  String get _showTitleLine {
    final show = _item.grandparentTitle ?? '';
    if (!_item.isEpisode) return show;

    final season = _item.parentIndex;
    final episode = _item.index;
    String se = '';
    if (season != null && episode != null) {
      se = 'S$season:E$episode';
    } else if (season != null) {
      se = 'S$season';
    } else if (episode != null) {
      se = 'E$episode';
    }

    if (show.isNotEmpty && se.isNotEmpty) {
      return '$show - $se';
    }
    return show.isNotEmpty ? show : se;
  }

  bool get _isEpisode4by3 {
    if (!_item.isEpisode) return false;
    if (_nativeThumbnailAspectRatio != null) {
      return (_nativeThumbnailAspectRatio! - 4.0 / 3.0).abs() < 0.1;
    }
    if (_item.aspectRatio != null && _item.aspectRatio! < 1.5) return true;
    if (_item.videoWidth != null && _item.videoHeight != null && _item.videoHeight! > 0) {
      return (_item.videoWidth! / _item.videoHeight!) < 1.5;
    }
    return false;
  }

  double _artworkWidth(bool isCompact) {
    if (_item.isEpisode) {
      if (_isEpisode4by3) {
        return isCompact ? 190 : 230;
      }
      return isCompact ? 250 : 260;
    }
    return isCompact ? 140 : 180;
  }

  double get _artworkAspectRatio {
    if (_item.isEpisode) {
      return _isEpisode4by3 ? (4.0 / 3.0) : (16.0 / 9.0);
    }
    return 2.0 / 3.0;
  }

  Widget _buildArtwork({
    required String posterUrl,
    required double width,
    required double height,
    required int decodeWidth,
    required int decodeHeight,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: PlixTheme.card,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: posterUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: posterUrl,
                fit: BoxFit.cover,
                memCacheWidth: decodeWidth,
                memCacheHeight: decodeHeight,
              )
            : const Center(
                child: Icon(Icons.movie, size: 48, color: PlixTheme.textMuted),
              ),
      ),
    );
  }

  Widget _buildMobileOverview(
    BuildContext context,
    String posterUrl,
    double artworkWidth,
    double artworkHeight,
    int artworkDecodeWidth,
    int artworkDecodeHeight,
  ) {
    // Keep the still inside narrow phone layouts while preserving its aspect
    // ratio. Episode stills are landscape; movies and shows remain portrait.
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final displayWidth = availableWidth > 0 && availableWidth < artworkWidth ? availableWidth : artworkWidth;
    final displayHeight = displayWidth / _artworkAspectRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Center Artwork
        Center(
          child: _buildArtwork(
            posterUrl: posterUrl,
            width: displayWidth,
            height: displayHeight,
            decodeWidth: artworkDecodeWidth,
            decodeHeight: artworkDecodeHeight,
          ),
        ),

        const SizedBox(height: 18),

        // Title
        Text(
          _item.title,
          style: const TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),

        if (_showTitleLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _showTitleLine,
            style: TextStyle(
              color: PlixTheme.plexGold,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 10),

        // Metadata Badges
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_item.formattedAirDate.isNotEmpty) _Badge(label: _item.formattedAirDate),
            if (!_item.isShow && _item.duration != null && _item.duration! > 0) _Badge(label: _item.formattedDuration),
            if (_item.contentRating != null) _Badge(label: _item.contentRating!),
            if (_item.formattedResolution.isNotEmpty)
              _Badge(
                label: _item.formattedResolution,
                isHighlight: true,
              ),
            if (_item.isHdr)
              _Badge(
                label: _item.hdrBadge.isNotEmpty ? _item.hdrBadge : 'HDR10',
                isHighlight: true,
              ),
            if (_item.videoCodec != null) _Badge(label: _item.videoCodec!.toUpperCase()),
            if (_item.audioCodec != null) _Badge(label: _item.audioCodec!.toUpperCase()),
            if (_item.formattedBitrate.isNotEmpty) _Badge(label: _item.formattedBitrate),
          ],
        ),

        const SizedBox(height: 14),

        // Action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_item.isShow) ...[
              if (_item.isInProgress) ...[
                PlixButton(
                  autofocus: true,
                  focusNode: _firstActionFocusNode,
                  isPrimary: true,
                  fontSize: 13.0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: 'Resume',
                  onPressed: () => _playMedia(
                    item: _item,
                    resumeMs: _item.viewOffset!,
                  ),
                ),
                PlixButton(
                  isPrimary: false,
                  fontSize: 12.0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: 'Restart',
                  onPressed: () => _playMedia(item: _item, resumeMs: 0),
                ),
              ] else if (_item.partKey != null || _item.duration != null) ...[
                PlixButton(
                  autofocus: true,
                  focusNode: _firstActionFocusNode,
                  isPrimary: true,
                  fontSize: 13.0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: 'Play',
                  onPressed: () => _playMedia(item: _item, resumeMs: 0),
                ),
              ],
              if (_trailerItem != null)
                PlixButton(
                  isPrimary: false,
                  fontSize: 12.0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  icon: const Icon(Icons.theaters_rounded, size: 16),
                  label: 'Trailer',
                  onPressed: _playTrailer,
                ),
              PlixButton(
                isPrimary: false,
                fontSize: 12.0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                icon: _isUpdatingWatchlist
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : Icon(
                        _isOnWatchlist ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        size: 16,
                        color: _isOnWatchlist ? PlixTheme.plexGold : null,
                      ),
                label: _isOnWatchlist ? 'In Watchlist' : 'Watchlist',
                onPressed: _toggleWatchlist,
              ),
              PlixButton(
                isPrimary: false,
                fontSize: 12.0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                icon: Icon(
                  _item.isWatched ? Icons.remove_done_rounded : Icons.check_rounded,
                  size: 16,
                ),
                label: _item.isWatched ? 'Unwatch' : 'Mark Watched',
                blockRight: !(_item.isEpisode && _item.grandparentRatingKey != null && _item.grandparentRatingKey!.isNotEmpty),
                onDown: _focusFirstCast,
                onPressed: _toggleWatched,
              ),
              if (_item.isEpisode && _item.grandparentRatingKey != null && _item.grandparentRatingKey!.isNotEmpty)
                PlixButton(
                  isPrimary: false,
                  fontSize: 12.0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  icon: const Icon(Icons.tv_rounded, size: 16),
                  label: 'Series',
                  blockRight: true,
                  onDown: _focusFirstCast,
                  onPressed: _goToSeries,
                ),
            ] else ...[
              PlixButton(
                autofocus: true,
                focusNode: _showPlayFocusNode,
                isPrimary: true,
                fontSize: 13.0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: _showPlayLabel,
                onPressed: _playShow,
              ),
              PlixButton(
                isPrimary: false,
                fontSize: 12.0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                icon: _isUpdatingWatchlist
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : Icon(
                        _isOnWatchlist ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        size: 16,
                        color: _isOnWatchlist ? PlixTheme.plexGold : null,
                      ),
                label: _isOnWatchlist ? 'In Watchlist' : 'Watchlist',
                onPressed: _toggleWatchlist,
              ),
            ],
          ],
        ),

        const SizedBox(height: 14),

        // Summary
        Text(
          _item.summary.isNotEmpty ? _item.summary : 'No summary available.',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PlixTheme.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlixDeviceHelper.isTelevision;
    final isCompact = PlixDeviceHelper.isCompact(context);
    final backdropUrl = _mediaService.buildImageUrl(
      _item.art ?? _item.thumb,
      width: 1920,
      height: 1080,
    );
    final artworkWidth = _artworkWidth(isCompact);
    final artworkHeight = artworkWidth / _artworkAspectRatio;
    final posterUrl = _mediaService.buildImageUrl(
      _item.thumb ?? _item.art,
      width: _isLandscapeArtwork ? 960 : 400,
      height: _isLandscapeArtwork ? (_isEpisode4by3 ? 720 : 540) : 600,
    );
    final artworkDecodeWidth = PlixImageCache.decodeWidth(
      context,
      artworkWidth,
      cap: _isLandscapeArtwork ? 960 : 400,
    );
    final artworkDecodeHeight = PlixImageCache.decodeHeight(
      context,
      artworkHeight,
      cap: _isLandscapeArtwork ? (_isEpisode4by3 ? 720 : 540) : 600,
    );
    final backdropDecodeWidth = PlixImageCache.decodeWidth(
      context,
      MediaQuery.sizeOf(context).width,
      cap: PlixImageCache.backdropWidth,
    );
    final backdropDecodeHeight = PlixImageCache.decodeHeight(
      context,
      520,
      cap: PlixImageCache.backdropHeight,
    );

    final currentSeasonIdx = _seasons.indexWhere(
      (s) => s.ratingKey == _selectedSeason?.ratingKey || s.key == _selectedSeason?.key,
    );
    final canPrevSeason = currentSeasonIdx > 0;
    final canNextSeason = currentSeasonIdx >= 0 && currentSeasonIdx < _seasons.length - 1;

    return PopScope(
      canPop: !_isAnyEpisodeFocused,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _focusSelectedSeason();
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Fanart Backdrop with dark gradient
            if (backdropUrl.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 520,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: backdropDecodeWidth,
                      memCacheHeight: backdropDecodeHeight,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            PlixTheme.background.withOpacity(0.3),
                            PlixTheme.background.withOpacity(0.8),
                            PlixTheme.background,
                          ],
                          stops: const [0.0, 0.6, 1.0],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            PlixTheme.background.withOpacity(0.95),
                            PlixTheme.background.withOpacity(0.5),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4, 0.8],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Scrollable Content
            SafeArea(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.only(
                      left: isCompact ? 16 : 40,
                      right: isCompact ? 16 : 40,
                      top: isCompact ? 16 : 24,
                      bottom: 48,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back & Home buttons placed naturally at top of content so it scrolls away
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PlixBackButton(
                                focusNode: _backButtonFocusNode,
                                onRight: () => _homeButtonFocusNode.requestFocus(),
                                onDown: () {
                                  if (_item.isShow) {
                                    _showPlayFocusNode.requestFocus();
                                  } else {
                                    _firstActionFocusNode.requestFocus();
                                  }
                                },
                              ),
                              const SizedBox(width: 10),
                              PlixHomeButton(
                                focusNode: _homeButtonFocusNode,
                                onLeft: () => _backButtonFocusNode.requestFocus(),
                                onDown: () {
                                  if (_item.isShow) {
                                    _showPlayFocusNode.requestFocus();
                                  } else {
                                    _firstActionFocusNode.requestFocus();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        // Top Overview Block (Poster + Info + Actions)
                        if (isCompact)
                          _buildMobileOverview(
                            context,
                            posterUrl,
                            artworkWidth,
                            artworkHeight,
                            artworkDecodeWidth,
                            artworkDecodeHeight,
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Poster or episode still
                              _buildArtwork(
                                posterUrl: posterUrl,
                                width: artworkWidth,
                                height: artworkHeight,
                                decodeWidth: artworkDecodeWidth,
                                decodeHeight: artworkDecodeHeight,
                              ),

                              const SizedBox(width: 36),

                              // Details & Action Buttons
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _item.title,
                                      style: const TextStyle(
                                        color: PlixTheme.textPrimary,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    if (_showTitleLine.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _showTitleLine,
                                        style: TextStyle(
                                          color: PlixTheme.plexGold,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 12),

                                    // Metadata Badges (Year/Air Date, Duration, Rating, Video Res, HDR, Audio, Bitrate)
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (_item.formattedAirDate.isNotEmpty) _Badge(label: _item.formattedAirDate),
                                        if (!_item.isShow && _item.duration != null && _item.duration! > 0)
                                          _Badge(label: _item.formattedDuration),
                                        if (_item.contentRating != null) _Badge(label: _item.contentRating!),
                                        if (_item.formattedResolution.isNotEmpty)
                                          _Badge(
                                            label: _item.formattedResolution,
                                            isHighlight: true,
                                          ),
                                        if (_item.isHdr)
                                          _Badge(
                                            label: _item.hdrBadge.isNotEmpty ? _item.hdrBadge : 'HDR10',
                                            isHighlight: true,
                                          ),
                                        if (_item.videoCodec != null) _Badge(label: _item.videoCodec!.toUpperCase()),
                                        if (_item.audioCodec != null) _Badge(label: _item.audioCodec!.toUpperCase()),
                                        if (_item.formattedBitrate.isNotEmpty) _Badge(label: _item.formattedBitrate),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // Summary / Overview
                                    Text(
                                      _item.summary.isNotEmpty ? _item.summary : 'No summary available.',
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PlixTheme.textSecondary,
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Action buttons
                                    if (!_item.isShow) ...[
                                      KeyedSubtree(
                                        key: _actionRowKey,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                for (final Widget button in <Widget>[
                                              if (_item.isInProgress) ...[
                                                PlixButton(
                                                  autofocus: true,
                                                  focusNode: _firstActionFocusNode,
                                                  onLeft: () {},
                                                  onUp: () {
                                                    _backButtonFocusNode.requestFocus();
                                                    if (_scrollController.hasClients && !Platform.isWindows) {
                                                      _scrollController.animateTo(0.0,
                                                          duration: const Duration(milliseconds: 250),
                                                          curve: Curves.easeOutCubic);
                                                    }
                                                  },
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                  label: 'Resume',
                                                  onDown: _focusFirstCast,
                                                  onPressed: () => _playMedia(
                                                    item: _item,
                                                    resumeMs: _item.viewOffset!,
                                                  ),
                                                ),
                                                PlixButton(
                                                  onUp: () => _backButtonFocusNode.requestFocus(),
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.replay_rounded, size: 16),
                                                  label: 'Restart',
                                                  onDown: _focusFirstCast,
                                                  onPressed: () => _playMedia(item: _item, resumeMs: 0),
                                                ),
                                              ] else if (_item.partKey != null || _item.duration != null) ...[
                                                PlixButton(
                                                  autofocus: true,
                                                  focusNode: _firstActionFocusNode,
                                                  onLeft: () {},
                                                  onUp: () => _backButtonFocusNode.requestFocus(),
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                  label: 'Play',
                                                  onDown: _focusFirstCast,
                                                  onPressed: () => _playMedia(item: _item, resumeMs: 0),
                                                ),
                                              ] else ...[
                                                PlixButton(
                                                  autofocus: true,
                                                  focusNode: _firstActionFocusNode,
                                                  onLeft: () {},
                                                  onUp: () => _backButtonFocusNode.requestFocus(),
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.cloud_off_rounded, size: 16),
                                                  label: 'Not in Library',
                                                  onDown: _focusFirstCast,
                                                  onPressed: () {
                                                    ScaffoldMessenger.of(context).removeCurrentSnackBar();
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: const Text(
                                                          'This item is on your Plex Watchlist but not in this server\'s library.',
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(
                                                              color: Colors.white, fontWeight: FontWeight.bold),
                                                        ),
                                                        duration: const Duration(seconds: 3),
                                                        behavior: SnackBarBehavior.floating,
                                                        width: 340,
                                                        backgroundColor: PlixTheme.surface,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(10),
                                                          side: const BorderSide(color: Colors.white24),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                              if (_trailerItem != null) ...[
                                                PlixButton(
                                                  onUp: () => _backButtonFocusNode.requestFocus(),
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.theaters_rounded, size: 16),
                                                  label: 'Trailer',
                                                  onDown: _focusFirstCast,
                                                  onPressed: _playTrailer,
                                                ),
                                              ],
                                              PlixButton(
                                                onUp: () => _backButtonFocusNode.requestFocus(),
                                                isPrimary: false,
                                                fontSize: 12.0,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                icon: _isUpdatingWatchlist
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                            strokeWidth: 2, color: Colors.white70),
                                                      )
                                                    : Icon(
                                                        _isOnWatchlist
                                                            ? Icons.bookmark_added_rounded
                                                            : Icons.bookmark_add_outlined,
                                                        size: 16,
                                                        color: _isOnWatchlist ? PlixTheme.plexGold : null,
                                                      ),
                                                label: _isOnWatchlist ? 'In Watchlist' : 'Watchlist',
                                                onDown: _focusFirstCast,
                                                onPressed: _toggleWatchlist,
                                              ),
                                              PlixButton(
                                                onUp: () => _backButtonFocusNode.requestFocus(),
                                                isPrimary: false,
                                                fontSize: 12.0,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                icon: Icon(
                                                  _item.isWatched ? Icons.remove_done_rounded : Icons.check_rounded,
                                                  size: 16,
                                                ),
                                                label: _item.isWatched ? 'Unwatch' : 'Mark Watched',
                                                blockRight: !(_item.isEpisode &&
                                                    _item.grandparentRatingKey != null &&
                                                    _item.grandparentRatingKey!.isNotEmpty),
                                                onDown: _focusFirstCast,
                                                onPressed: _toggleWatched,
                                              ),
                                              if (_item.isEpisode &&
                                                  _item.grandparentRatingKey != null &&
                                                  _item.grandparentRatingKey!.isNotEmpty) ...[
                                                PlixButton(
                                                  onUp: () => _backButtonFocusNode.requestFocus(),
                                                  isPrimary: false,
                                                  fontSize: 12.0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  icon: const Icon(Icons.tv_rounded, size: 16),
                                                  label: 'Series',
                                                  blockRight: true,
                                                  onDown: _focusFirstCast,
                                                  onPressed: _goToSeries,
                                                ),
                                              ],
                                            ])
                                              IntrinsicWidth(child: button),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      Row(
                                        children: [
                                          PlixButton(
                                            autofocus: true,
                                            focusNode: _showPlayFocusNode,
                                            onLeft: () {},
                                            onUp: () => _backButtonFocusNode.requestFocus(),
                                            onDown: _focusSelectedSeason,
                                            isPrimary: false,
                                            fontSize: 12.0,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                            label: _showPlayLabel,
                                            onPressed: _playShow,
                                          ),
                                          const SizedBox(width: 10),
                                          PlixButton(
                                            onUp: () => _backButtonFocusNode.requestFocus(),
                                            onDown: _focusSelectedSeason,
                                            isPrimary: false,
                                            fontSize: 12.0,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            icon: _isUpdatingWatchlist
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                        strokeWidth: 2, color: Colors.white70),
                                                  )
                                                : Icon(
                                                    _isOnWatchlist
                                                        ? Icons.bookmark_added_rounded
                                                        : Icons.bookmark_add_outlined,
                                                    size: 18,
                                                    color: _isOnWatchlist ? PlixTheme.plexGold : null,
                                                  ),
                                            label: _isOnWatchlist ? 'In Watchlist' : 'Watchlist',
                                            onPressed: _toggleWatchlist,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),

                  // Cast & Crew (movies and episodes). Shows have their own
                  // season/episode list below.
                  if ((_item.isMovie || _item.isEpisode) && _people.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    CastRow(
                      firstFocusNode: _firstCastFocusNode,
                      people: _people,
                      mediaService: _mediaService,
                      onPersonTap: _openPerson,
                      onUp: _focusActionRowFromCast,
                    ),
                  ],

                  // TV Show Seasons & Episodes Section
                  if (_item.isShow) ...[
                    const SizedBox(height: 36),
                    Divider(color: PlixTheme.cardBorder),
                    const SizedBox(height: 16),

                    // Season Chips
                    if (_isLoadingDetails && _seasons.isEmpty) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36.0),
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                          ),
                        ),
                      ),
                    ] else if (_seasons.isNotEmpty) ...[
                      const Text(
                        'Seasons',
                        style: TextStyle(
                          color: PlixTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isCompact)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: PlixTheme.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: PlixTheme.cardBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              focusNode: _seasonDropdownFocusNode,
                              value: _seasons.any((s) => s.ratingKey == _selectedSeason?.ratingKey)
                                  ? _selectedSeason!.ratingKey
                                  : _seasons.first.ratingKey,
                              isExpanded: true,
                              isDense: true,
                              borderRadius: BorderRadius.circular(10),
                              dropdownColor: PlixTheme.surface,
                              icon: Icon(Icons.arrow_drop_down_rounded, color: PlixTheme.plexGold),
                              style: const TextStyle(
                                color: PlixTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              items: _seasons
                                  .map(
                                    (season) => DropdownMenuItem<String>(
                                      value: season.ratingKey,
                                      child: Text(
                                        season.title,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (ratingKey) {
                                if (ratingKey == null) return;
                                final season = _seasons.firstWhere(
                                  (s) => s.ratingKey == ratingKey,
                                );
                                _loadEpisodesForSeason(season);
                              },
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _seasons.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final season = _seasons[index];
                              final isSel = _selectedSeason?.ratingKey == season.ratingKey ||
                                  (_selectedSeason?.key.isNotEmpty == true && _selectedSeason?.key == season.key);
                              return PlixButton(
                                focusNode: _seasonFocusNodes[season.ratingKey],
                                onUp: () {
                                  _showPlayFocusNode.requestFocus();
                                  if (_scrollController.hasClients && !Platform.isWindows) {
                                    _scrollController.animateTo(
                                      0.0,
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                },
                                onDown: _focusFirstEpisode,
                                label: season.title,
                                isPrimary: isSel,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                onPressed: () => _loadEpisodesForSeason(
                                  season,
                                  focusFirstEpisode: true,
                                ),
                              );
                            },
                          ),
                        ),
                    ],

                    const SizedBox(height: 24),

                    // Episodes List
                    Builder(
                      builder: (context) {
                        final currentSeasonIdx = _seasons.indexWhere(
                          (s) => s.ratingKey == _selectedSeason?.ratingKey || s.key == _selectedSeason?.key,
                        );
                        final canPrevSeason = currentSeasonIdx > 0;
                        final canNextSeason = currentSeasonIdx >= 0 && currentSeasonIdx < _seasons.length - 1;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Episodes',
                                  style: TextStyle(
                                    color: PlixTheme.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                if (_seasons.length > 1 && !isCompact) ...[
                                  Opacity(
                                    opacity: canPrevSeason ? 1.0 : 0.35,
                                    child: Row(
                                      children: [
                                        Icon(Icons.arrow_left_rounded, color: PlixTheme.plexGold, size: 22),
                                        Text(
                                          canPrevSeason ? _seasons[currentSeasonIdx - 1].title : 'First Season',
                                          style: const TextStyle(
                                            color: PlixTheme.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Opacity(
                                    opacity: canNextSeason ? 1.0 : 0.35,
                                    child: Row(
                                      children: [
                                        Text(
                                          canNextSeason ? _seasons[currentSeasonIdx + 1].title : 'Last Season',
                                          style: const TextStyle(
                                            color: PlixTheme.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Icon(Icons.arrow_right_rounded, color: PlixTheme.plexGold, size: 22),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (_isLoadingEpisodes)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                                  ),
                                ),
                              )
                            else if (_episodes.isEmpty)
                              const Text(
                                'No episodes available for this season.',
                                style: TextStyle(color: PlixTheme.textSecondary),
                              )
                            else
                              Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onFocusChange: (hasEpisodeFocus) {
                                  if (mounted && _isAnyEpisodeFocused != hasEpisodeFocus) {
                                    setState(() {
                                      _isAnyEpisodeFocused = hasEpisodeFocus;
                                    });
                                  }
                                },
                                      child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _episodes.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final ep = _episodes[index];
                                  final epThumb = _mediaService.buildImageUrl(
                                    ep.thumb ?? _item.art,
                                    width: 280,
                                    height: 160,
                                  );

                                  final prevKey = index > 0 ? _episodes[index - 1].ratingKey : null;
                                          final nextKey =
                                              index < _episodes.length - 1 ? _episodes[index + 1].ratingKey : null;

                                  return _EpisodeTile(
                                    focusNode: _episodeFocusNodes[ep.ratingKey],
                                    onUp: index == 0
                                        ? _focusSelectedSeason
                                        : () => _episodeFocusNodes[prevKey]?.requestFocus(),
                                    onDown: nextKey != null
                                        ? () => _episodeFocusNodes[nextKey]?.requestFocus()
                                        : null,
                                    onBack: _focusSelectedSeason,
                                    onLeft: canPrevSeason ? () => _switchSeasonRelative(-1) : null,
                                    onRight: canNextSeason ? () => _switchSeasonRelative(1) : null,
                                    onFocusChanged: (focused) {
                                      if (focused != _isAnyEpisodeFocused) {
                                        setState(() {
                                          _isAnyEpisodeFocused = focused;
                                        });
                                      }
                                    },
                                    episode: ep,
                                    episodeIndex: index + 1,
                                    seasonIndex: _selectedSeason?.index,
                                    epThumb: epThumb,
                                    onSelect: () => _openEpisodeDetails(ep),
                                  );
                                },
                              ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            // Left & Right Season Side Chevrons (sleek, no circle, shown only when episode list focused)
            if (_item.isShow && _seasons.length > 1 && !isCompact) ...[
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                            opacity: ((_isAnyEpisodeFocused || _episodeFocusNodes.values.any((n) => n.hasFocus)) &&
                                    canPrevSeason)
                                ? 0.9
                                : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: PlixTheme.plexGold,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                            opacity: ((_isAnyEpisodeFocused || _episodeFocusNodes.values.any((n) => n.hasFocus)) &&
                                    canNextSeason)
                                ? 0.9
                                : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: PlixTheme.plexGold,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  ),
),
);
  }
}

class _EpisodeTile extends StatefulWidget {
  final PlexMediaItem episode;
  final int episodeIndex;
  final int? seasonIndex;
  final String epThumb;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onBack;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final ValueChanged<bool>? onFocusChanged;

  const _EpisodeTile({
    required this.episode,
    required this.episodeIndex,
    this.seasonIndex,
    required this.epThumb,
    required this.onSelect,
    this.focusNode,
    this.onUp,
    this.onDown,
    this.onBack,
    this.onLeft,
    this.onRight,
    this.onFocusChanged,
  });

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
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
      widget.onFocusChanged?.call(_focusNode.hasFocus);
      if (_focusNode.hasFocus) {
        if (!Platform.isWindows || HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.3,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
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
    final ep = widget.episode;
    final isHighlighted = _isFocused || _isHovered;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
            widget.onDown!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) {
            if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
              widget.onLeft!();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
              widget.onRight!();
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent && (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack)) {
            if (widget.onBack != null) {
              widget.onBack!();
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
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
      child: AnimatedScale(
        scale: isHighlighted ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onSelect,
          onHover: (hovered) {
            if (Platform.isWindows && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlighted ? PlixTheme.cardFocused : PlixTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHighlighted ? PlixTheme.plexGold : PlixTheme.cardBorder,
                width: isHighlighted ? 2.0 : 1.0,
              ),
              boxShadow: isHighlighted
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode thumbnail
                Container(
                  width: 140,
                  height: 80,
                  decoration: BoxDecoration(
                    color: PlixTheme.card,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.epThumb.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: widget.epThumb,
                            fit: BoxFit.cover,
                            memCacheWidth: PlixImageCache.decodeWidth(context, 140, cap: 280),
                            memCacheHeight: PlixImageCache.decodeHeight(context, 80, cap: 160),
                          ),
                        if (ep.isInProgress)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: ep.progressPercentage,
                              backgroundColor: Colors.black,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                PlixTheme.plexGold,
                              ),
                              minHeight: 3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Episode details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ep.title.isNotEmpty ? ep.title : 'Episode ${ep.index ?? widget.episodeIndex}',
                              style: TextStyle(
                                color: isHighlighted ? PlixTheme.plexGold : PlixTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (ep.isWatched) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_circle,
                              color: PlixTheme.plexGold,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Builder(
                        builder: (ctx) {
                          final isPortraitMode = PlixDeviceHelper.isPortrait(ctx) || PlixDeviceHelper.isCompact(ctx);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'S${ep.parentIndex ?? widget.seasonIndex ?? 1}:E${ep.index ?? widget.episodeIndex}',
                                    style: TextStyle(
                                      color: isHighlighted ? PlixTheme.plexGold : PlixTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (ep.formattedAirDate.isNotEmpty ||
                                      (ep.duration != null && ep.duration! > 0) ||
                                      (!isPortraitMode && ep.formattedResolution.isNotEmpty))
                                    const Text(
                                      '  •  ',
                                      style: TextStyle(
                                        color: PlixTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (ep.formattedAirDate.isNotEmpty) ...[
                                    Text(
                                      ep.formattedAirDate,
                                      style: const TextStyle(
                                        color: PlixTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (ep.duration != null && ep.duration! > 0)
                                      const Text(
                                        '  •  ',
                                        style: TextStyle(
                                          color: PlixTheme.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                  if (ep.duration != null && ep.duration! > 0) ...[
                                    Text(
                                      ep.formattedDuration,
                                      style: const TextStyle(
                                        color: PlixTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (!isPortraitMode && ep.formattedResolution.isNotEmpty) ...[
                                    if (ep.formattedAirDate.isNotEmpty || (ep.duration != null && ep.duration! > 0))
                                      const Text(
                                        '  •  ',
                                        style: TextStyle(
                                          color: PlixTheme.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        ep.formattedResolution,
                                        style: const TextStyle(
                                          color: PlixTheme.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (!isPortraitMode && ep.isHdr) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: PlixTheme.plexGold.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: PlixTheme.plexGold.withOpacity(0.6),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Text(
                                        ep.hdrBadge.isNotEmpty ? ep.hdrBadge : 'HDR10',
                                        style: TextStyle(
                                          color: PlixTheme.plexGold,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (isPortraitMode && (ep.formattedResolution.isNotEmpty || ep.isHdr)) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    if (ep.formattedResolution.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          ep.formattedResolution,
                                          style: const TextStyle(
                                            color: PlixTheme.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    if (ep.isHdr) ...[
                                      if (ep.formattedResolution.isNotEmpty) const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: PlixTheme.plexGold.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                            color: PlixTheme.plexGold.withOpacity(0.6),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Text(
                                          ep.hdrBadge.isNotEmpty ? ep.hdrBadge : 'HDR10',
                                          style: TextStyle(
                                            color: PlixTheme.plexGold,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ep.summary.isNotEmpty ? ep.summary : 'No episode description.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

class _Badge extends StatelessWidget {
  final String label;
  final bool isHighlight;

  const _Badge({
    required this.label,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight ? PlixTheme.plexGold.withOpacity(0.2) : PlixTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHighlight ? PlixTheme.plexGold : PlixTheme.cardBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isHighlight ? PlixTheme.plexGold : PlixTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
