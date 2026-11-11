import 'package:flutter_test/flutter_test.dart';
import 'package:plix/services/update_service.dart';

void main() {
  group('UpdateService Tests', () {
    test('currentVersion and versionCode are updated to 1.8.6 (48)', () {
      expect(UpdateService.currentVersion, equals('1.8.6'));
      expect(UpdateService.currentVersionCode, equals(48));
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
        'windowsSha256': 'a1b2c3d4e5',
        'apkSha256': 'f6g7h8i9j0',
        'linuxSha256': '1234567890',
        'linuxArchSha256': '0987654321',
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
      expect(info.getExpectedSha256ForTarget('plix_windows.exe'), equals('a1b2c3d4e5'));
      expect(info.getExpectedSha256ForTarget('plix_android.apk'), equals('f6g7h8i9j0'));
      expect(info.getExpectedSha256ForTarget('plix_linux.deb'), equals('1234567890'));
      expect(info.getExpectedSha256ForTarget('plix_linux_arch.pkg.tar.zst'), equals('0987654321'));
    });

    test('isTrustedUpdateUri strictly validates schemes and hosts', () {
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe')), isTrue);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://objects.githubusercontent.com/github-production-release-asset-2e65be/plix_windows.exe')), isTrue);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://plix.jman100.com/plix_windows.exe')), isTrue);

      // Insecure plain HTTP must be rejected
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('http://github.com/Jman100/plix/releases/latest/download/plix_windows.exe')), isFalse);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('http://plix.jman100.com/plix.json')), isFalse);

      // Spoofed or lookalike domains must be rejected
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://plix.jman100.com.evil.net/plix_windows.exe')), isFalse);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://10.evil.com/plix_windows.exe')), isFalse);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://192.168.1.100/plix_windows.exe')), isFalse);
      expect(UpdateService.isTrustedUpdateUri(Uri.parse('https://evilgithub.com/download/plix_windows.exe')), isFalse);
    });
  });
}
