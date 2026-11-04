import 'package:flutter_test/flutter_test.dart';
import 'package:plix/services/update_service.dart';

void main() {
  group('UpdateService Tests', () {
    test('currentVersion and versionCode are updated to 1.7.1 (41)', () {
      expect(UpdateService.currentVersion, equals('1.7.1'));
      expect(UpdateService.currentVersionCode, equals(41));
    });

    test('isVersionNewer correctly compares semver versions', () {
      expect(UpdateService.isVersionNewer('1.7.2', '1.7.1'), isTrue);
      expect(UpdateService.isVersionNewer('1.8.0', '1.7.1'), isTrue);
      expect(UpdateService.isVersionNewer('2.0.0', '1.7.1'), isTrue);
      expect(UpdateService.isVersionNewer('1.7.1', '1.7.1'), isFalse);
      expect(UpdateService.isVersionNewer('1.7.0', '1.7.1'), isFalse);
      expect(UpdateService.isVersionNewer('1.6.0', '1.7.1'), isFalse);
    });

    test('UpdateInfo.fromJson parses Arch Linux URLs and release notes', () {
      final json = {
        'version': '1.7.1',
        'versionCode': 41,
        'apkUrl': 'https://github.com/Jman100/plix/releases/latest/download/plix_android.apk',
        'windowsUrl': 'https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe',
        'linuxUrl': 'https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb',
        'linuxArchUrl': 'https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst',
        'releaseNotes': 'Arch Linux self updater fix',
        'releaseDate': '2026-11-04',
      };

      final info = UpdateInfo.fromJson(
        json,
        currentVersion: '1.7.0',
        currentVersionCode: 40,
      );

      expect(info.version, equals('1.7.1'));
      expect(info.versionCode, equals(41));
      expect(info.hasUpdate, isTrue);
      expect(info.linuxArchUrl, contains('plix_linux_arch.pkg.tar.zst'));
      expect(info.releaseNotes, contains('Arch Linux'));
    });
  });
}
