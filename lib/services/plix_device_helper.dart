import 'dart:io';
import 'package:flutter/services.dart';

class PlixDeviceHelper {
  static String? _cachedDeviceName;

  static String get clientName =>
      Platform.isWindows ? 'Plix for Windows' : 'Plix for Android TV';

  static String get clientPlatform =>
      Platform.isWindows ? 'Windows' : 'Android';

  static String get clientDevice =>
      Platform.isWindows ? 'PC' : 'Android TV';

  static String get clientPlatformVersion =>
      Platform.isWindows ? Platform.operatingSystemVersion : '14';

  static Future<String> initDeviceName() async {
    if (_cachedDeviceName != null && _cachedDeviceName!.isNotEmpty) {
      return _cachedDeviceName!;
    }
    if (Platform.isWindows) {
      try {
        final host = Platform.localHostname;
        _cachedDeviceName = host.isNotEmpty ? host : 'Windows PC';
      } catch (_) {
        _cachedDeviceName = 'Windows PC';
      }
    } else if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.plix.plix/updater');
        final name = await channel.invokeMethod<String>('getDeviceName');
        if (name != null && name.trim().isNotEmpty) {
          _cachedDeviceName = name.trim();
        }
      } catch (_) {}
      _cachedDeviceName ??= 'Android TV';
    } else {
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
    return 'Android TV';
  }
}
