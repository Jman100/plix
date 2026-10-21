import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class PlixDeviceHelper {
  static String? _cachedDeviceName;
  static bool _isTelevision = true;

  static bool get isTelevision => _isTelevision;

  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  static bool isCompact(BuildContext context) {
    return isPortrait(context) || MediaQuery.of(context).size.width < 720;
  }

  static bool isPhone(BuildContext context) {
    if (Platform.isWindows) return false;
    if (_isTelevision) return false;
    return !isTablet(context);
  }

  static String get clientName {
    if (Platform.isWindows) return 'Plix for Windows';
    if (Platform.isIOS) return 'Plix for iOS';
    return _isTelevision ? 'Plix for Android TV' : 'Plix for Android';
  }

  static String get clientPlatform =>
      Platform.isWindows ? 'Windows' : (Platform.isIOS ? 'iOS' : 'Android');

  static String get clientDevice {
    if (Platform.isWindows) return 'PC';
    if (Platform.isIOS) return _cachedDeviceName ?? 'iPad';
    return _isTelevision ? 'Android TV' : 'Android Phone';
  }

  static String get clientPlatformVersion =>
      Platform.isWindows ? Platform.operatingSystemVersion : (Platform.isIOS ? '16.7' : '14');

  static Future<String> initDeviceName() async {
    if (_cachedDeviceName != null && _cachedDeviceName!.isNotEmpty) {
      return _cachedDeviceName!;
    }
    if (Platform.isWindows) {
      _isTelevision = false;
      try {
        final host = Platform.localHostname;
        _cachedDeviceName = host.isNotEmpty ? host : 'Windows PC';
      } catch (_) {
        _cachedDeviceName = 'Windows PC';
      }
    } else if (Platform.isIOS) {
      _isTelevision = false;
      _cachedDeviceName = 'iPad';
    } else if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.plix.plix/updater');
        final tv = await channel.invokeMethod<bool>('isTelevision');
        if (tv != null) {
          _isTelevision = tv;
        }
        final name = await channel.invokeMethod<String>('getDeviceName');
        if (name != null && name.trim().isNotEmpty) {
          _cachedDeviceName = name.trim();
        }
      } catch (_) {}
      _cachedDeviceName ??= _isTelevision ? 'Android TV' : 'Android Phone';
    } else {
      _isTelevision = false;
      _cachedDeviceName = Platform.operatingSystem;
    }
    return _cachedDeviceName!;
  }

  static String get deviceName {
    if (_cachedDeviceName != null && _cachedDeviceName!.isNotEmpty) {
      return _cachedDeviceName!;
    }
    if (Platform.isWindows) {
      try {
        final host = Platform.localHostname;
        if (host.isNotEmpty) return host;
      } catch (_) {}
      return 'Windows PC';
    }
    if (Platform.isIOS) return 'iPad';
    return _isTelevision ? 'Android TV' : 'Android Phone';
  }
}
