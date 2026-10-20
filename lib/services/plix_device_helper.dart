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

  static bool isCompact(BuildContext context) {
    return isPortrait(context) || MediaQuery.of(context).size.width < 720;
  }

  static bool isPhone(BuildContext context) {
    if (Platform.isWindows) return false;
    return !_isTelevision || isCompact(context);
  }

  static String get clientName =>
      Platform.isWindows ? 'Plix for Windows' : (_isTelevision ? 'Plix for Android TV' : 'Plix for Android');

  static String get clientPlatform =>
      Platform.isWindows ? 'Windows' : 'Android';

  static String get clientDevice =>
      Platform.isWindows ? 'PC' : (_isTelevision ? 'Android TV' : 'Android Phone');

  static String get clientPlatformVersion =>
      Platform.isWindows ? Platform.operatingSystemVersion : '14';

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
    return _isTelevision ? 'Android TV' : 'Android Phone';
  }
}
