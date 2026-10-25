import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

enum DuoPosture {
  none,
  closed,
  fullyOpen,
  tabletop,
  book,
}

class IPhoneDuoInfo {
  final bool isDuo;
  final DuoPosture posture;
  final double hingeAngle;
  final double foldCoord;
  final double foldBand;

  const IPhoneDuoInfo({
    this.isDuo = false,
    this.posture = DuoPosture.none,
    this.hingeAngle = 0.0,
    this.foldCoord = 475.5,
    this.foldBand = 40.0,
  });

  factory IPhoneDuoInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const IPhoneDuoInfo();
    final isDuo = map['isDuo'] as bool? ?? false;
    final postureStr = map['posture'] as String? ?? 'none';
    final angle = (map['angle'] as num?)?.toDouble() ?? 0.0;
    final fold = (map['foldY'] as num?)?.toDouble() ?? 475.5;
    final band = (map['foldBand'] as num?)?.toDouble() ?? 40.0;

    DuoPosture p = DuoPosture.none;
    if (isDuo) {
      switch (postureStr) {
        case 'closed':
          p = DuoPosture.closed;
          break;
        case 'fullyOpen':
          p = DuoPosture.fullyOpen;
          break;
        case 'tabletop':
          p = DuoPosture.tabletop;
          break;
        case 'book':
          p = DuoPosture.book;
          break;
        default:
          p = DuoPosture.closed;
      }
    }

    return IPhoneDuoInfo(
      isDuo: isDuo,
      posture: p,
      hingeAngle: angle,
      foldCoord: fold,
      foldBand: band,
    );
  }
}

class IPhoneDuoService {
  static const MethodChannel _channel = MethodChannel('com.plix.plix/native_player');
  static bool _initialized = false;
  static bool get isInitialized => _initialized;
  static IPhoneDuoInfo _currentInfo = const IPhoneDuoInfo();
  static final _postureController = StreamController<IPhoneDuoInfo>.broadcast();

  static IPhoneDuoInfo get currentInfo => _currentInfo;
  static bool get isDuo => _currentInfo.isDuo;
  static DuoPosture get currentPosture => _currentInfo.posture;
  static Stream<IPhoneDuoInfo> get onPostureChanged => _postureController.stream;

  static Future<IPhoneDuoInfo> init() async {
    if (!Platform.isIOS) {
      _currentInfo = const IPhoneDuoInfo(isDuo: false, posture: DuoPosture.none);
      return _currentInfo;
    }

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDuoInfo');
      _currentInfo = IPhoneDuoInfo.fromMap(res);
      _initialized = true;
    } catch (_) {
      _currentInfo = const IPhoneDuoInfo(isDuo: false, posture: DuoPosture.none);
    }
    return _currentInfo;
  }

  static void updateFromNative(Map<dynamic, dynamic>? map) {
    if (!Platform.isIOS) return;
    _currentInfo = IPhoneDuoInfo.fromMap(map);
    _postureController.add(_currentInfo);
  }

  static Future<void> setSimulatedPosture(DuoPosture? posture) async {
    if (!Platform.isIOS) return;
    String? pStr;
    if (posture != null) {
      switch (posture) {
        case DuoPosture.closed:
          pStr = 'closed';
          break;
        case DuoPosture.fullyOpen:
          pStr = 'fullyOpen';
          break;
        case DuoPosture.tabletop:
          pStr = 'tabletop';
          break;
        case DuoPosture.book:
          pStr = 'book';
          break;
        case DuoPosture.none:
          pStr = null;
          break;
      }
    }
    try {
      await _channel.invokeMethod('setDuoPosture', pStr != null ? {'posture': pStr} : null);
    } catch (_) {}
  }

  /// Returns true ONLY if on iPhone Duo in tabletop (laptop) posture.
  /// Strictly returns false for any other iOS or Android device.
  static bool isTabletop(BuildContext context) {
    if (!Platform.isIOS) return false;
    if (!_currentInfo.isDuo) return false;
    return _currentInfo.posture == DuoPosture.tabletop &&
        MediaQuery.of(context).orientation == Orientation.portrait;
  }

  /// Returns true ONLY if on iPhone Duo in book posture.
  /// Strictly returns false for any other device.
  static bool isBook(BuildContext context) {
    if (!Platform.isIOS) return false;
    if (!_currentInfo.isDuo) return false;
    return _currentInfo.posture == DuoPosture.book;
  }
}
