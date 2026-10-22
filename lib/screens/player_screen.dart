import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/media_button_service.dart';
import '../services/native_player_service.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_timeline_service.dart';
import '../services/plix_device_helper.dart';
import '../services/plix_image_cache.dart';
import '../services/subtitle_parser.dart';
import '../services/theme_music_service.dart';
import '../services/update_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_button.dart';
import 'details_screen.dart';

class VideoQualityOption {
  final String label;
  final String resolution;
  final int bitrateKbps;
  final bool isDirectPlay;

  const VideoQualityOption({
    required this.label,
    required this.resolution,
    required this.bitrateKbps,
    this.isDirectPlay = false,
  });

  static const directPlay = VideoQualityOption(
    label: 'Original (Direct Play)',
    resolution: '',
    bitrateKbps: 0,
    isDirectPlay: true,
  );

  static const directStream = VideoQualityOption(
    label: 'Direct Stream Video (Transcode Audio)',
    resolution: '',
    bitrateKbps: 0,
    isDirectPlay: false,
  );

  static const List<VideoQualityOption> presets = [
    directPlay,
    directStream,
    VideoQualityOption(label: '1080p (20 Mbps)', resolution: '1920x1080', bitrateKbps: 20000),
    VideoQualityOption(label: '1080p (12 Mbps)', resolution: '1920x1080', bitrateKbps: 12000),
    VideoQualityOption(label: '1080p (8 Mbps)', resolution: '1920x1080', bitrateKbps: 8000),
    VideoQualityOption(label: '720p (4 Mbps)', resolution: '1280x720', bitrateKbps: 4000),
    VideoQualityOption(label: '720p (2 Mbps)', resolution: '1280x720', bitrateKbps: 2000),
    VideoQualityOption(label: '480p (1.5 Mbps)', resolution: '720x480', bitrateKbps: 1500),
  ];
}

enum _OrientationLock { none, lockedLandscape, lockedPortrait }

class PlayerScreen extends StatefulWidget {
  final PlexMediaItem item;
  final PlexServer server;
  final String clientId;
  final int initialPositionMs;

  const PlayerScreen({
    super.key,
    required this.item,
    required this.server,
    required this.clientId,
    this.initialPositionMs = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final NativePlayerService _nativePlayer = NativePlayerService();
  late PlexTimelineService _timelineService;
  late PlexMediaService _mediaService;
  final MediaButtonService _mediaButtonService = MediaButtonService();

  Map<String, String> get _playHeaders {
    if (widget.server.isJellyfin) {
      return {
        'Authorization': 'MediaBrowser Client="${PlixDeviceHelper.clientName}", Device="${PlixDeviceHelper.deviceName}", DeviceId="${widget.clientId}", Version="${UpdateService.currentVersion}", Token="${widget.server.accessToken}"',
      };
    }
    return {
      'X-Plex-Token': widget.server.accessToken,
      'X-Plex-Client-Identifier': widget.clientId,
      'X-Plex-Product': PlixDeviceHelper.clientName,
      'X-Plex-Device': PlixDeviceHelper.clientDevice,
      'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
      'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
      'X-Plex-Version': UpdateService.currentVersion,
    };
  }

  late PlexMediaItem _currentItem;
  StreamSubscription<MediaKeyAction>? _mediaKeySub;
  StreamSubscription<int>? _posSub;
  StreamSubscription<int>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<void>? _endedSub;
  StreamSubscription<String>? _subCueSub;

  Timer? _hideControlsTimer;
  Timer? _centerFeedbackTimer;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _currentPositionMs = 0;
  int _durationMs = 0;
  int _streamOffsetMs = 0;

  bool _showControls = true;
  bool _hasError = false;
  String _errorMessage = '';
  IconData? _centerFeedbackIcon;
  String? _centerFeedbackText;
  int _accumulatedSeekSeconds = 0;
  Timer? _seekDebounceTimer;
  bool _isSwitchingQuality = false;

  // Subtitles state
  PlexSubtitleStream? _selectedSubtitle;
  List<SubtitleCue> _subtitleCues = [];
  String _currentSubtitleText = '';
  Uint8List? _subtitleBitmapBytes;
  StreamSubscription<Uint8List?>? _subBitmapSub;

  // Audio track state
  PlexAudioStream? _selectedAudio;
  bool _audioNeedsTranscode = false;
  bool _forceAudioForSpeed = false;

  // Quality state
  VideoQualityOption _selectedQuality = VideoQualityOption.directPlay;

  // Preferences
  bool _autoplayEnabled = true;
  int _quickRewindSeconds = 10;
  int _skipAheadSeconds = 30;

  // Autoplay countdown state
  // Quick Seek progress bar state
  bool _isQuickSeeking = false;
  Timer? _quickSeekHideTimer;

  // Skip Intro state
  bool _autoSkipIntro = false;
  bool _hasAutoSkippedIntro = false;
  bool _showSkipIntroButton = false;
  final FocusNode _skipIntroFocusNode = FocusNode();

  bool _isAutoplayCountdownActive = false;
  int _autoplayCountdownSeconds = 5;
  Timer? _autoplayTimer;
  PlexMediaItem? _previousEpisodeItem;
  PlexMediaItem? _nextEpisodeItem;
  final FocusNode _autoplayPlayNowFocusNode = FocusNode();
  final FocusNode _autoplayCancelFocusNode = FocusNode();

  final FocusNode _playerFocusNode = FocusNode();
  final FocusNode _backBtnFocusNode = FocusNode();
  final FocusNode _scrubberFocusNode = FocusNode();
  bool _isScrubberFocused = false;
  final FocusNode _playPauseBtnFocusNode = FocusNode();
  final FocusNode _prevEpBtnFocusNode = FocusNode();
  final FocusNode _nextEpBtnFocusNode = FocusNode();
  final FocusNode _subtitleBtnFocusNode = FocusNode();
  final FocusNode _audioBtnFocusNode = FocusNode();
  final FocusNode _qualityBtnFocusNode = FocusNode();
  final FocusNode _seriesBtnFocusNode = FocusNode();
  final FocusNode _fullscreenBtnFocusNode = FocusNode();
  final FocusNode _speedBtnFocusNode = FocusNode();
  bool _isBuffering = false;
  StreamSubscription<bool>? _bufferingSub;
  Orientation? _lastAppliedOrientation;
  bool _isInPip = false;
  StreamSubscription<bool>? _pipSub;
  _OrientationLock _orientationLock = _OrientationLock.none;
  StreamSubscription<String>? _physicalOrientationSub;
  double _playbackSpeed = 1.0;
  List<PlexMediaItem> _portraitSeasonEpisodes = [];
  bool _isLoadingPortraitEpisodes = false;
  bool _isOnWatchlist = false;
  bool _isUpdatingWatchlist = false;
  bool _isFullScreen = false;
  StreamSubscription<String?>? _serverStopSubscription;

  @override
  void initState() {
    super.initState();
    ThemeMusicService.instance.stopImmediate();
    _currentItem = widget.item;
    if (_currentItem.isTrailer) {
      _selectedQuality = VideoQualityOption.directStream;
    }
    _currentPositionMs = widget.initialPositionMs;
    _mediaService = PlexMediaService(server: widget.server);
    _timelineService = PlexTimelineService(
      server: widget.server,
      clientId: widget.clientId,
    );

    _serverStopSubscription = _timelineService.onServerStop.listen((reason) {
      if (mounted) {
        _handleServerStop(reason);
      }
    });

    if (Platform.isWindows) {
      windowManager.isFullScreen().then((val) {
        if (mounted) setState(() => _isFullScreen = val);
      });
    }

    _loadPlayerPreferences();

    // Register active player with native Button Remapper handler
    _mediaButtonService.setPlayerActive(true);
    _mediaKeySub = _mediaButtonService.onMediaAction.listen(_handleNativeMediaKey);
    HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);

    _scrubberFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isScrubberFocused = _scrubberFocusNode.hasFocus;
        });
        if (_scrubberFocusNode.hasFocus) {
          _scheduleHideControls();
        }
      }
    });

    // Subscribe to native player events
    _posSub = _nativePlayer.onPositionUpdate.listen(_onPositionUpdate);
    _durSub = _nativePlayer.onDurationReady.listen((dur) {
      if (mounted && dur > 0) {
        if (_durationMs <= 0 || _currentItem.duration == null || _currentItem.duration! <= 0) {
          setState(() => _durationMs = dur);
        }
      }
    });
    _playSub = _nativePlayer.onIsPlayingChanged.distinct().listen((playing) {
      if (mounted) {
        if (_isPlaying != playing) {
          setState(() {
            _isPlaying = playing;
            if (playing) {
              _isPaused = false;
            }
          });
        }
        if (playing && !_isPaused && _showControls) {
          _scheduleHideControls();
        }
      }
    });
    _errSub = _nativePlayer.onPlayerError.listen((err) {
      if (mounted) {
        final lower = err.toLowerCase();
        final isBenign = lower.contains('ffurl_read') ||
            lower.contains('tcp:') ||
            lower.contains('demux') ||
            lower.contains('protocol') ||
            lower.contains('buffering') ||
            lower.contains('seek');
        if (isBenign && _isPlaying) {
          return;
        }
        setState(() {
          _hasError = true;
          _errorMessage = err;
        });
      }
    });
    _subCueSub = _nativePlayer.onSubtitleCue.listen((cueText) {
      if (mounted && _selectedSubtitle != null && _subtitleCues.isEmpty) {
        if (_currentSubtitleText != cueText) {
          setState(() {
            _currentSubtitleText = cueText;
          });
        }
      }
    });
    _bufferingSub = _nativePlayer.onBufferingChanged.listen((isBuffering) {
      if (mounted && _isBuffering != isBuffering) {
        setState(() {
          _isBuffering = isBuffering;
        });
      }
    });
    _subBitmapSub = _nativePlayer.onSubtitleBitmapCue.listen((bytes) {
      if (mounted && _selectedSubtitle != null) {
        if (_subtitleBitmapBytes != bytes) {
          setState(() {
            _subtitleBitmapBytes = bytes;
          });
        }
      }
    });
    _endedSub = _nativePlayer.onPlayerEnded.listen((_) {
      if (mounted) {
        _handlePlaybackEnded();
      }
    });

    _pipSub = _nativePlayer.onPipModeChanged.listen((inPip) {
      if (mounted) {
        setState(() {
          _isInPip = inPip;
          if (inPip) {
            _showControls = false;
          }
        });
      }
    });

    _physicalOrientationSub = _nativePlayer.onDevicePhysicalOrientationChanged.listen((orient) {
      if (!mounted) return;
      if (_orientationLock == _OrientationLock.lockedLandscape && orient == 'landscape') {
        setState(() {
          _orientationLock = _OrientationLock.none;
        });
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (_orientationLock == _OrientationLock.lockedPortrait && orient == 'portrait') {
        setState(() {
          _orientationLock = _OrientationLock.none;
        });
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
    _initPlayer();
    _fetchAdjacentEpisodes();
    _loadPortraitSeasonEpisodes();
    _checkWatchlist();

    if (!Platform.isWindows && !PlixDeviceHelper.isTelevision) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls && _playPauseBtnFocusNode.canRequestFocus) {
        _playPauseBtnFocusNode.requestFocus();
      }
    });
  }

  Future<void> _loadPlayerPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoplayEnabled = prefs.getBool('autoplay_next_episode') ?? true;
          _autoSkipIntro = prefs.getBool('auto_skip_intro') ?? false;
          _quickRewindSeconds = prefs.getInt('quick_rewind_seconds') ?? 10;
          _skipAheadSeconds = prefs.getInt('skip_ahead_seconds') ?? 30;
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePlaybackEnded() async {
    _timelineService.stop(_currentPositionMs);

    if (_autoplayEnabled && _currentItem.isEpisode) {
      final nextEp = _nextEpisodeItem ?? await _mediaService.getNextEpisode(_currentItem);
      if (nextEp != null && mounted) {
        setState(() {
          _nextEpisodeItem = nextEp;
          _isAutoplayCountdownActive = true;
          _autoplayCountdownSeconds = 5;
          _showControls = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoplayPlayNowFocusNode.canRequestFocus) {
            _autoplayPlayNowFocusNode.requestFocus();
          }
        });

        _autoplayTimer?.cancel();
        _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_autoplayCountdownSeconds > 1) {
            setState(() {
              _autoplayCountdownSeconds--;
            });
          } else {
            timer.cancel();
            _startNextEpisode();
          }
        });
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _skipIntro() {
    final intro = _currentItem.introMarker;
    if (intro != null) {
      _seekToTarget(intro.endTimeOffset);
      setState(() {
        _showSkipIntroButton = false;
      });
      _playerFocusNode.requestFocus();
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
        width: 200,
        backgroundColor: Colors.black.withOpacity(0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.6), width: 1.5),
        ),
      ),
    );
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    setState(() {
      _isAutoplayCountdownActive = false;
      _nextEpisodeItem = null;
    });
    Navigator.of(context).maybePop();
  }

  Future<void> _fetchAdjacentEpisodes() async {
    if (!_currentItem.isEpisode) {
      if (mounted) {
        setState(() {
          _previousEpisodeItem = null;
          _nextEpisodeItem = null;
        });
      }
      return;
    }

    var item = _currentItem;
    if (item.parentRatingKey == null || item.parentRatingKey!.isEmpty) {
      try {
        final fullItem = await _mediaService.getItemMetadata(item.ratingKey);
        if (mounted && _currentItem.ratingKey == item.ratingKey) {
          _currentItem = fullItem;
          item = fullItem;
        }
      } catch (_) {}
    }

    final results = await Future.wait([
      _mediaService.getPreviousEpisode(item),
      _mediaService.getNextEpisode(item),
    ]);

    if (mounted && _currentItem.ratingKey == item.ratingKey) {
      setState(() {
        _previousEpisodeItem = results[0];
        _nextEpisodeItem = results[1];
      });
    }
  }

  void _playEpisode(PlexMediaItem ep) {
    _autoplayTimer?.cancel();
    _timelineService.stop(_currentPositionMs);
    _nativePlayer.stop();

    setState(() {
      _showControls = true;
      _isAutoplayCountdownActive = false;
      _nextEpisodeItem = null;
      _previousEpisodeItem = null;
      _currentItem = ep;
      _currentPositionMs = 0;
      _streamOffsetMs = 0;
      _durationMs = ep.duration ?? 0;
      _isInitialized = false;
      _isPlaying = true;
      _isPaused = false;
      _hasError = false;
      _errorMessage = '';
      _selectedSubtitle = null;
      _subtitleCues = [];
      _currentSubtitleText = '';
      _subtitleBitmapBytes = null;
      _selectedAudio = null;
      _selectedQuality = VideoQualityOption.directPlay;
      _accumulatedSeekSeconds = 0;
      _hasAutoSkippedIntro = false;
      _showSkipIntroButton = false;
    });

    _initPlayer();
    _fetchAdjacentEpisodes();
    _loadPortraitSeasonEpisodes();
    _checkWatchlist();

    if (!Platform.isWindows && !PlixDeviceHelper.isTelevision) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls && _playPauseBtnFocusNode.canRequestFocus) {
        _playPauseBtnFocusNode.requestFocus();
      }
    });
  }

  void _startNextEpisode() {
    _autoplayTimer?.cancel();
    if (_nextEpisodeItem == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _playEpisode(_nextEpisodeItem!);
  }

  void _onPositionUpdate(int pos) {
    if (!mounted || !_isInitialized) return;
    final actualPos = _selectedQuality.isDirectPlay ? pos : (_streamOffsetMs + pos);
    final clampedPos = (_durationMs > 0 && actualPos > _durationMs) ? _durationMs : actualPos;
    _currentPositionMs = clampedPos;
    _timelineService.updatePosition(clampedPos);

    // Intro detection & auto skip or skip button
    final intro = _currentItem.introMarker;
    if (intro != null) {
      final inIntro = clampedPos >= intro.startTimeOffset && clampedPos < intro.endTimeOffset;
      if (inIntro) {
        if (_autoSkipIntro && !_hasAutoSkippedIntro) {
          _hasAutoSkippedIntro = true;
          _skipIntro();
          _showToast('Skipped Intro');
        } else if (!_autoSkipIntro && !_showSkipIntroButton) {
          setState(() {
            _showSkipIntroButton = true;
          });
        }
      } else {
        if (_showSkipIntroButton) {
          setState(() {
            _showSkipIntroButton = false;
          });
        }
      }
    }

    // Update active subtitle cue ONLY if we have parsed external cues in Flutter (Android TV).
    // On Windows, MPV renders subtitles natively on the video surface.
    if (!Platform.isWindows && _subtitleCues.isNotEmpty) {
      final cue = SubtitleParser.findActiveCue(_subtitleCues, Duration(milliseconds: clampedPos));
      final text = cue?.text ?? '';
      if (_currentSubtitleText != text) {
        setState(() {
          _currentSubtitleText = text;
        });
      }
    }

    // Trigger state update for progress bar
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkWatchlist() async {
    try {
      final userToken = await PlexAuthService().getSavedToken() ?? widget.server.accessToken;
      final target = _currentItem.isEpisode || _currentItem.isSeason
          ? (_currentItem.grandparentRatingKey != null
              ? PlexMediaItem(
                  ratingKey: _currentItem.grandparentRatingKey!,
                  key: '/library/metadata/${_currentItem.grandparentRatingKey}',
                  title: _currentItem.grandparentTitle ?? _currentItem.title,
                  type: 'show',
                  grandparentRatingKey: _currentItem.grandparentRatingKey,
                  grandparentGuid: _currentItem.grandparentGuid,
                  guid: _currentItem.grandparentGuid,
                )
              : _currentItem)
          : _currentItem;
      final inList = await _mediaService.isInWatchlist(item: target, userToken: userToken);
      if (mounted) setState(() => _isOnWatchlist = inList);
    } catch (_) {}
  }

  Future<void> _toggleWatchlist() async {
    if (_isUpdatingWatchlist) return;
    setState(() => _isUpdatingWatchlist = true);
    try {
      final userToken = await PlexAuthService().getSavedToken() ?? widget.server.accessToken;
      final target = _currentItem.isEpisode || _currentItem.isSeason
          ? (_currentItem.grandparentRatingKey != null
              ? PlexMediaItem(
                  ratingKey: _currentItem.grandparentRatingKey!,
                  key: '/library/metadata/${_currentItem.grandparentRatingKey}',
                  title: _currentItem.grandparentTitle ?? _currentItem.title,
                  type: 'show',
                  grandparentRatingKey: _currentItem.grandparentRatingKey,
                  grandparentGuid: _currentItem.grandparentGuid,
                  guid: _currentItem.grandparentGuid,
                )
              : _currentItem)
          : _currentItem;
      final willAdd = !_isOnWatchlist;
      final success = willAdd
          ? await _mediaService.addToWatchlist(item: target, userToken: userToken)
          : await _mediaService.removeFromWatchlist(item: target, userToken: userToken);
      if (mounted && success) {
        setState(() {
          _isOnWatchlist = willAdd;
          _isUpdatingWatchlist = false;
        });
        _showToast(willAdd ? 'Added to Watchlist' : 'Removed from Watchlist');
      } else if (mounted) {
        setState(() => _isUpdatingWatchlist = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isUpdatingWatchlist = false);
    }
  }

  Future<void> _loadPortraitSeasonEpisodes() async {
    if (!_currentItem.isEpisode) {
      if (mounted) setState(() => _portraitSeasonEpisodes = []);
      return;
    }
    setState(() => _isLoadingPortraitEpisodes = true);
    try {
      final seasonKey = _currentItem.parentRatingKey ?? '';
      final showKey = _currentItem.grandparentRatingKey;
      final episodes = await _mediaService.getSeasonEpisodes(
        seasonKey,
        showRatingKey: showKey,
      );
      if (mounted) {
        setState(() {
          _portraitSeasonEpisodes = episodes;
          _isLoadingPortraitEpisodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPortraitEpisodes = false);
    }
  }

  void _updateVideoBounds(BuildContext context, bool isPortrait) {
    if (Platform.isWindows || PlixDeviceHelper.isTelevision) return;
    if (_isInPip) return;

    final currentOrientation = MediaQuery.of(context).orientation;
    if (currentOrientation != _lastAppliedOrientation) {
      _lastAppliedOrientation = currentOrientation;
      if (isPortrait) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }

    if (isPortrait) {
      final mq = MediaQuery.of(context);
      final dpr = mq.devicePixelRatio;
      final topPadding = mq.padding.top;
      final screenWidth = mq.size.width;
      final videoHeight = screenWidth / 1.77778;

      final pxY = (topPadding * dpr).round();
      final pxWidth = (screenWidth * dpr).round();
      final pxHeight = (videoHeight * dpr).round();

      _nativePlayer.setVideoBounds(
        x: 0,
        y: pxY,
        width: pxWidth,
        height: pxHeight,
      );
    } else {
      _nativePlayer.setVideoBounds(
        x: 0,
        y: 0,
        width: -1,
        height: -1,
      );
    }
  }

  Future<void> _setPlaybackSpeed(double s) async {
    setState(() {
      _playbackSpeed = s;
    });

    // On Android Direct Play, ExoPlayer may not time-stretch compressed audio
    // passthrough (AC3/EAC3/DTS). Force a directStream transcode when speed != 1x
    // so the server encodes the audio at the requested speed. Return to directPlay
    // when the user resets to 1x.
    if (!Platform.isWindows) {
      final needsTranscode = (s - 1.0).abs() > 0.01;
      _forceAudioForSpeed = needsTranscode;
      if (needsTranscode && _selectedQuality.isDirectPlay) {
        await _changeQuality(VideoQualityOption.directStream, force: true);
        // _changeQuality restarts the player; then set speed on the new stream
        await _nativePlayer.setPlaybackSpeed(s);
        return;
      } else if (!needsTranscode && !_selectedQuality.isDirectPlay) {
        _forceAudioForSpeed = false;
        // Back to 1x — restore direct play. The new ExoPlayer instance starts
        // with the previous native speed, so reset it explicitly.
        await _changeQuality(VideoQualityOption.directPlay, force: true);
        await _nativePlayer.setPlaybackSpeed(1.0);
        return;
      }
    }

    await _nativePlayer.setPlaybackSpeed(s);
  }

  void _showSpeedSelector() {
    _hideControlsTimer?.cancel();
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5];
    final items = speeds.map((s) => _PlaybackOptionItem(
      label: '${s == 1.0 ? '1.0' : s.toString()}x',
      isSelected: (_playbackSpeed - s).abs() < 0.01,
      onTap: () {
        Navigator.of(context).pop();
        _setPlaybackSpeed(s);
        _scheduleHideControls();
      },
    )).toList();

    int selectedIdx = speeds.indexWhere((s) => (_playbackSpeed - s).abs() < 0.01);
    if (selectedIdx < 0) selectedIdx = 2;

    showModalBottomSheet(
      context: context,
      backgroundColor: PlixTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _PlaybackOptionSelector(
          title: 'Playback Speed',
          icon: Icons.speed_rounded,
          items: items,
          initialSelectedIndex: selectedIdx,
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  Future<void> _initPlayer() async {
    try {
      // Fetch full metadata if not present (ensures full streams, bitrate, HDR flags, air date)
      if (_currentItem.partKey == null ||
          _currentItem.partKey!.isEmpty ||
          _currentItem.subtitleStreams.isEmpty) {
        try {
          final fullItem = await _mediaService.getItemMetadata(_currentItem.ratingKey);
          _currentItem = fullItem;
        } catch (_) {}
      }

      if (_currentItem.duration != null && _currentItem.duration! > 0) {
        _durationMs = _currentItem.duration!;
      }

      // Check device audio compatibility. Some Android TV devices advertise a
      // DTS decoder but cannot actually render DTS (especially DTS-HD), which
      // results in direct play with no audio. Always transcode DTS/TrueHD.
      final audioCodec = (_currentItem.audioCodec ?? '').toLowerCase();
      if (audioCodec.isNotEmpty) {
        final isDtsOrLossless = audioCodec.contains('dts') ||
            audioCodec == 'dca' ||
            audioCodec.contains('truehd') ||
            audioCodec.contains('true-hd') ||
            audioCodec == 'mlp';
        final isSupported = !isDtsOrLossless &&
            await _nativePlayer.checkAudioSupported(audioCodec);
        _audioNeedsTranscode = isDtsOrLossless || !isSupported;
        if (_audioNeedsTranscode) {
          _selectedQuality = VideoQualityOption.directStream;
        }
      }
      if (_currentItem.isTrailer && _selectedQuality.isDirectPlay) {
        _selectedQuality = VideoQualityOption.directStream;
      }

      final String streamUrl;
      final int startPos;
      if (_selectedQuality.isDirectPlay) {
        _streamOffsetMs = 0;
        startPos = _currentPositionMs;
        final partKey = _currentItem.partKey;
        if (partKey == null || partKey.isEmpty) {
          throw Exception('Direct Play stream URL unavailable for this media file.');
        }
        streamUrl = _mediaService.buildDirectPlayUrl(partKey);
      } else {
        _streamOffsetMs = _currentPositionMs;
        startPos = 0;
        streamUrl = _mediaService.buildTranscodeUrl(
          ratingKey: _currentItem.ratingKey,
          maxBitrateKbps: _selectedQuality.bitrateKbps,
          resolution: _selectedQuality.resolution,
          offsetSeconds: _currentPositionMs ~/ 1000,
          clientId: widget.clientId,
          directStreamVideo: _selectedQuality.resolution.isEmpty,
          forceAudioTranscode: _audioNeedsTranscode || _forceAudioForSpeed,
        );
      }

      await _nativePlayer.play(
        url: streamUrl,
        headers: _playHeaders,
        positionMs: startPos,
      );

      _timelineService.startPlayback(
        _currentItem,
        _currentPositionMs,
      );

      // Check if any subtitle stream is marked as selected by default
      PlexSubtitleStream? defaultSub;
      for (final s in _currentItem.subtitleStreams) {
        if (s.isSelected) {
          defaultSub = s;
          break;
        }
      }
      if (defaultSub != null) {
        _selectSubtitle(defaultSub);
      } else {
        _nativePlayer.setSubtitleTrack(enabled: false);
      }

      // Check if any audio stream is marked as selected by default
      for (final a in _currentItem.audioStreams) {
        if (a.isSelected) {
          _selectedAudio = a;
          break;
        }
      }
      if (_selectedAudio == null && _currentItem.audioStreams.isNotEmpty) {
        _selectedAudio = _currentItem.audioStreams.first;
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isPlaying = true;
          _isPaused = false;
        });
        if (_showControls && _playPauseBtnFocusNode.canRequestFocus) {
          _playPauseBtnFocusNode.requestFocus();
        }
        _scheduleHideControls();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _selectSubtitle(PlexSubtitleStream? stream) async {
    final isBitmap = stream != null && stream.isBitmapSubtitle;

    setState(() {
      _selectedSubtitle = stream;
      _subtitleCues = [];
      _currentSubtitleText = '';
      _subtitleBitmapBytes = null;
    });

    if (stream == null) {
      await _nativePlayer.setSubtitleTrack(enabled: false);
    } else if (!isBitmap || Platform.isWindows) {
      String? subUrl;
      if (Platform.isWindows && stream.key.isNotEmpty && !widget.server.isJellyfin) {
        subUrl = '${_mediaService.baseUrl}${stream.key}?X-Plex-Token=${widget.server.accessToken}';
      }
      await _nativePlayer.setSubtitleTrack(
        enabled: true,
        language: stream.languageCode.isNotEmpty ? stream.languageCode : stream.language,
        label: stream.displayTitle,
        trackIndex: stream.streamIndex,
        url: subUrl,
      );
    } else {
      // For bitmap subtitles on Android (VOBSUB / PGS):
      // Disable ExoPlayer's text track override so ExoPlayer doesn't try to decode bitmap packets (which freezes playback).
      await _nativePlayer.setSubtitleTrack(enabled: false);
    }

    if (_currentItem.partId != null) {
      _mediaService.setSubtitleStream(
        partId: _currentItem.partId!,
        subtitleStreamId: stream?.id ?? '0',
      );
    }

    // On Android, bitmap subtitles (VOBSUB/PGS) cannot be decoded by ExoPlayer and must be burned in by transcoding.
    // If we are currently Direct Playing and a bitmap subtitle is selected, automatically switch to Direct Stream.
    if (!Platform.isWindows && isBitmap && _selectedQuality.isDirectPlay) {
      await _changeQuality(VideoQualityOption.directStream, force: true);
    } else if (!_selectedQuality.isDirectPlay) {
      await _changeQuality(_selectedQuality, force: true);
    }

    // Only fetch text subtitle cues for text subtitles (SRT, VTT, etc.).
    // Never attempt to fetch text cues for VOBSUB or PGS bitmap subtitles (which causes Plex endpoint to hang/fail).
    if (!Platform.isWindows && stream != null && !isBitmap) {
      final content = await _mediaService.fetchSubtitleContent(
        ratingKey: _currentItem.ratingKey,
        subtitleStreamId: stream.id,
        streamKey: stream.key,
      );
      if (content != null && content.isNotEmpty && mounted) {
        final cues = SubtitleParser.parse(content);
        if (cues.isNotEmpty) {
          setState(() {
            _subtitleCues = cues;
          });
        }
      }
    }
  }

  void _handleNativeMediaKey(MediaKeyAction action) {
    if (!_isInitialized) return;

    switch (action) {
      case MediaKeyAction.playPause:
        _togglePlayPause();
        break;
      case MediaKeyAction.play:
        if (!_isPlaying) {
          _isPaused = false;
          setState(() => _isPlaying = true);
          _nativePlayer.resume();
          _timelineService.resume(_currentPositionMs);
          _showCenterFeedback(Icons.play_arrow_rounded);
          if (_showControls) {
            _scheduleHideControls();
          }
        }
        break;
      case MediaKeyAction.pause:
        if (_isPlaying) {
          _isPaused = true;
          setState(() => _isPlaying = false);
          _nativePlayer.pause();
          _timelineService.pause(_currentPositionMs);
          _showCenterFeedback(Icons.pause_rounded);
          _hideControlsTimer?.cancel();
        }
        break;
      case MediaKeyAction.fastForward:
        _accumulateSeek(_skipAheadSeconds);
        break;
      case MediaKeyAction.rewind:
        _accumulateSeek(-_quickRewindSeconds);
        break;
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    if (_isPlaying) {
      _isPaused = true;
      setState(() => _isPlaying = false);
      _nativePlayer.pause();
      _timelineService.pause(_currentPositionMs);
      _showCenterFeedback(Icons.pause_rounded);
      _hideControlsTimer?.cancel();
    } else {
      _isPaused = false;
      setState(() => _isPlaying = true);
      _nativePlayer.resume();
      _timelineService.resume(_currentPositionMs);
      _showCenterFeedback(Icons.play_arrow_rounded);
      if (_showControls) {
        _scheduleHideControls();
      }
    }
  }

  void _accumulateSeek(int seconds) {
    if (!_isInitialized) return;

    // Pause UI hide timer so controls don't disappear while seeking!
    _hideControlsTimer?.cancel();
    _quickSeekHideTimer?.cancel();
    _isQuickSeeking = true;

    _accumulatedSeekSeconds += seconds;

    final sign = _accumulatedSeekSeconds > 0 ? '+' : '';
    _showCenterFeedback(
      _accumulatedSeekSeconds > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      text: '$sign${_accumulatedSeekSeconds}s',
      duration: const Duration(milliseconds: 1000),
    );

    // Update UI dynamically on the fly to adjust progress bar and elapsed time!
    if (mounted) {
      setState(() {});
    }

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      final totalSec = _accumulatedSeekSeconds;
      _accumulatedSeekSeconds = 0;
      if (totalSec != 0 && mounted) {
        _seekRelative(totalSec);
      }
      if (_showControls && mounted) {
        _scheduleHideControls();
      }
      _quickSeekHideTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _isQuickSeeking = false;
          });
        }
      });
    });
  }

  void _seekToTarget(int target) {
    if (!_isInitialized) return;
    final maxMs = _durationMs > 0 ? _durationMs : target + 60000;
    final clampedTarget = target.clamp(0, maxMs);

    if (_selectedQuality.isDirectPlay) {
      _nativePlayer.seekTo(clampedTarget);
      _timelineService.updatePosition(clampedTarget);
      _currentPositionMs = clampedTarget;
      if (mounted) setState(() {});
    } else {
      _currentPositionMs = clampedTarget;
      _streamOffsetMs = clampedTarget;
      if (mounted) setState(() {});

      final streamUrl = _mediaService.buildTranscodeUrl(
        ratingKey: _currentItem.ratingKey,
        maxBitrateKbps: _selectedQuality.bitrateKbps,
        resolution: _selectedQuality.resolution,
        offsetSeconds: clampedTarget ~/ 1000,
        clientId: widget.clientId,
        directStreamVideo: _selectedQuality.resolution.isEmpty,
        burnSubtitles: _selectedSubtitle != null,
        subtitleStreamId: _selectedSubtitle?.id,
        forceAudioTranscode: _audioNeedsTranscode || _forceAudioForSpeed,
      );

      _nativePlayer.play(
        url: streamUrl,
        headers: _playHeaders,
        positionMs: 0,
      );
      _timelineService.updatePosition(clampedTarget);
    }
  }

  void _seekRelative(int seconds) {
    if (!_isInitialized) return;
    final cur = _currentPositionMs;
    final maxMs = _durationMs > 0 ? _durationMs : cur + 60000;
    final target = (cur + (seconds * 1000)).clamp(0, maxMs);
    _seekToTarget(target);
  }

  void _showCenterFeedback(IconData icon, {String? text, Duration duration = const Duration(milliseconds: 650)}) {
    setState(() {
      _centerFeedbackIcon = icon;
      _centerFeedbackText = text;
    });
    _centerFeedbackTimer?.cancel();
    _centerFeedbackTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _centerFeedbackIcon = null;
          _centerFeedbackText = null;
        });
      }
    });
  }

  void _showControlsTemporarily() {
    if (_accumulatedSeekSeconds != 0) {
      _seekDebounceTimer?.cancel();
      final totalSec = _accumulatedSeekSeconds;
      _accumulatedSeekSeconds = 0;
      _seekRelative(totalSec);
    }
    if (_showControls) {
      if (_isPlaying && !_isPaused) {
        _scheduleHideControls();
      }
      return;
    }
    setState(() {
      _showControls = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls && _playPauseBtnFocusNode.canRequestFocus) {
        _playPauseBtnFocusNode.requestFocus();
      }
    });
    if (_isPlaying && !_isPaused) {
      _scheduleHideControls();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_isPlaying || _isPaused) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_isPaused) {
        setState(() {
          _showControls = false;
        });
        if (_playerFocusNode.canRequestFocus) {
          _playerFocusNode.requestFocus();
        }
      }
    });
  }

  void _hideControlsImmediate() {
    _hideControlsTimer?.cancel();
    if (mounted) {
      setState(() {
        _showControls = false;
      });
      if (_playerFocusNode.canRequestFocus) {
        _playerFocusNode.requestFocus();
      }
    }
  }

  Future<void> _toggleFullScreen() async {
    if (Platform.isWindows) {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
      if (mounted) {
        setState(() {
          _isFullScreen = !isFull;
        });
      }
    }
  }

  void _goToSeries() {
    final seriesKey = _currentItem.grandparentRatingKey;
    if (seriesKey == null || seriesKey.isEmpty) return;

    final showTitle = _currentItem.grandparentTitle ?? 'Series';
    final showThumb = _currentItem.grandparentThumb;
    final seasonKey = _currentItem.parentRatingKey;
    final episodeKey = _currentItem.ratingKey;

    _timelineService.stop(_currentPositionMs);
    _nativePlayer.stop();

    final showItem = PlexMediaItem(
      ratingKey: seriesKey,
      key: widget.server.isJellyfin ? '/Items/$seriesKey' : '/library/metadata/$seriesKey',
      type: 'show',
      title: showTitle,
      thumb: showThumb,
      grandparentThumb: showThumb,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: showItem,
          initialSeasonKey: seasonKey,
          initialEpisodeKey: episodeKey,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    );
  }

  void _handleServerStop(String? reason) {
    _nativePlayer.pause();
    setState(() {
      _isPlaying = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PlixTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.5), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.block_rounded, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 14),
            const Text(
              'Playback Stopped by Server',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Plex server has stopped this playback session.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (reason != null && reason.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PlixTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PlixTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message from administrator:',
                      style: TextStyle(color: PlixTheme.plexGold, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reason.trim(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          PlixButton(
            autofocus: true,
            isPrimary: true,
            label: 'OK',
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;

      if (event is KeyDownEvent) {
        // Toggle fullscreen with 'F' key on desktop
        if (Platform.isWindows && key == LogicalKeyboardKey.keyF) {
          _toggleFullScreen();
          return KeyEventResult.handled;
        }

        // Remote media keys (Play/Pause)
        if (key == LogicalKeyboardKey.mediaPlayPause ||
            key == LogicalKeyboardKey.mediaPlay ||
            key == LogicalKeyboardKey.mediaPause) {
          _togglePlayPause();
          return KeyEventResult.handled;
        }

        // Back key handling: exit fullscreen first if active, else close UI first if open; only exit if UI closed
        if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
          if (Platform.isWindows && _isFullScreen) {
            _toggleFullScreen();
            return KeyEventResult.handled;
          }
          if (_showControls) {
            setState(() {
              _showControls = false;
            });
            _playerFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
        }
      }

      // Seeking keys (media keys)
      if (key == LogicalKeyboardKey.mediaTrackNext ||
          key == LogicalKeyboardKey.mediaFastForward) {
        _accumulateSeek(_skipAheadSeconds);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.mediaTrackPrevious ||
          key == LogicalKeyboardKey.mediaRewind) {
        _accumulateSeek(-_quickRewindSeconds);
        return KeyEventResult.handled;
      }

      // Skip intro on select/enter if Skip Intro button is showing
      if (_showSkipIntroButton && event is KeyDownEvent &&
          (key == LogicalKeyboardKey.select ||
           key == LogicalKeyboardKey.enter ||
           key == LogicalKeyboardKey.space ||
           key == LogicalKeyboardKey.gameButtonA)) {
        _skipIntro();
        return KeyEventResult.handled;
      }

      // When controls are NOT showing:
      if (!_showControls) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _accumulateSeek(-_quickRewindSeconds);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _accumulateSeek(_skipAheadSeconds);
          return KeyEventResult.handled;
        }
        // Pressing Up, Down, Select or Enter brings up the UI without triggering any buttons!
        if (event is KeyDownEvent &&
            (key == LogicalKeyboardKey.arrowUp ||
             key == LogicalKeyboardKey.arrowDown ||
             key == LogicalKeyboardKey.select ||
             key == LogicalKeyboardKey.enter ||
             key == LogicalKeyboardKey.space ||
             key == LogicalKeyboardKey.gameButtonA)) {
          _showControlsTemporarily();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // When controls ARE showing:
      if (event is KeyDownEvent) {
        _scheduleHideControls();
        // If player focus node receives directional keys or select while controls are visible, redirect to play/pause button
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (!_playPauseBtnFocusNode.hasFocus &&
              !_prevEpBtnFocusNode.hasFocus &&
              !_nextEpBtnFocusNode.hasFocus &&
              !_subtitleBtnFocusNode.hasFocus &&
              !_audioBtnFocusNode.hasFocus &&
              !_qualityBtnFocusNode.hasFocus &&
              !_backBtnFocusNode.hasFocus) {
            _playPauseBtnFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
      }
    }
    return KeyEventResult.ignored;
  }

  bool _onGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.mediaPlayPause ||
         key == LogicalKeyboardKey.mediaPlay ||
         key == LogicalKeyboardKey.mediaPause ||
         key == LogicalKeyboardKey.headsetHook)) {
      _togglePlayPause();
      return true;
    }

    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _accumulateSeek(_skipAheadSeconds);
      return true;
    }

    if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.mediaRewind) {
      _accumulateSeek(-_quickRewindSeconds);
      return true;
    }

    // Remote Back button
    if (event is KeyDownEvent && (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack)) {
      if (_showControls) {
        setState(() {
          _showControls = false;
        });
        _playerFocusNode.requestFocus();
        return true;
      }
    }

    if (!_showControls) {
      if (event is KeyDownEvent &&
          (key == LogicalKeyboardKey.arrowUp ||
           key == LogicalKeyboardKey.arrowDown ||
           key == LogicalKeyboardKey.select ||
           key == LogicalKeyboardKey.enter ||
           key == LogicalKeyboardKey.space ||
           key == LogicalKeyboardKey.gameButtonA)) {
        _showControlsTemporarily();
        return true;
      }
    }

    return false;
  }

  void _showAudioSelector() {
    _hideControlsTimer?.cancel();
    final items = <_PlaybackOptionItem>[
      for (int i = 0; i < _currentItem.audioStreams.length; i++)
        (() {
          final stream = _currentItem.audioStreams[i];
          final isSel = _selectedAudio?.id == stream.id || (_selectedAudio == null && i == 0);
          return _PlaybackOptionItem(
            label: stream.displayTitle.isNotEmpty ? stream.displayTitle : 'Audio Track ${i + 1}',
            codec: stream.codec.toUpperCase(),
            isSelected: isSel,
            onTap: () {
              Navigator.of(context).pop();
              _selectAudio(stream);
              _scheduleHideControls();
            },
          );
        })(),
    ];

    int selectedIdx = 0;
    if (_selectedAudio != null) {
      final aIdx = _currentItem.audioStreams.indexWhere((s) => s.id == _selectedAudio!.id);
      if (aIdx >= 0) selectedIdx = aIdx;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: PlixTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _PlaybackOptionSelector(
          title: 'Audio Track',
          icon: Icons.audiotrack_rounded,
          items: items,
          initialSelectedIndex: selectedIdx,
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  Future<void> _selectAudio(PlexAudioStream stream) async {
    setState(() {
      _selectedAudio = stream;
    });

    await _nativePlayer.setAudioTrack(
      trackIndex: stream.streamIndex,
      language: stream.languageCode.isNotEmpty ? stream.languageCode : stream.language,
      label: stream.displayTitle,
    );

    if (_currentItem.partId != null) {
      _mediaService.setAudioStream(
        partId: _currentItem.partId!,
        audioStreamId: stream.id,
      );
    }
  }

  void _showSubtitleSelector() {
    _hideControlsTimer?.cancel();
    final items = <_PlaybackOptionItem>[
      _PlaybackOptionItem(
        label: 'Off',
        isSelected: _selectedSubtitle == null,
        onTap: () {
          Navigator.of(context).pop();
          _selectSubtitle(null);
          _scheduleHideControls();
        },
      ),
      for (final stream in _currentItem.subtitleStreams)
        _PlaybackOptionItem(
          label: stream.displayTitle,
          codec: stream.codec.toUpperCase(),
          isSelected: _selectedSubtitle?.id == stream.id,
          onTap: () {
            Navigator.of(context).pop();
            _selectSubtitle(stream);
            _scheduleHideControls();
          },
        ),
    ];

    int selectedIdx = 0;
    if (_selectedSubtitle != null) {
      final subIdx = _currentItem.subtitleStreams.indexWhere((s) => s.id == _selectedSubtitle!.id);
      if (subIdx >= 0) {
        selectedIdx = subIdx + 1;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: PlixTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _PlaybackOptionSelector(
          title: 'Subtitles',
          icon: Icons.subtitles_rounded,
          items: items,
          initialSelectedIndex: selectedIdx,
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  void _showQualitySelector() {
    _hideControlsTimer?.cancel();
    final presets = _currentItem.isTrailer
        ? VideoQualityOption.presets.where((o) => !o.isDirectPlay).toList()
        : VideoQualityOption.presets;
    final selectedIdx = presets.indexOf(_selectedQuality);

    final items = presets.map((option) {
      return _PlaybackOptionItem(
        label: option.label,
        codec: option.isDirectPlay ? 'DIRECT' : 'TRANSCODE',
        isSelected: _selectedQuality == option,
        onTap: () {
          Navigator.of(context).pop();
          _changeQuality(option);
          _scheduleHideControls();
        },
      );
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: PlixTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _PlaybackOptionSelector(
          title: 'Playback Quality',
          icon: Icons.tune_rounded,
          items: items,
          initialSelectedIndex: selectedIdx >= 0 ? selectedIdx : 0,
        );
      },
    ).then((_) => _scheduleHideControls());
  }

  Future<void> _changeQuality(VideoQualityOption quality, {bool force = false}) async {
    if (_currentItem.isTrailer && quality.isDirectPlay) {
      quality = VideoQualityOption.directStream;
    }
    if (!force && _selectedQuality == quality) return;
    setState(() {
      _selectedQuality = quality;
      _isSwitchingQuality = true;
    });

    final currentPosition = _currentPositionMs;

    try {
      final String streamUrl;
      final int startPos;
      if (quality.isDirectPlay) {
        _streamOffsetMs = 0;
        startPos = currentPosition;
        final partKey = _currentItem.partKey;
        if (partKey == null || partKey.isEmpty) {
          throw Exception('Direct Play stream URL unavailable.');
        }
        streamUrl = _mediaService.buildDirectPlayUrl(partKey);
      } else {
        _streamOffsetMs = currentPosition;
        startPos = 0;
        streamUrl = _mediaService.buildTranscodeUrl(
          ratingKey: _currentItem.ratingKey,
          maxBitrateKbps: quality.bitrateKbps,
          resolution: quality.resolution,
          offsetSeconds: currentPosition ~/ 1000,
          clientId: widget.clientId,
          directStreamVideo: quality.resolution.isEmpty,
          burnSubtitles: _selectedSubtitle != null,
          subtitleStreamId: _selectedSubtitle?.id,
          forceAudioTranscode: _audioNeedsTranscode || _forceAudioForSpeed,
        );
      }

      await _nativePlayer.play(
        url: streamUrl,
        headers: _playHeaders,
        positionMs: startPos,
      );

      _timelineService.resume(currentPosition);

      if (mounted) {
        setState(() {
          _isSwitchingQuality = false;
        });
        _scheduleHideControls();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSwitchingQuality = false;
          _hasError = true;
          _errorMessage = 'Failed to switch quality: $e';
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    _mediaButtonService.setPlayerActive(false);
    _mediaKeySub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _errSub?.cancel();
    _endedSub?.cancel();
    _subCueSub?.cancel();
    _subBitmapSub?.cancel();
    _bufferingSub?.cancel();
    _hideControlsTimer?.cancel();
    _centerFeedbackTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _quickSeekHideTimer?.cancel();
    _autoplayTimer?.cancel();

    _pipSub?.cancel();
    _physicalOrientationSub?.cancel();
    _speedBtnFocusNode.dispose();
    _nativePlayer.setVideoBounds(x: 0, y: 0, width: -1, height: -1);
    _timelineService.stop(_currentPositionMs);
    _timelineService.dispose();
    _serverStopSubscription?.cancel();
    _nativePlayer.stop();
    _nativePlayer.dispose();

    _playerFocusNode.dispose();
    _backBtnFocusNode.dispose();
    _scrubberFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _playPauseBtnFocusNode.dispose();
    _prevEpBtnFocusNode.dispose();
    _nextEpBtnFocusNode.dispose();
    _subtitleBtnFocusNode.dispose();
    _audioBtnFocusNode.dispose();
    _qualityBtnFocusNode.dispose();
    _seriesBtnFocusNode.dispose();
    _autoplayPlayNowFocusNode.dispose();
    _autoplayCancelFocusNode.dispose();
    _fullscreenBtnFocusNode.dispose();
    if (Platform.isWindows && _isFullScreen) {
      windowManager.setFullScreen(false);
    }
    if (!Platform.isWindows && !PlixDeviceHelper.isTelevision) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Widget _buildPortraitLayout(BuildContext context, double progressMs, double maxMs) {
    final mq = MediaQuery.of(context);
    final videoHeight = mq.size.width / 1.77778;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Status bar background
          Container(
            height: mq.padding.top,
            color: Colors.black,
          ),
          // Top Video Box (16:9 Aspect Ratio)
            SizedBox(
              width: double.infinity,
              height: videoHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                      if (_showControls) {
                        _scheduleHideControls();
                      }
                    },
                    child: const SizedBox.expand(),
                  ),

                  // Switching quality loading overlay
                  if (_isSwitchingQuality)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Switching quality...',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Subtitles overlay on video
                  if (!Platform.isWindows && _subtitleBitmapBytes != null && _selectedSubtitle != null)
                    Positioned(
                      bottom: _showControls ? 48 : 8,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: _isInPip
                                ? 26
                                : MediaQuery.of(context).size.height * 0.20,
                          ),
                          child: Image.memory(
                            _subtitleBitmapBytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    )
                  else if (!Platform.isWindows && _currentSubtitleText.isNotEmpty)
                    Positioned(
                      bottom: _isInPip ? 4 : (_showControls ? 48 : 8),
                      left: _isInPip ? 8 : 16,
                      right: _isInPip ? 8 : 16,
                      child: Center(
                        child: Text(
                          _currentSubtitleText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _isInPip ? 10 : 15,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: _isInPip ? 2 : 4, offset: const Offset(1, 1)),
                              Shadow(color: Colors.black, blurRadius: _isInPip ? 2 : 4, offset: const Offset(-1, -1)),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Skip intro button
                  if (_showSkipIntroButton)
                    Positioned(
                      bottom: _showControls ? 52 : 12,
                      right: 12,
                      child: PlixButton(
                        label: 'Skip Intro',
                        icon: const Icon(Icons.skip_next_rounded, size: 16),
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        onPressed: _skipIntro,
                      ),
                    ),

                  // Quick seek / play feedback
                  if (_centerFeedbackIcon != null || _centerFeedbackText != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_centerFeedbackIcon != null)
                              Icon(_centerFeedbackIcon, color: PlixTheme.plexGold, size: 36),
                            if (_centerFeedbackText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _centerFeedbackText!,
                                style: TextStyle(
                                  color: PlixTheme.plexGold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // Buffering indicator
                  if (_isBuffering && !_isSwitchingQuality)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                          strokeWidth: 3,
                        ),
                      ),
                    ),

                  // Controls Overlay
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _showControls = false;
                          });
                        },
                        child: Container(
                          color: Colors.black45,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                                    onPressed: () {
                                      _nativePlayer.stop();
                                      _timelineService.stop(_currentPositionMs);
                                      _nativePlayer.setVideoBounds(x: 0, y: 0, width: -1, height: -1);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  Expanded(
                                    child: Text(
                                      _currentItem.isEpisode ? _currentItem.title : _currentItem.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 22),
                                    tooltip: 'Picture in Picture',
                                    onPressed: () => _nativePlayer.enterPipMode(),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 26),
                                    tooltip: 'Fullscreen',
                                    onPressed: () {
                                      setState(() {
                                        _orientationLock = _OrientationLock.lockedLandscape;
                                      });
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.landscapeLeft,
                                        DeviceOrientation.landscapeRight,
                                      ]);
                                    },
                                  ),
                                ],
                              ),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 36),
                                  onPressed: () => _accumulateSeek(-_quickRewindSeconds),
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                    color: PlixTheme.plexGold,
                                    size: 54,
                                  ),
                                  onPressed: _togglePlayPause,
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  icon: const Icon(Icons.forward_30_rounded, color: Colors.white, size: 36),
                                  onPressed: () => _accumulateSeek(_skipAheadSeconds),
                                ),
                              ],
                            ),

                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(Duration(milliseconds: progressMs.toInt())),
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        trackHeight: 3,
                                        activeTrackColor: PlixTheme.plexGold,
                                        thumbColor: PlixTheme.plexGold,
                                        inactiveTrackColor: Colors.white24,
                                      ),
                                      child: Slider(
                                        value: progressMs.clamp(0.0, maxMs),
                                        min: 0.0,
                                        max: maxMs,
                                        onChangeStart: (_) {
                                          _hideControlsTimer?.cancel();
                                        },
                                        onChanged: (val) {
                                          _seekToTarget(val.toInt());
                                        },
                                        onChangeEnd: (_) {
                                          if (_isPlaying && !_isPaused) {
                                            _scheduleHideControls();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(Duration(milliseconds: maxMs.toInt())),
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                color: PlixTheme.background,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentItem.isEpisode ? _currentItem.title : _currentItem.displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_currentItem.isEpisode && _currentItem.grandparentTitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_currentItem.grandparentTitle!} • S${_currentItem.parentIndex ?? 1} E${_currentItem.index ?? 1}',
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_currentItem.formattedResolution.isNotEmpty)
                          _buildMobileBadge(_currentItem.formattedResolution),
                        if (_currentItem.isHdr)
                          _buildMobileBadge(_currentItem.hdrType?.toUpperCase() ?? 'HDR', isGold: true),
                        if (_currentItem.audioCodec != null && _currentItem.audioCodec!.isNotEmpty)
                          _buildMobileBadge(_currentItem.audioCodec!.toUpperCase()),
                        _buildMobileBadge(_selectedQuality.label),
                        if ((_playbackSpeed - 1.0).abs() > 0.01)
                          _buildMobileBadge('${_playbackSpeed}x', isGold: true),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPortraitIconButton(
                            icon: _isOnWatchlist ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                            iconColor: _isOnWatchlist ? PlixTheme.plexGold : Colors.white,
                            tooltip: _isOnWatchlist ? 'In Watchlist' : 'Watchlist',
                            onPressed: _toggleWatchlist,
                          ),
                          const SizedBox(width: 14),
                          _buildPortraitIconButton(
                            icon: Icons.speed_rounded,
                            iconColor: (_playbackSpeed - 1.0).abs() > 0.01 ? PlixTheme.plexGold : Colors.white,
                            tooltip: 'Speed (${_playbackSpeed == 1.0 ? '1.0' : _playbackSpeed}x)',
                            badgeText: (_playbackSpeed - 1.0).abs() > 0.01 ? '${_playbackSpeed}x' : null,
                            onPressed: _showSpeedSelector,
                          ),
                          const SizedBox(width: 14),
                          _buildPortraitIconButton(
                            icon: Icons.tune_rounded,
                            iconColor: _selectedQuality.isDirectPlay ? Colors.white : PlixTheme.plexGold,
                            tooltip: 'Quality (${_selectedQuality.label})',
                            onPressed: _showQualitySelector,
                          ),
                          const SizedBox(width: 14),
                          _buildPortraitIconButton(
                            icon: Icons.audiotrack_rounded,
                            iconColor: Colors.white,
                            tooltip: 'Audio Track',
                            onPressed: _showAudioSelector,
                          ),
                          const SizedBox(width: 14),
                          _buildPortraitIconButton(
                            icon: Icons.subtitles_rounded,
                            iconColor: _selectedSubtitle != null ? PlixTheme.plexGold : Colors.white,
                            tooltip: 'Subtitles',
                            onPressed: _showSubtitleSelector,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (_currentItem.summary.isNotEmpty) ...[
                      Text(
                        _currentItem.summary,
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_currentItem.isEpisode) ...[
                      Text(
                        'Season ${_currentItem.parentIndex ?? 1} Episodes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingPortraitEpisodes)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_portraitSeasonEpisodes.isEmpty)
                        const Text(
                          'No episodes available in this season.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _portraitSeasonEpisodes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) {
                            final ep = _portraitSeasonEpisodes[idx];
                            final isCurrent = ep.ratingKey == _currentItem.ratingKey;
                            return InkWell(
                              onTap: () => _playEpisode(ep),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? PlixTheme.plexGold.withOpacity(0.15)
                                      : PlixTheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isCurrent ? PlixTheme.plexGold : PlixTheme.cardBorder,
                                    width: isCurrent ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        width: 80,
                                        height: 48,
                                        child: ep.thumb != null && ep.thumb!.isNotEmpty
                                            ? Image.network(
                                                _mediaService.buildImageUrl(ep.thumb, width: 240, height: 144),
                                                headers: _playHeaders,
                                                fit: BoxFit.cover,
                                                cacheWidth: PlixImageCache.decodeWidth(context, 80, cap: 240),
                                                cacheHeight: PlixImageCache.decodeHeight(context, 48, cap: 144),
                                                errorBuilder: (_, __, ___) => Container(
                                                  color: Colors.black45,
                                                  child: const Icon(Icons.movie, color: Colors.white24),
                                                ),
                                              )
                                            : Container(
                                                color: Colors.black45,
                                                child: const Icon(Icons.movie, color: Colors.white24),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${ep.index ?? idx + 1}. ${ep.title}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isCurrent ? PlixTheme.plexGold : Colors.white,
                                              fontSize: 14,
                                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                            ),
                                          ),
                                          if (ep.duration != null && ep.duration! > 0) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '${(ep.duration! / 60000).round()} min',
                                              style: const TextStyle(
                                                color: PlixTheme.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isCurrent)
                                      Icon(Icons.play_arrow_rounded, color: PlixTheme.plexGold, size: 24),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildMobileBadge(String label, {bool isGold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGold ? PlixTheme.plexGold.withOpacity(0.2) : PlixTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isGold ? PlixTheme.plexGold : PlixTheme.cardBorder,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isGold ? PlixTheme.plexGold : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPortraitIconButton({
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onPressed,
    String? badgeText,
  }) {
    Widget button = Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: (badgeText != null || iconColor == PlixTheme.plexGold)
                    ? PlixTheme.plexGold.withOpacity(0.5)
                    : Colors.white12,
                width: 1.2,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );

    if (badgeText != null) {
      button = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          button,
          Positioned(
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: PlixTheme.plexGold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return button;
  }

  @override
  Widget build(BuildContext context) {
    final curMs = _currentPositionMs.toDouble();
    final maxMs = _durationMs > 0 ? _durationMs.toDouble() : 1.0;
    final seekOffsetMs = (_accumulatedSeekSeconds * 1000).toDouble();
    final effectiveProgressMs = (_accumulatedSeekSeconds != 0)
        ? (curMs + seekOffsetMs).clamp(0.0, maxMs)
        : curMs.clamp(0.0, maxMs);
    final progress = effectiveProgressMs;

    final isMobile = !Platform.isWindows && !PlixDeviceHelper.isTelevision;
    final isPortrait = isMobile && MediaQuery.of(context).orientation == Orientation.portrait;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateVideoBounds(context, isPortrait);
      }
    });



    return PopScope(
      canPop: isPortrait || !_showControls,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _nativePlayer.stop();
          _timelineService.stop(_currentPositionMs);
          _nativePlayer.setVideoBounds(x: 0, y: 0, width: -1, height: -1);
        } else {
          setState(() {
            _showControls = false;
          });
          _playerFocusNode.requestFocus();
        }
      },
      child: isPortrait
          ? _buildPortraitLayout(context, effectiveProgressMs, maxMs)
          : Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          cursor: (Platform.isWindows && !_showControls)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          onHover: (_) {
            if (Platform.isWindows) {
              _showControlsTemporarily();
            }
          },
          child: Focus(
            focusNode: _playerFocusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: Platform.isWindows ? _toggleFullScreen : null,
              onTap: () {
                if (_showControls) {
                  setState(() {
                    _showControls = false;
                  });
                  _playerFocusNode.requestFocus();
                } else {
                  _showControlsTemporarily();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // On Windows: MediaKit Video player; On TV: Native HDR SurfaceView behind transparent surface
                  if (Platform.isWindows && _nativePlayer.windowsVideoController != null)
                    Video(
                      controller: _nativePlayer.windowsVideoController!,
                      controls: NoVideoControls,
                    )
                  else
                    const SizedBox.expand(),

              // Switching quality loading overlay
              if (_isSwitchingQuality)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Switching to ${_selectedQuality.label}...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Buffering indicator
              if (_isBuffering && !_isSwitchingQuality)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                      strokeWidth: 3,
                    ),
                  ),
                ),

              // Subtitles overlay on video (Bitmap & Text) - Android TV & Mobile
              if (!Platform.isWindows && _subtitleBitmapBytes != null && _selectedSubtitle != null)
                Positioned(
                  bottom: _isInPip ? 4 : (_showControls ? 140 : 48),
                  left: _isInPip ? 8 : 48,
                  right: _isInPip ? 8 : 48,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: _isInPip
                            ? 30
                            : MediaQuery.of(context).size.height * 0.20,
                      ),
                      child: Image.memory(
                        _subtitleBitmapBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                )
              else if (!Platform.isWindows && _currentSubtitleText.isNotEmpty)
                Positioned(
                  bottom: _isInPip ? 4 : (_showControls ? 140 : 48),
                  left: _isInPip ? 8 : 48,
                  right: _isInPip ? 8 : 48,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: _isInPip ? 4 : 16, vertical: _isInPip ? 2 : 8),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Stroke outline
                          Text(
                            _currentSubtitleText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: _isInPip ? 10 : 24,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = _isInPip ? 1.5 : 3.5
                                ..color = Colors.black,
                            ),
                          ),
                          // Text fill
                          Text(
                            _currentSubtitleText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _isInPip ? 10 : 24,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Error state
              if (_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Playback Error',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        PlixButton(
                          autofocus: true,
                          isPrimary: true,
                          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                          label: 'Go Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),

              // Center quick action feedback (Play, Pause, Seek icons and text)
              if (_centerFeedbackIcon != null || _centerFeedbackText != null)
                Center(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: PlixTheme.plexGold.withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_centerFeedbackIcon != null)
                            Icon(
                              _centerFeedbackIcon,
                              color: PlixTheme.plexGold,
                              size: 56,
                            ),
                          if (_centerFeedbackText != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _centerFeedbackText!,
                              style: TextStyle(
                                color: PlixTheme.plexGold,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

              // Autoplay Next Episode Countdown Overlay
              if (_isAutoplayCountdownActive && _nextEpisodeItem != null)
                Center(
                  child: Container(
                    width: 480,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: PlixTheme.plexGold, width: 2.0),
                      boxShadow: [
                        BoxShadow(
                          color: PlixTheme.plexGold.withOpacity(0.35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.skip_next_rounded, color: PlixTheme.plexGold, size: 28),
                            const SizedBox(width: 8),
                            Text(
                              'Next episode in ${_autoplayCountdownSeconds}s...',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _nextEpisodeItem!.displayTitle,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PlayerDialogButton(
                              focusNode: _autoplayCancelFocusNode,
                              label: 'Cancel',
                              icon: Icons.close_rounded,
                              isPrimary: false,
                              onRight: () => _autoplayPlayNowFocusNode.requestFocus(),
                              onPressed: _cancelAutoplay,
                            ),
                            const SizedBox(width: 16),
                            _PlayerDialogButton(
                              focusNode: _autoplayPlayNowFocusNode,
                              label: 'Play Now',
                              icon: Icons.play_arrow_rounded,
                              isPrimary: true,
                              autofocus: true,
                              onLeft: () => _autoplayCancelFocusNode.requestFocus(),
                              onPressed: _startNextEpisode,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // OSD Overlays (Top bar and Bottom Controls)
              if (_isInitialized)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: ExcludeFocus(
                      excluding: !_showControls,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.9),
                            ],
                            stops: const [0.0, 0.25, 0.7, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Top bar with Title, Air date, and Stats Badges (Res, HDR, Audio, Bitrate, Direct Play)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PlixBackButton(
                                      focusNode: _backBtnFocusNode,
                                      onPressed: () {
                                        _nativePlayer.stop();
                                        _timelineService.stop(_currentPositionMs);
                                        _nativePlayer.setVideoBounds(x: 0, y: 0, width: -1, height: -1);
                                        Navigator.of(context).pop();
                                      },
                                      onDown: () => _scrubberFocusNode.requestFocus(),
                                      onRight: _scheduleHideControls,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _currentItem.isEpisode ? _currentItem.title : _currentItem.displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (_currentItem.grandparentTitle != null) ...[
                                                Text(
                                                  _currentItem.grandparentTitle!,
                                                  style: TextStyle(
                                                    color: PlixTheme.plexGold,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (_currentItem.isEpisode && _currentItem.parentIndex != null) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'S${_currentItem.parentIndex}:E${_currentItem.index ?? 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(width: 10),
                                              ],
                                              if (_currentItem.formattedAirDate.isNotEmpty)
                                                Text(
                                                  _currentItem.isMovie
                                                      ? _currentItem.formattedAirDate
                                                      : 'Aired: ${_currentItem.formattedAirDate}',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          // Media info boxes below show/movie name/air date
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              // Resolution badge
                                              if (_currentItem.formattedResolution.isNotEmpty)
                                                _OsdBadge(
                                                  label: _currentItem.formattedResolution,
                                                  isHighlight: true,
                                                ),

                                              // HDR badge
                                              if (_currentItem.isHdr)
                                                _OsdBadge(
                                                  label: _currentItem.hdrBadge.isNotEmpty
                                                      ? _currentItem.hdrBadge
                                                      : 'HDR',
                                                  isHighlight: true,
                                                  color: Colors.amberAccent,
                                                ),

                                              // Audio format badge
                                              if (_currentItem.formattedAudio.isNotEmpty)
                                                _OsdBadge(
                                                  label: _currentItem.formattedAudio,
                                                  icon: Icons.volume_up_rounded,
                                                  isHighlight: true,
                                                  color: Colors.lightBlueAccent,
                                                ),

                                              // Bitrate badge
                                              if (_currentItem.formattedBitrate.isNotEmpty)
                                                _OsdBadge(
                                                  label: _currentItem.formattedBitrate,
                                                ),

                                              // Direct play / Transcode badge
                                              _OsdBadge(
                                                label: _selectedQuality.isDirectPlay
                                                    ? 'DIRECT PLAY'
                                                    : (_selectedQuality.resolution.isEmpty
                                                        ? 'DIRECT STREAM'
                                                        : 'TRANSCODE (${_selectedQuality.label.split(' ').first})'),
                                                icon: _selectedQuality.isDirectPlay
                                                    ? Icons.flash_on
                                                    : Icons.tune_rounded,
                                                isHighlight: true,
                                                color: _selectedQuality.isDirectPlay
                                                    ? PlixTheme.plexGold
                                                    : Colors.amberAccent,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: _LiveClock(),
                                    ),
                                  ],
                                ),
                              ),

                              // Bottom controls (Scrubber + Playback buttons)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Scrubber slider
                                    Column(
                                      children: [
                                        Focus(
                                          focusNode: _scrubberFocusNode,
                                          onKeyEvent: (node, event) {
                                            if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                              final key = event.logicalKey;
                                              if (key == LogicalKeyboardKey.arrowLeft) {
                                                _accumulateSeek(-_quickRewindSeconds);
                                                return KeyEventResult.handled;
                                              }
                                              if (key == LogicalKeyboardKey.arrowRight) {
                                                _accumulateSeek(_skipAheadSeconds);
                                                return KeyEventResult.handled;
                                              }
                                              if (key == LogicalKeyboardKey.arrowDown) {
                                                _playPauseBtnFocusNode.requestFocus();
                                                return KeyEventResult.handled;
                                              }
                                              if (key == LogicalKeyboardKey.arrowUp) {
                                                _backBtnFocusNode.requestFocus();
                                                return KeyEventResult.handled;
                                              }
                                            }
                                            return KeyEventResult.ignored;
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: _isScrubberFocused ? PlixTheme.plexGold : Colors.transparent,
                                                width: 2.0,
                                              ),
                                              color: _isScrubberFocused ? Colors.white.withOpacity(0.08) : Colors.transparent,
                                            ),
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: _isScrubberFocused ? 8 : 4,
                                                activeTrackColor: PlixTheme.plexGold,
                                                inactiveTrackColor: Colors.white24,
                                                thumbColor: PlixTheme.plexGold,
                                                thumbShape: RoundSliderThumbShape(
                                                  enabledThumbRadius: _isScrubberFocused ? 11 : 6,
                                                ),
                                                overlayColor: PlixTheme.plexGold.withOpacity(0.3),
                                              ),
                                              child: Slider(
                                                value: progress,
                                                min: 0.0,
                                                max: maxMs,
                                                onChanged: (val) {
                                                  _seekToTarget(val.toInt());
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatDuration(Duration(milliseconds: effectiveProgressMs.toInt())),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                _formatDuration(Duration(milliseconds: _durationMs)),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Action Buttons (Focusable with remote D-pad)
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Centered circle buttons row
                                        Center(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Rotate button (Mobile only)
                                              if (isMobile) ...[
                                                _PlayerIconButton(
                                                  icon: Icons.screen_rotation_rounded,
                                                  iconColor: Colors.white,
                                                  tooltip: 'Portrait Mode',
                                                  onPressed: () {
                                                    setState(() {
                                                      _orientationLock = _OrientationLock.lockedPortrait;
                                                    });
                                                    SystemChrome.setPreferredOrientations([
                                                      DeviceOrientation.portraitUp,
                                                    ]);
                                                  },
                                                  onDown: _hideControlsImmediate,
                                                  onFocus: _scheduleHideControls,
                                                ),
                                                const SizedBox(width: 20),
                                              ],

                                              // Speed button (All platforms - on the left)
                                              _PlayerIconButton(
                                                focusNode: _speedBtnFocusNode,
                                                icon: Icons.speed_rounded,
                                                iconColor: (_playbackSpeed - 1.0).abs() > 0.01
                                                    ? PlixTheme.plexGold
                                                    : Colors.white70,
                                                badgeText: (_playbackSpeed - 1.0).abs() > 0.01 ? '${_playbackSpeed}x' : null,
                                                tooltip: 'Speed (${_playbackSpeed == 1.0 ? '1.0' : _playbackSpeed}x)',
                                                onPressed: _showSpeedSelector,
                                                onRight: () => (_currentItem.audioStreams.length > 1)
                                                    ? _audioBtnFocusNode.requestFocus()
                                                    : (_currentItem.isEpisode
                                                        ? _prevEpBtnFocusNode.requestFocus()
                                                        : _playPauseBtnFocusNode.requestFocus()),
                                                onUp: () => _scrubberFocusNode.requestFocus(),
                                                onDown: _hideControlsImmediate,
                                                onFocus: _scheduleHideControls,
                                              ),
                                              const SizedBox(width: 20),

                                              // Audio button (when audio tracks > 1 - on the left)
                                              if (_currentItem.audioStreams.length > 1) ...[
                                                _PlayerIconButton(
                                                  focusNode: _audioBtnFocusNode,
                                                  icon: Icons.audiotrack_rounded,
                                                  iconColor: _selectedAudio != null
                                                      ? PlixTheme.plexGold
                                                      : Colors.white70,
                                                  tooltip: 'Audio Track',
                                                  onPressed: _showAudioSelector,
                                                  onLeft: () => _speedBtnFocusNode.requestFocus(),
                                                  onRight: () => _currentItem.isEpisode
                                                      ? _prevEpBtnFocusNode.requestFocus()
                                                      : _playPauseBtnFocusNode.requestFocus(),
                                                  onUp: () => _scrubberFocusNode.requestFocus(),
                                                  onDown: _hideControlsImmediate,
                                                  onFocus: _scheduleHideControls,
                                                ),
                                                const SizedBox(width: 20),
                                              ],

                                              // Previous Episode button (TV Shows only)
                                              if (_currentItem.isEpisode) ...[
                                                _PlayerIconButton(
                                                  focusNode: _prevEpBtnFocusNode,
                                                  icon: Icons.skip_previous_rounded,
                                                  tooltip: _previousEpisodeItem != null
                                                      ? 'Previous: ${_previousEpisodeItem!.displayTitle}'
                                                      : 'No previous episode',
                                                  onPressed: _previousEpisodeItem != null
                                                      ? () => _playEpisode(_previousEpisodeItem!)
                                                      : null,
                                                  onLeft: () => (_currentItem.audioStreams.length > 1)
                                                      ? _audioBtnFocusNode.requestFocus()
                                                      : _speedBtnFocusNode.requestFocus(),
                                                  onRight: () => _playPauseBtnFocusNode.requestFocus(),
                                                  onUp: () => _scrubberFocusNode.requestFocus(),
                                                  onDown: _hideControlsImmediate,
                                                  onFocus: _scheduleHideControls,
                                                ),
                                                const SizedBox(width: 24),
                                              ],

                                              // Play/Pause button (Centered)
                                              _PlayerIconButton(
                                                focusNode: _playPauseBtnFocusNode,
                                                icon: _isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                isPrimary: true,
                                                tooltip: 'Play/Pause',
                                                onPressed: _togglePlayPause,
                                                onLeft: () => _currentItem.isEpisode
                                                    ? _prevEpBtnFocusNode.requestFocus()
                                                    : ((_currentItem.audioStreams.length > 1)
                                                        ? _audioBtnFocusNode.requestFocus()
                                                        : _speedBtnFocusNode.requestFocus()),
                                                onRight: () => _currentItem.isEpisode
                                                    ? _nextEpBtnFocusNode.requestFocus()
                                                    : _subtitleBtnFocusNode.requestFocus(),
                                                onUp: () => _scrubberFocusNode.requestFocus(),
                                                onDown: _hideControlsImmediate,
                                                onFocus: _scheduleHideControls,
                                              ),

                                              // Next Episode button (TV Shows only)
                                              if (_currentItem.isEpisode) ...[
                                                const SizedBox(width: 24),
                                                _PlayerIconButton(
                                                  focusNode: _nextEpBtnFocusNode,
                                                  icon: Icons.skip_next_rounded,
                                                  tooltip: _nextEpisodeItem != null
                                                      ? 'Next: ${_nextEpisodeItem!.displayTitle}'
                                                      : 'No next episode',
                                                  onPressed: _nextEpisodeItem != null
                                                      ? () => _playEpisode(_nextEpisodeItem!)
                                                      : null,
                                                  onLeft: () => _playPauseBtnFocusNode.requestFocus(),
                                                  onRight: () => _subtitleBtnFocusNode.requestFocus(),
                                                  onUp: () => _scrubberFocusNode.requestFocus(),
                                                  onDown: _hideControlsImmediate,
                                                  onFocus: _scheduleHideControls,
                                                ),
                                              ],

                                              const SizedBox(width: 28),

                                              // Subtitle button
                                              _PlayerIconButton(
                                                focusNode: _subtitleBtnFocusNode,
                                                icon: _selectedSubtitle != null
                                                    ? Icons.closed_caption_rounded
                                                    : Icons.closed_caption_disabled_rounded,
                                                iconColor: _selectedSubtitle != null
                                                    ? PlixTheme.plexGold
                                                    : Colors.white70,
                                                tooltip: 'Subtitles',
                                                onPressed: _showSubtitleSelector,
                                                onLeft: () => _currentItem.isEpisode
                                                    ? _nextEpBtnFocusNode.requestFocus()
                                                    : _playPauseBtnFocusNode.requestFocus(),
                                                onRight: () => _qualityBtnFocusNode.requestFocus(),
                                                onUp: () => _scrubberFocusNode.requestFocus(),
                                                onDown: _hideControlsImmediate,
                                                onFocus: _scheduleHideControls,
                                              ),

                                              const SizedBox(width: 24),

                                              // Quality button
                                              _PlayerIconButton(
                                                focusNode: _qualityBtnFocusNode,
                                                icon: Icons.tune_rounded,
                                                iconColor: _selectedQuality.isDirectPlay
                                                    ? Colors.white70
                                                    : PlixTheme.plexGold,
                                                tooltip: 'Quality',
                                                onPressed: _showQualitySelector,
                                                onLeft: () => _subtitleBtnFocusNode.requestFocus(),
                                                onRight: () => Platform.isWindows
                                                    ? _fullscreenBtnFocusNode.requestFocus()
                                                    : ((_currentItem.isEpisode && _currentItem.grandparentRatingKey != null)
                                                        ? _seriesBtnFocusNode.requestFocus()
                                                        : null),
                                                onUp: () => _scrubberFocusNode.requestFocus(),
                                                onDown: _hideControlsImmediate,
                                                onFocus: _scheduleHideControls,
                                              ),

                                              // Fullscreen button (Windows)
                                              if (Platform.isWindows) ...[
                                                const SizedBox(width: 24),
                                                _PlayerIconButton(
                                                  focusNode: _fullscreenBtnFocusNode,
                                                  icon: _isFullScreen
                                                      ? Icons.fullscreen_exit_rounded
                                                      : Icons.fullscreen_rounded,
                                                  iconColor: _isFullScreen
                                                      ? PlixTheme.plexGold
                                                      : Colors.white,
                                                  tooltip: _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
                                                  onPressed: _toggleFullScreen,
                                                  onLeft: () => _qualityBtnFocusNode.requestFocus(),
                                                  onRight: (_currentItem.isEpisode && _currentItem.grandparentRatingKey != null)
                                                      ? () => _seriesBtnFocusNode.requestFocus()
                                                      : null,
                                                  onUp: () => _scrubberFocusNode.requestFocus(),
                                                  onDown: _hideControlsImmediate,
                                                  onFocus: _scheduleHideControls,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),

                                        // Right corner: Rectangular "Go to series" button (Episodes only)
                                        if (_currentItem.isEpisode && _currentItem.grandparentRatingKey != null)
                                          Positioned(
                                            right: 0,
                                            child: _GoToSeriesButton(
                                              focusNode: _seriesBtnFocusNode,
                                              onPressed: _goToSeries,
                                              onLeft: () {
                                                if (Platform.isWindows) {
                                                  _fullscreenBtnFocusNode.requestFocus();
                                                } else {
                                                  _speedBtnFocusNode.requestFocus();
                                                }
                                              },
                                              onRight: () {},
                                              onUp: () => _scrubberFocusNode.requestFocus(),
                                              onDown: _hideControlsImmediate,
                                              onFocus: _scheduleHideControls,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Quick Seek Progress Bar Overlay (shows when controls are hidden and user skips/rewinds)
              if (!_showControls && _isQuickSeeking)
                Positioned(
                  left: 48,
                  right: 48,
                  bottom: 36,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: PlixTheme.plexGold.withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            activeTrackColor: PlixTheme.plexGold,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: PlixTheme.plexGold,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: progress,
                            min: 0.0,
                            max: maxMs,
                            onChanged: null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(Duration(milliseconds: effectiveProgressMs.toInt())),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatDuration(Duration(milliseconds: _durationMs)),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Skip Intro Floating Button
              if (_showSkipIntroButton)
                Positioned(
                  right: 48,
                  bottom: _showControls ? 160 : 48,
                  child: Focus(
                    focusNode: _skipIntroFocusNode,
                    child: Builder(
                      builder: (ctx) {
                        final isFocused = Focus.of(ctx).hasFocus;
                        return InkWell(
                          onTap: _skipIntro,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? PlixTheme.plexGold
                                  : Colors.black.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: PlixTheme.plexGold,
                                width: 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: PlixTheme.plexGold.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.skip_next_rounded,
                                  color: isFocused ? Colors.black : PlixTheme.plexGold,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Skip Intro',
                                  style: TextStyle(
                                    color: isFocused ? Colors.black : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
}

class _OsdBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isHighlight;
  final Color? color;

  const _OsdBadge({
    required this.label,
    this.icon,
    this.isHighlight = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? (isHighlight ? PlixTheme.plexGold : Colors.white70);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight ? effectiveColor.withOpacity(0.18) : Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHighlight ? effectiveColor : Colors.white30,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: effectiveColor, size: 13),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: effectiveColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isPrimary;
  final Color? iconColor;
  final FocusNode? focusNode;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onFocus;
  final String? badgeText;

  const _PlayerIconButton({
    required this.icon,
    this.onPressed,
    required this.tooltip,
    this.isPrimary = false,
    this.iconColor,
    this.focusNode,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onFocus,
    this.badgeText,
  });

  @override
  State<_PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<_PlayerIconButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _PlayerIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        widget.onFocus?.call();
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
    final isPri = widget.isPrimary;
    final size = isPri ? 52.0 : 44.0;
    final iconSize = isPri ? 34.0 : 26.0;

    final isEnabled = widget.onPressed != null;
    final activeGlow = _isFocused || _isHovered;

    final bgColor = isPri
        ? (activeGlow ? PlixTheme.plexGoldLight : PlixTheme.plexGold)
        : !isEnabled
            ? (activeGlow ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.04))
            : (activeGlow ? PlixTheme.cardFocused : Colors.white.withOpacity(0.15));

    final fgColor = isPri
        ? Colors.black
        : !isEnabled
            ? (activeGlow ? Colors.white54 : Colors.white24)
            : (activeGlow ? PlixTheme.plexGold : (widget.iconColor ?? Colors.white));

    final borderColor = !isEnabled
        ? (activeGlow ? Colors.white38 : Colors.transparent)
        : (activeGlow ? PlixTheme.plexGold : Colors.transparent);

    Widget content = Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onFocus?.call();
            if (widget.onLeft != null) {
              widget.onLeft!();
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            widget.onFocus?.call();
            if (widget.onRight != null) {
              widget.onRight!();
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowDown) {
            if (widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            if (widget.onPressed != null) {
              widget.onPressed!();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: activeGlow ? (isEnabled ? 1.15 : 1.05) : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovered) {
            if (Platform.isWindows) {
              setState(() {
                _isHovered = hovered;
              });
            }
          },
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: 2.0,
              ),
              boxShadow: (activeGlow && isEnabled)
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Icon(widget.icon, color: fgColor, size: iconSize),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip.isNotEmpty) {
      content = Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 200),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4), width: 1.0),
        ),
        child: content,
      );
    }

    if (widget.badgeText != null) {
      content = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          content,
          Positioned(
            top: -14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.badgeText!,
                style: TextStyle(
                  color: PlixTheme.plexGold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }
}

class _GoToSeriesButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onFocus;

  const _GoToSeriesButton({
    required this.focusNode,
    required this.onPressed,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onFocus,
  });

  @override
  State<_GoToSeriesButton> createState() => _GoToSeriesButtonState();
}

class _GoToSeriesButtonState extends State<_GoToSeriesButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
      if (widget.focusNode.hasFocus) {
        widget.onFocus?.call();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeGlow = _isFocused || _isHovered;
    final bgColor = activeGlow ? PlixTheme.cardFocused : Colors.white.withOpacity(0.15);
    final fgColor = activeGlow ? PlixTheme.plexGold : Colors.white;

    Widget btn = Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onFocus?.call();
            if (widget.onLeft != null) {
              widget.onLeft!();
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            widget.onFocus?.call();
            if (widget.onRight != null) {
              widget.onRight!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled; // Remote right press does nothing
          } else if (key == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowDown) {
            if (widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: activeGlow ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovered) {
            if (Platform.isWindows) {
              setState(() {
                _isHovered = hovered;
              });
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: activeGlow ? PlixTheme.plexGold : Colors.white24,
                width: activeGlow ? 2.0 : 1.0,
              ),
              boxShadow: activeGlow
                  ? [
                      BoxShadow(
                        color: PlixTheme.plexGold.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tv_rounded, color: fgColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Go to series',
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: 'Go to series page',
      waitDuration: const Duration(milliseconds: 200),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4), width: 1.0),
      ),
      child: btn,
    );
  }
}

class _PlaybackOptionItem {
  final String label;
  final String? codec;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlaybackOptionItem({
    required this.label,
    this.codec,
    required this.isSelected,
    required this.onTap,
  });
}

class _PlaybackOptionSelector extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<_PlaybackOptionItem> items;
  final int initialSelectedIndex;

  const _PlaybackOptionSelector({
    required this.title,
    required this.icon,
    required this.items,
    required this.initialSelectedIndex,
  });

  @override
  State<_PlaybackOptionSelector> createState() => _PlaybackOptionSelectorState();
}

class _PlaybackOptionSelectorState extends State<_PlaybackOptionSelector> {
  late final ScrollController _scrollController;
  bool _canScrollDown = false;

  @override
  void initState() {
    super.initState();
    final initialOffset = widget.initialSelectedIndex > 1 ? (widget.initialSelectedIndex * 56.0) : 0.0;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_updateScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScroll();
      if (widget.initialSelectedIndex > 1 && _scrollController.hasClients) {
        final targetOffset = (widget.initialSelectedIndex * 56.0).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _updateScroll() {
    if (_scrollController.hasClients) {
      final canDown = _scrollController.position.pixels < _scrollController.position.maxScrollExtent - 8;
      if (canDown != _canScrollDown) {
        setState(() {
          _canScrollDown = canDown;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        padding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: PlixTheme.plexGold, size: 24),
                const SizedBox(width: 12),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: PlixTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (context, idx) {
                  final item = widget.items[idx];
                  return _SubtitleDialogOption(
                    autofocus: idx == widget.initialSelectedIndex,
                    label: item.label,
                    codec: item.codec,
                    isSelected: item.isSelected,
                    onTap: item.onTap,
                  );
                },
              ),
            ),
            if (_canScrollDown) ...[
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: PlixTheme.plexGold.withOpacity(0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'More options below',
                      style: TextStyle(
                        color: PlixTheme.plexGold.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubtitleDialogOption extends StatefulWidget {
  final String label;
  final String? codec;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _SubtitleDialogOption({
    required this.label,
    this.codec,
    required this.isSelected,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  State<_SubtitleDialogOption> createState() => _SubtitleDialogOptionState();
}

class _SubtitleDialogOptionState extends State<_SubtitleDialogOption> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _handleFocus() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (!Platform.isWindows && _focusNode.hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovered) {
          if (Platform.isWindows) {
            setState(() {
              _isHovered = hovered;
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          decoration: BoxDecoration(
            color: highlighted
                ? PlixTheme.cardFocused
                : (widget.isSelected ? PlixTheme.plexGold.withOpacity(0.15) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted
                  ? PlixTheme.plexGold
                  : (widget.isSelected ? PlixTheme.plexGold.withOpacity(0.5) : Colors.transparent),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: widget.isSelected ? PlixTheme.plexGold : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: (highlighted || widget.isSelected) ? PlixTheme.plexGold : Colors.white,
                    fontSize: 15,
                    fontWeight: (highlighted || widget.isSelected) ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (widget.codec != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.codec!,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;
  late String _timeString;

  @override
  void initState() {
    super.initState();
    _timeString = _formatTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final newTime = _formatTime(DateTime.now());
        if (newTime != _timeString) {
          setState(() {
            _timeString = newTime;
          });
        }
      }
    });
  }

  String _formatTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            _timeString,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerDialogButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool autofocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback onPressed;

  const _PlayerDialogButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    this.isPrimary = false,
    this.autofocus = false,
    this.onLeft,
    this.onRight,
    required this.onPressed,
  });

  @override
  State<_PlayerDialogButton> createState() => _PlayerDialogButtonState();
}

class _PlayerDialogButtonState extends State<_PlayerDialogButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isPrimary
        ? (_isFocused ? PlixTheme.plexGoldLight : PlixTheme.plexGold)
        : (_isFocused ? PlixTheme.cardFocused : Colors.white12);
    final fgColor = widget.isPrimary ? Colors.black : Colors.white;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
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
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (hovered) {
          if (Platform.isWindows && hovered) {
            widget.focusNode.requestFocus();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? PlixTheme.plexGold : Colors.transparent,
              width: 2.0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: PlixTheme.plexGold.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: fgColor, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}