import 'iphone_duo_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

  Player? _windowsPlayer;
  VideoController? _windowsVideoController;
  final List<StreamSubscription> _windowsSubscriptions = [];

  VideoController? get windowsVideoController => _windowsVideoController;

  NativePlayerService() {
    if (Platform.isWindows) {
      _initWindowsPlayer();
    } else {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  void _initWindowsPlayer() {
    try {
      final p = Player();
      _windowsPlayer = p;
      _windowsVideoController = VideoController(p);

      try {
        (p.platform as dynamic).setProperty('rebase-start-time', 'yes');
        (p.platform as dynamic).setProperty('hr-seek', 'yes');
      } catch (_) {}

      _windowsSubscriptions.add(p.stream.position.listen((pos) {
        _positionController.add(pos.inMilliseconds);
      }));

      _windowsSubscriptions.add(p.stream.duration.listen((dur) {
        if (dur.inMilliseconds > 0) {
          _durationController.add(dur.inMilliseconds);
        }
      }));

      _windowsSubscriptions.add(p.stream.playing.listen((playing) {
        _isPlayingController.add(playing);
      }));

      _windowsSubscriptions.add(p.stream.buffering.listen((buffering) {
        _bufferingController.add(buffering);
      }));

      _windowsSubscriptions.add(p.stream.completed.listen((completed) {
        if (completed) {
          _endedController.add(null);
        }
      }));

      _windowsSubscriptions.add(p.stream.tracks.listen((tracks) {
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

      _windowsSubscriptions.add(p.stream.error.listen((err) {
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
      _errorController.add('Windows player init error: $e');
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
    if (Platform.isWindows) {
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
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.open(
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
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.pause();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> resume() async {
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.play();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  Future<void> seekTo(int positionMs) async {
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.seek(Duration(milliseconds: positionMs));
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('seekTo', {'positionMs': positionMs});
    } catch (_) {}
  }

  Future<void> stop() async {
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.stop();
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        await _windowsPlayer!.setRate(speed);
      } catch (_) {}
      return;
    }
    try {
      await _channel.invokeMethod('setPlaybackSpeed', {'speed': speed});
    } catch (_) {}
  }

  Future<void> setVideoBounds({int x = 0, int y = 0, int? width, int? height}) async {
    if (Platform.isWindows) return;
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
    if (Platform.isWindows) return false;
    try {
      final res = await _channel.invokeMethod<bool>('enterPipMode');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getState() async {
    if (Platform.isWindows && _windowsPlayer != null) {
      final p = _windowsPlayer!;
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
    if (Platform.isWindows && _windowsPlayer != null) {
      try {
        if (!enabled) {
          await _windowsPlayer!.setSubtitleTrack(SubtitleTrack.no());
        } else if (url != null && url.isNotEmpty) {
          await _windowsPlayer!.setSubtitleTrack(SubtitleTrack.uri(url, title: label, language: language));
        } else {
          final tracks = _windowsPlayer!.state.tracks.subtitle;
          if (trackIndex != null && trackIndex >= 0 && trackIndex < tracks.length) {
            await _windowsPlayer!.setSubtitleTrack(tracks[trackIndex]);
          } else if (language != null) {
            final match = tracks.firstWhere(
              (t) => (t.language ?? '').toLowerCase().startsWith(language.toLowerCase()),
              orElse: () => SubtitleTrack.auto(),
            );
            await _windowsPlayer!.setSubtitleTrack(match);
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
    if (Platform.isWindows && _windowsPlayer != null) {
      _pendingAudioTrackIndex = trackIndex;
      _pendingAudioLanguage = language;
      _pendingAudioLabel = label;
      try {
        final tracks = _windowsPlayer!.state.tracks.audio;
        if (trackIndex != null && trackIndex >= 0 && trackIndex < tracks.length) {
          await _windowsPlayer!.setAudioTrack(tracks[trackIndex]);
        } else if (language != null) {
          final match = tracks.firstWhere(
            (t) => (t.language ?? '').toLowerCase().startsWith(language.toLowerCase()),
            orElse: () => AudioTrack.auto(),
          );
          await _windowsPlayer!.setAudioTrack(match);
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
    if (Platform.isWindows) return;
    try {
      await _channel.invokeMethod('setScreenOffPlayback', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  void dispose() {
    for (final s in _windowsSubscriptions) {
      s.cancel();
    }
    _windowsSubscriptions.clear();
    _windowsPlayer?.dispose();
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
