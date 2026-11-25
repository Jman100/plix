import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'update_service.dart';

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

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool isPhone(BuildContext context) {
    if (isDesktop) return false;
    if (_isTelevision) return false;
    return !isTablet(context);
  }

  static String get clientName {
    final v = UpdateService.currentVersion;
    if (Platform.isWindows) return 'Plix Windows v$v';
    if (Platform.isLinux) return 'Plix Linux v$v';
    if (Platform.isMacOS) return 'Plix macOS v$v';
    if (Platform.isIOS) return 'Plix iOS v$v';
    return _isTelevision ? 'Plix TV v$v' : 'Plix Android v$v';
  }

  static String get clientPlatform {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    return 'Android';
  }

  static String get clientDevice {
    if (Platform.isWindows) return 'PC';
    if (Platform.isLinux) return _cachedDeviceName ?? 'Linux PC';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isIOS) return _cachedDeviceName ?? 'iPad';
    return _isTelevision ? 'Android TV' : 'Android Phone';
  }

  static String get clientPlatformVersion {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return Platform.operatingSystemVersion;
    }
    return Platform.isIOS ? '16.7' : '14';
  }

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
    } else if (Platform.isLinux) {
      _isTelevision = false;
      try {
        final host = Platform.localHostname;
        _cachedDeviceName = host.isNotEmpty ? host : 'Linux PC';
      } catch (_) {
        _cachedDeviceName = 'Linux PC';
      }
    } else if (Platform.isMacOS) {
      _isTelevision = false;
      _cachedDeviceName = 'Mac';
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
    if (Platform.isLinux) {
      try {
        final host = Platform.localHostname;
        if (host.isNotEmpty) return host;
      } catch (_) {}
      return 'Linux PC';
    }
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isIOS) return 'iPad';
    return _isTelevision ? 'Android TV' : 'Android Phone';
  }

  static Future<void> openYoutubeTrailer(String videoKey, {String? title}) async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.plix.plix/native_player');
        await channel.invokeMethod('openYoutubeTrailer', {
          'videoKey': videoKey,
          if (title != null) 'title': title,
        });
        return;
      } catch (_) {}
    }
    await openUrl('https://www.youtube.com/watch?v=$videoKey');
  }

  static Future<void> openUrl(String url) async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.plix.plix/native_player');
        await channel.invokeMethod('openUrl', {'url': url});
        return;
      } catch (_) {}
    }
    if (Platform.isWindows) {
      try {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        await Process.run('open', [url]);
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        await Process.run('xdg-open', [url]);
      } catch (_) {}
    }
  }
}
