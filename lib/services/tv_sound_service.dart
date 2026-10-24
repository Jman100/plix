import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'plix_device_helper.dart';

class TvSoundService {
  static final TvSoundService instance = TvSoundService._();
  TvSoundService._();

  static const MethodChannel _channel = MethodChannel('com.plix.plix/media_keys');
  FocusNode? _lastFocusedNode;
  bool _isNavigating = false;
  bool _initialized = false;

  void init() {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    FocusManager.instance.addListener(_handleFocusChange);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!PlixDeviceHelper.isTelevision) return false;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _isNavigating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isNavigating = false;
        });
      } else if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA) {
        if (FocusManager.instance.primaryFocus != null) {
          playClick();
        }
      }
    }
    return false;
  }

  void _handleFocusChange() {
    if (!PlixDeviceHelper.isTelevision) return;

    final current = FocusManager.instance.primaryFocus;
    if (current != null && current != _lastFocusedNode) {
      _lastFocusedNode = current;
      if (_isNavigating) {
        _isNavigating = false;
        playNavigation();
      }
    }
  }

  void playNavigation() {
    try {
      _channel.invokeMethod('playSystemSound', {'type': 'navigation'});
    } catch (_) {}
  }

  void playClick() {
    try {
      _channel.invokeMethod('playSystemSound', {'type': 'click'});
    } catch (_) {}
  }
}
