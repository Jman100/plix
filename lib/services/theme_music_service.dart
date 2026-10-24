import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'jellyfin_auth_service.dart';
import 'plex_media_service.dart';
import 'plix_device_helper.dart';
import 'update_service.dart';

class ThemeMusicService {
  static final ThemeMusicService instance = ThemeMusicService._internal();
  ThemeMusicService._internal();

  String? _currentShowKey;
  String? get currentShowKey => _currentShowKey;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  final Map<Object, String> _activeScreenTokens = {};
  Timer? _fadeTimer;
  Timer? _winHeartbeatTimer;

  // Windows MediaKit player
  Player? _windowsPlayer;
  StreamSubscription<double>? _winVolumeSub;
  StreamSubscription<bool>? _winCompletedSub;

  // Android VideoPlayerController
  VideoPlayerController? _androidController;

  static const double windowsMaxVolume = 25.0;
  static const double androidMaxVolume = 0.25;

  static String normalizeKey(String? key) {
    if (key == null) return '';
    return key
        .replaceAll('/library/metadata/', '')
        .replaceAll('/Items/', '')
        .replaceAll('/children', '')
        .trim();
  }

  static bool isSameShow(String? a, String? b) {
    if (a == null || b == null) return false;
    final normA = normalizeKey(a);
    final normB = normalizeKey(b);
    if (normA.isEmpty || normB.isEmpty) return false;
    return normA == normB;
  }

  void registerScreen(Object token, String showKey) {
    final normShowKey = normalizeKey(showKey);
    if (_currentShowKey != null && !isSameShow(_currentShowKey, normShowKey)) {
      _activeScreenTokens.clear();
      stopImmediate(clearScreens: false);
    }
    _activeScreenTokens[token] = normShowKey;
    _currentShowKey = normShowKey;
  }

  void unregisterScreen(Object token) {
    _activeScreenTokens.remove(token);
    final hasActiveScreenForCurrentShow = _activeScreenTokens.values
        .any((k) => isSameShow(k, _currentShowKey));
    if (!hasActiveScreenForCurrentShow) {
      if (_activeScreenTokens.isEmpty) {
        stopImmediate(clearScreens: true);
      } else {
        fadeOutAndStop();
      }
    }
  }

  Future<void> playThemeForShow({
    required String showKey,
    required String themePath,
    required PlexMediaService mediaService,
    required String clientId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('play_tv_show_themes') ?? true;
      if (!enabled) return;
    } catch (_) {}

    final normShowKey = normalizeKey(showKey);

    // Guard: Do not play if no active screen is registered for this show!
    if (!_activeScreenTokens.values.any((k) => isSameShow(k, normShowKey))) {
      return;
    }

    // If already playing for this exact show, keep playing continuously without restarting!
    if (isSameShow(_currentShowKey, normShowKey) && _isPlaying) {
      return;
    }

    // New show or restarting: stop any previous playback immediately without dropping current screen token
    await stopImmediate(clearScreens: false);

    // Re-check after stopping previous playback (in case screen was closed during await)
    if (!_activeScreenTokens.values.any((k) => isSameShow(k, normShowKey))) {
      return;
    }

    _currentShowKey = normShowKey;
    _isPlaying = true;
    _fadeTimer?.cancel();
    _winHeartbeatTimer?.cancel();

    String themeUrl = themePath;
    if (!themePath.startsWith('http')) {
      final sep = themePath.contains('?') ? '&' : '?';
      themeUrl = mediaService.server.isJellyfin
          ? '${mediaService.baseUrl}$themePath${sep}api_key=${mediaService.token}'
          : '${mediaService.baseUrl}$themePath${sep}X-Plex-Token=${mediaService.token}';
    } else if (mediaService.server.isJellyfin && themeUrl.startsWith(mediaService.baseUrl) && !themePath.contains('api_key=')) {
      final sep = themePath.contains('?') ? '&' : '?';
      themeUrl = '$themePath${sep}api_key=${mediaService.token}';
    }

    final isJellyfinServerUrl = mediaService.server.isJellyfin && themeUrl.startsWith(mediaService.baseUrl);
    final isPlexServerUrl = !mediaService.server.isJellyfin && themeUrl.startsWith(mediaService.baseUrl);

    final Map<String, String>? headers;
    if (isJellyfinServerUrl) {
      headers = {
        'Authorization': JellyfinAuthService.buildAuthHeader(
          clientId: clientId,
          clientName: PlixDeviceHelper.clientName,
          version: UpdateService.currentVersion,
          token: mediaService.token,
          deviceName: PlixDeviceHelper.deviceName,
        ),
        'X-Emby-Token': mediaService.token,
      };
    } else if (isPlexServerUrl) {
      headers = {
        'X-Plex-Token': mediaService.token,
        'X-Plex-Client-Identifier': clientId,
      };
    } else {
      headers = null;
    }

    try {
      if (Platform.isWindows) {
        _windowsPlayer ??= Player();
        final p = _windowsPlayer!;

        _winVolumeSub?.cancel();
        _winCompletedSub?.cancel();

        await p.setVolume(0.0);
        await p.open(Media(themeUrl, httpHeaders: headers));
        if (!_isPlaying || !_activeScreenTokens.values.any((k) => isSameShow(k, normShowKey))) {
          await p.stop();
          _isPlaying = false;
          _currentShowKey = null;
          return;
        }
        // Single play: no looping
        await p.setPlaylistMode(PlaylistMode.none);

        // Guard: whenever MPV/media_kit attempts to raise volume above 25.0, clamp it
        _winVolumeSub = p.stream.volume.listen((vol) {
          if (_isPlaying && vol > (windowsMaxVolume + 0.1)) {
            p.setVolume(windowsMaxVolume);
          }
        });

        // When playback completes once, stop and reset
        _winCompletedSub = p.stream.completed.listen((completed) {
          if (completed && _isPlaying) {
            _isPlaying = false;
            _currentShowKey = null;
            _activeScreenTokens.clear();
          }
        });

        // Fade in to 25.0 over 2.0s (20 steps of 100ms) starting ONLY once audio actually begins playing
        int step = 0;
        const totalSteps = 20;
        _fadeTimer?.cancel();
        _fadeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (!_isPlaying) {
            timer.cancel();
            return;
          }
          if (p.state.playing && p.state.position > Duration.zero) {
            step++;
            final vol = (windowsMaxVolume * (step / totalSteps)).clamp(0.0, windowsMaxVolume);
            p.setVolume(vol);
            if (step >= totalSteps) {
              timer.cancel();
              p.setVolume(windowsMaxVolume);
              // Start persistent volume guard heartbeat on Windows
              _winHeartbeatTimer = Timer.periodic(const Duration(milliseconds: 250), (hb) {
                if (!_isPlaying || _windowsPlayer == null) {
                  hb.cancel();
                  return;
                }
                if (_windowsPlayer!.state.volume > (windowsMaxVolume + 0.1)) {
                  _windowsPlayer!.setVolume(windowsMaxVolume);
                }
              });
            }
          }
        });
      } else {
        await _androidController?.dispose();
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(themeUrl),
          httpHeaders: headers ?? const {},
        );
        _androidController = controller;
        await controller.initialize();
        if (!_isPlaying || !_activeScreenTokens.values.any((k) => isSameShow(k, normShowKey))) {
          await controller.dispose();
          if (_androidController == controller) _androidController = null;
          _isPlaying = false;
          _currentShowKey = null;
          return;
        }
        // Single play: no looping
        await controller.setLooping(false);
        controller.addListener(() {
          if (controller.value.isInitialized &&
              controller.value.duration > Duration.zero &&
              controller.value.position >= controller.value.duration &&
              !controller.value.isPlaying &&
              _isPlaying) {
            _isPlaying = false;
            _currentShowKey = null;
            _activeScreenTokens.clear();
          }
        });
        await controller.setVolume(0.0);
        await controller.play();

        // Fade in to 0.25 over 2.0s (20 steps of 100ms) starting once controller begins playing
        int step = 0;
        const totalSteps = 20;
        _fadeTimer?.cancel();
        _fadeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (!_isPlaying || _androidController != controller) {
            timer.cancel();
            return;
          }
          if (controller.value.isPlaying && controller.value.position > Duration.zero) {
            step++;
            final vol = (androidMaxVolume * (step / totalSteps)).clamp(0.0, androidMaxVolume);
            controller.setVolume(vol);
            if (step >= totalSteps) {
              timer.cancel();
              controller.setVolume(androidMaxVolume);
            }
          }
        });
      }
    } catch (_) {
      _isPlaying = false;
      _currentShowKey = null;
    }
  }

  Future<void> fadeOutAndStop({Duration duration = const Duration(milliseconds: 800)}) async {
    if (!_isPlaying) return;
    _fadeTimer?.cancel();
    _winHeartbeatTimer?.cancel();

    int step = 0;
    const totalSteps = 10;
    final stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ totalSteps);

    if (Platform.isWindows) {
      final p = _windowsPlayer;
      if (p == null) {
        _isPlaying = false;
        _currentShowKey = null;
        return;
      }
      final startVol = p.state.volume;
      _fadeTimer = Timer.periodic(stepDuration, (timer) async {
        step++;
        final vol = (startVol * (1.0 - (step / totalSteps))).clamp(0.0, windowsMaxVolume);
        try {
          await p.setVolume(vol);
        } catch (_) {}
        if (step >= totalSteps) {
          timer.cancel();
          _isPlaying = false;
          _currentShowKey = null;
          try {
            await p.stop();
          } catch (_) {}
        }
      });
    } else {
      final c = _androidController;
      if (c == null) {
        _isPlaying = false;
        _currentShowKey = null;
        return;
      }
      final startVol = c.value.volume;
      _fadeTimer = Timer.periodic(stepDuration, (timer) async {
        step++;
        final vol = (startVol * (1.0 - (step / totalSteps))).clamp(0.0, androidMaxVolume);
        try {
          await c.setVolume(vol);
        } catch (_) {}
        if (step >= totalSteps) {
          timer.cancel();
          _isPlaying = false;
          _currentShowKey = null;
          try {
            await c.pause();
            await c.dispose();
            if (_androidController == c) _androidController = null;
          } catch (_) {}
        }
      });
    }
  }

  Future<void> stopImmediate({bool clearScreens = true}) async {
    _fadeTimer?.cancel();
    _winHeartbeatTimer?.cancel();
    _isPlaying = false;
    _currentShowKey = null;
    if (clearScreens) {
      _activeScreenTokens.clear();
    }

    _winVolumeSub?.cancel();
    _winCompletedSub?.cancel();

    try {
      if (Platform.isWindows) {
        await _windowsPlayer?.stop();
      } else {
        await _androidController?.pause();
        await _androidController?.dispose();
        _androidController = null;
      }
    } catch (_) {}
  }
}
