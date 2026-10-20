import 'dart:async';
import 'package:flutter/services.dart';

enum MediaKeyAction {
  playPause,
  play,
  pause,
  fastForward,
  rewind,
}

class MediaButtonService {
  static const MethodChannel _channel = MethodChannel('com.plix.plix/media_keys');
  static final MediaButtonService _instance = MediaButtonService._internal();

  factory MediaButtonService() => _instance;

  final StreamController<MediaKeyAction> _actionController =
      StreamController<MediaKeyAction>.broadcast();

  Stream<MediaKeyAction> get onMediaAction => _actionController.stream;

  MediaButtonService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onMediaKey') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final actionStr = args?['action'] as String?;
      switch (actionStr) {
        case 'play_pause':
          _actionController.add(MediaKeyAction.playPause);
          break;
        case 'play':
          _actionController.add(MediaKeyAction.play);
          break;
        case 'pause':
          _actionController.add(MediaKeyAction.pause);
          break;
        case 'fast_forward':
          _actionController.add(MediaKeyAction.fastForward);
          break;
        case 'rewind':
          _actionController.add(MediaKeyAction.rewind);
          break;
      }
    }
  }

  Future<void> setPlayerActive(bool active) async {
    try {
      await _channel.invokeMethod('setPlayerActive', {'active': active});
    } catch (_) {}
  }
}
