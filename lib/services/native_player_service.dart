import 'iphone_duo_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativePlayerService {
  static const MethodChannel _channel = MethodChannel('com.plix.plix/native_player');

  int? _pendingAudioTrackIndex;
  String? _pendingAudioLanguage;
  String? _pendingAudioLabel;

  final _positionController = StreamController<int>.broadcast();
  final _durationController = StreamController<int>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _endedController = StreamController<void>.broadcast();
  final _subtitleCueController = StreamController<String>.broadcast();
  final _subtitleBitmapCueController = StreamController<Uint8List?>.broadcast();
  final _pipModeController = StreamController<bool>.broadcast();
  final _physicalOrientationController = StreamController<String>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();

  Stream<int> get onPositionUpdate => _positionController.stream;
  Stream<int> get onDurationReady => _durationController.stream;
  Stream<bool> get onIsPlayingChanged => _isPlayingController.stream;
  Stream<String> get onPlayerError => _errorController.stream;
  Stream<void> get onPlayerEnded => _endedController.stream;
  Stream<String> get onSubtitleCue => _subtitleCueController.stream;
  Stream<Uint8List?> get onSubtitleBitmapCue => _subtitleBitmapCueController.stream;
  Stream<bool> get onPipModeChanged => _pipModeController.stream;
  Stream<String> get onDevicePhysicalOrientationChanged => _physicalOrientationController.stream;
  Stream<bool> get onBufferingChanged => _bufferingController.stream;

  static bool get useMediaKit =>
      Platform.isWindows || Platform.isIOS || Platform.isLinux || Platform.isMacOS;

  static String get defaultHwdecMode => Platform.isLinux ? 'no' : 'auto-safe';

  static String _hwdecMode = Platform.isLinux ? 'no' : 'auto-safe';
  static String get hwdecMode => _hwdecMode;

  static Future<void> loadSavedHwdecMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hwdecMode = prefs.getString('desktop_hwdec_mode') ?? defaultHwdecMode;
    } catch (_) {}
  }

  Future<void> setHwdecMode(String mode) async {
    _hwdecMode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('desktop_hwdec_mode', mode);
    } catch (_) {}
    if (_mediaKitPlayer != null) {
      _applyMpvOptimizations(_mediaKitPlayer!);
    }
  }

  static void _applyMpvOptimizations(Player p) {
    try {
      final dynamic plat = p.platform;
      plat.setProperty('rebase-start-time', 'yes');
      plat.setProperty('hr-seek', 'yes');

      // CRITICAL: vo MUST be libmpv to render internally into Flutter's texture.
      plat.setProperty('vo', 'libmpv');
      plat.setProperty('keep-open', 'yes');

      // Hardware decoding: 'no' (Software) by default on Linux matches the official Plex app,
      // eliminating driver-level VA-API/Mesa slice corruption and grey macroblock artifacts.
      plat.setProperty('hwdec', _hwdecMode);

      // Disable HDR peak luminance compute shader on desktop OpenGL (prevents grey grid/tile artifacts on 10-bit/HDR)
      plat.setProperty('hdr-compute-peak', 'no');
      plat.setProperty('tone-mapping', 'bt.2446a');

      // Error resilience: suppress broken/corrupt frames rather than displaying grey macroblock garbage
      plat.setProperty('vd-lavc-show-all', 'no');
      plat.setProperty('vd-lavc-check-hw-profile', 'yes');
      plat.setProperty('vd-lavc-fast', 'no');
      plat.setProperty('vd-lavc-threads', '0'); // Multi-threaded CPU decoding across all cores

      // Prevent frame dropping
      plat.setProperty('framedrop', 'no');

      // Network buffer and cache settings for smooth streaming without starvation
      plat.setProperty('cache', 'yes');
      plat.setProperty('demuxer-max-bytes', '157286400'); // 150 MB buffer
      plat.setProperty('demuxer-max-back-bytes', '52428800'); // 50 MB back buffer
      plat.setProperty('demuxer-readahead-secs', '30');
      plat.setProperty('demuxer-lavf-buffersize', '1048576'); // 1 MB buffer for avformat
      plat.setProperty('network-timeout', '30');
    } catch (_) {}
  }

  Player? _mediaKitPlayer;
  VideoController? _mediaKitVideoController;
  final List<StreamSubscription> _mediaKitSubscriptions = [];

  VideoController? get videoController => _mediaKitVideoController;
  VideoController? get windowsVideoController => _mediaKitVideoController;

  NativePlayerService() {
    _channel.setMethodCallHandler(_handleNativeCall);
    if (useMediaKit) {
      _initMediaKitPlayer();
    }
  }

  void _initMediaKitPlayer() {
    try {
      final p = Player();
      _mediaKitPlayer = p;
      _mediaKitVideoController = VideoController(
        p,
        configuration: VideoControllerConfiguration(
          vo: 'libmpv',
          hwdec: _hwdecMode,
        ),
      );

      _applyMpvOptimizations(p);

      _mediaKitSubscriptions.add(p.stream.position.listen((pos) {
        _positionController.add(pos.inMilliseconds);
      }));

      _mediaKitSubscriptions.add(p.stream.duration.listen((dur) {
        if (dur.inMilliseconds > 0) {
          _durationController.add(dur.inMilliseconds);
        }
      }));

      _mediaKitSubscriptions.add(p.stream.playing.listen((playing) {
        _isPlayingController.add(playing);
      }));

      _mediaKitSubscriptions.add(p.stream.buffering.listen((buffering) {
        _bufferingController.add(buffering);
      }));

      _mediaKitSubscriptions.add(p.stream.completed.listen((completed) {
        if (completed) {
          _endedController.add(null);
        }
      }));

      _mediaKitSubscriptions.add(p.stream.tracks.listen((tracks) {
        if (_pendingAudioTrackIndex != null &&
            _pendingAudioTrackIndex! >= 0 &&
            _pendingAudioTrackIndex! < tracks.audio.length) {
          p.setAudioTrack(tracks.audio[_pendingAudioTrackIndex!]);
          _pendingAudioTrackIndex = null;
        } else if (_pendingAudioLanguage != null && tracks.audio.isNotEmpty) {
          final match = tracks.audio.firstWhere(
            (t) => (t.language ?? '').toLowerCase().startsWith(_pendingAudioLanguage!.toLowerCase()),
            orElse: () => AudioTrack.auto(),
          );
          if (match != AudioTrack.auto()) {
            p.setAudioTrack(match);
            _pendingAudioLanguage = null;
          }
        } else if (_pendingAudioLabel != null && tracks.audio.isNotEmpty) {
          final match = tracks.audio.firstWhere(
            (t) => (t.title ?? '').toLowerCase().contains(_pendingAudioLabel!.toLowerCase()),
            orElse: () => AudioTrack.auto(),
          );
          if (match != AudioTrack.auto()) {
            p.setAudioTrack(match);
            _pendingAudioLabel = null;
          }
        }
      }));

      _mediaKitSubscriptions.add(p.stream.error.listen((err) {
        final errStr = err.toString().toLowerCase();
        // Ignore non-fatal network or demuxer warnings (e.g. tcp: ffurl_read returned 0xdfb9b0bb) that do not interrupt playback
        if (errStr.contains('ffurl_read') ||
            errStr.contains('tcp:') ||
            errStr.contains('demux') ||
            errStr.contains('seeking') ||
            errStr.contains('buffering') ||
            errStr.contains('protocol') ||
            errStr.contains('http:')) {
          return;
        }
        if (!p.state.playing) {
          _errorController.add(err.toString());
        }
      }));
    } catch (e) {
      _errorController.add('MediaKit player init error: $e');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPositionUpdate':
        final pos = (call.arguments['position'] as num?)?.toInt() ?? 0;
        final dur = (call.arguments['duration'] as num?)?.toInt() ?? 0;
        _positionController.add(pos);
        if (dur > 0) _durationController.add(dur);
        break;
      case 'onPlayerReady':
        final dur = (call.arguments['duration'] as num?)?.toInt() ?? 0;
        if (dur > 0) _durationController.add(dur);
        break;
      case 'onIsPlayingChanged':
        final isPlaying = call.arguments['isPlaying'] as bool? ?? false;
        _isPlayingController.add(isPlaying);
        break;
      case 'onPlayerEnded':
        _endedController.add(null);
        break;
      case 'onPlayerError':
        final err = call.arguments['error']?.toString() ?? 'Player error';
        _errorController.add(err);
        break;
      case 'onSubtitleCue':
        final cueText = call.arguments['text']?.toString() ?? '';
        _subtitleCueController.add(cueText);
        break;
      case 'onSubtitleBitmapCue':
        final bytes = call.arguments?['bytes'] as Uint8List?;
        _subtitleBitmapCueController.add(bytes);
        break;
      case 'onPipModeChanged':
        final inPip = call.arguments?['isInPip'] as bool? ?? false;
        _pipModeController.add(inPip);
        break;
      case 'onDevicePhysicalOrientationChanged':
        final orientation = call.arguments?['orientation']?.toString() ?? '';
        if (orientation.isNotEmpty) {
          _physicalOrientationController.add(orientation);
        }
        break;
      case 'onBufferingChanged':
        final isBuffering = call.arguments?['isBuffering'] as bool? ?? false;
        _bufferingController.add(isBuffering);
        break;
      case 'onDuoPostureChanged':
        IPhoneDuoService.updateFromNative(call.arguments as Map<dynamic, dynamic>?);
        break;
    }
  }

  Future<String> startVoiceRecognition() async {
    try {
      final res = await _channel.invokeMethod<String>('startVoiceRecognition');
      return res ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> checkAudioSupported(String codec) async {
    if (useMediaKit) {
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('checkAudioSupported', {'codec': codec});
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> play({
    required String url,
    Map<String, String>? headers,
    int positionMs = 0,
  }) async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        _applyMpvOptimizations(_mediaKitPlayer!);
        await _mediaKitPlayer!.open(
          Media(
            url,
            httpHeaders: headers,
            start: positionMs > 0 ? Duration(milliseconds: positionMs) : null,
          ),
          play: true,
        );
      } catch (e) {
        _errorController.add(e.toString());
      }
      return;
    }
    try {
      await _channel.invokeMethod('play', {
        'url': url,
        'headers': headers,
        'positionMs': positionMs,
      });
    } catch (_) {}
  }

  Future<void> pause() async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.pause();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> resume() async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.play();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  Future<void> seekTo(int positionMs) async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.seek(Duration(milliseconds: positionMs));
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('seekTo', {'positionMs': positionMs});
    } catch (_) {}
  }

  Future<void> stop() async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.stop();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        await _mediaKitPlayer!.setRate(speed);
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('setPlaybackSpeed', {'speed': speed});
    } catch (_) {}
  }

  Future<void> setVideoBounds({int x = 0, int y = 0, int? width, int? height}) async {
    if (useMediaKit) return;
    try {
      await _channel.invokeMethod('setVideoBounds', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }

  Future<bool> enterPipMode() async {
    if (useMediaKit) return false;
    try {
      final res = await _channel.invokeMethod<bool>('enterPipMode');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getState() async {
    if (useMediaKit && _mediaKitPlayer != null) {
      final p = _mediaKitPlayer!;
      return {
        'position': p.state.position.inMilliseconds,
        'duration': p.state.duration.inMilliseconds,
        'isPlaying': p.state.playing,
        'buffered': p.state.buffer.inMilliseconds,
      };
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getState');
      return res ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> setSubtitleTrack({
    required bool enabled,
    String? language,
    String? label,
    int? trackIndex,
    String? url,
  }) async {
    if (useMediaKit && _mediaKitPlayer != null) {
      try {
        if (!enabled) {
          await _mediaKitPlayer!.setSubtitleTrack(SubtitleTrack.no());
        } else if (url != null && url.isNotEmpty) {
          await _mediaKitPlayer!.setSubtitleTrack(SubtitleTrack.uri(url, title: label, language: language));
        } else {
          final tracks = _mediaKitPlayer!.state.tracks.subtitle;
          if (trackIndex != null && trackIndex >= 0 && trackIndex < tracks.length) {
            await _mediaKitPlayer!.setSubtitleTrack(tracks[trackIndex]);
          } else if (language != null) {
            final match = tracks.firstWhere(
              (t) => (t.language ?? '').toLowerCase().startsWith(language.toLowerCase()),
              orElse: () => SubtitleTrack.auto(),
            );
            await _mediaKitPlayer!.setSubtitleTrack(match);
          }
        }
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('setSubtitleTrack', {
        'enabled': enabled,
        'language': language,
        'label': label,
        'trackIndex': trackIndex,
      });
    } catch (_) {}
  }

  Future<void> setAudioTrack({
    int? trackIndex,
    String? language,
    String? label,
  }) async {
    if (useMediaKit && _mediaKitPlayer != null) {
      _pendingAudioTrackIndex = trackIndex;
      _pendingAudioLanguage = language;
      _pendingAudioLabel = label;
      try {
        final tracks = _mediaKitPlayer!.state.tracks.audio;
        if (trackIndex != null && trackIndex >= 0 && trackIndex < tracks.length) {
          await _mediaKitPlayer!.setAudioTrack(tracks[trackIndex]);
        } else if (language != null) {
          final match = tracks.firstWhere(
            (t) => (t.language ?? '').toLowerCase().startsWith(language.toLowerCase()),
            orElse: () => AudioTrack.auto(),
          );
          await _mediaKitPlayer!.setAudioTrack(match);
        }
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('setAudioTrack', {
        'trackIndex': trackIndex,
        'language': language,
        'label': label,
      });
    } catch (_) {}
  }

  Future<void> setScreenOffPlayback(bool enabled) async {
    if (useMediaKit) return;
    try {
      await _channel.invokeMethod('setScreenOffPlayback', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  void dispose() {
    for (final s in _mediaKitSubscriptions) {
      s.cancel();
    }
    _mediaKitSubscriptions.clear();
    _mediaKitPlayer?.dispose();
    _positionController.close();
    _durationController.close();
    _isPlayingController.close();
    _errorController.close();
    _endedController.close();
    _subtitleCueController.close();
    _subtitleBitmapCueController.close();
    _pipModeController.close();
    _bufferingController.close();
  }
}
