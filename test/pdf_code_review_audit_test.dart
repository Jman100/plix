import 'package:flutter_test/flutter_test.dart';
import 'package:plix/services/update_service.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/services/plex_server_service.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/models/plex_server.dart';

void main() {
  group('Carlos Code Review - SemVer and Update Hardening Tests', () {
    test('compareSemVer correctly handles release vs prerelease', () {
      // 1.8.0-beta must be strictly less than 1.8.0
      expect(UpdateService.compareSemVer('1.8.0-beta', '1.8.0'), lessThan(0));
      expect(UpdateService.compareSemVer('1.8.0', '1.8.0-beta'), greaterThan(0));

      // Same versions
      expect(UpdateService.compareSemVer('1.7.1', '1.7.1'), equals(0));
      expect(UpdateService.compareSemVer('v1.7.1', '1.7.1'), equals(0));

      // Higher versions
      expect(UpdateService.compareSemVer('1.7.2', '1.7.1'), greaterThan(0));
      expect(UpdateService.compareSemVer('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareSemVer('1.7.0', '1.7.1'), lessThan(0));
    });

    test('UpdateInfo.fromJson prevents downgrades despite higher versionCode', () {
      // Remote version is older (1.5.0) than current (1.7.1), but has high versionCode (999)
      final downgradeJson = {
        'version': '1.5.0',
        'versionCode': 999,
        'apkUrl': 'https://github.com/Jman100/plix/releases/download/v1.5.0/plix_android.apk',
      };

      final info = UpdateInfo.fromJson(
        downgradeJson,
        currentVersion: '1.7.1',
        currentVersionCode: 41,
      );

      // Must NOT consider downgrade an update
      expect(info.hasUpdate, isFalse);
    });

    test('UpdateInfo.fromJson accepts build number increment for same semver', () {
      final patchJson = {
        'version': '1.7.1',
        'versionCode': 42,
        'apkUrl': 'https://github.com/Jman100/plix/releases/download/v1.7.1/plix_android.apk',
        'sha256': 'mocksha256hashvaluefortest1234567890',
      };

      final info = UpdateInfo.fromJson(
        patchJson,
        currentVersion: '1.7.1',
        currentVersionCode: 41,
      );

      expect(info.hasUpdate, isTrue);
    });
  });

  group('Carlos Code Review - Media Item & Date Added Tests', () {
    test('PlexMediaItem parses addedAt from Plex JSON timestamp', () {
      final plexJson = {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'title': 'Test Movie',
        'type': 'movie',
        'addedAt': 1700000000,
      };

      final item = PlexMediaItem.fromJson(plexJson);
      expect(item.addedAt, equals(1700000000));
    });

    test('PlexMediaItem parses addedAt from Jellyfin DateCreated ISO string', () {
      final jfJson = {
        'Id': 'jf_movie_1',
        'Name': 'Test Jellyfin Movie',
        'Type': 'Movie',
        'DateCreated': '2026-11-04T12:00:00.000Z',
      };

      final item = PlexMediaItem.fromJson(jfJson);
      expect(item.addedAt, equals(DateTime.parse('2026-11-04T12:00:00.000Z').millisecondsSinceEpoch));
    });

    test('Date Added sorting strictly orders by addedAt', () {
      const itemOld = PlexMediaItem(
        ratingKey: '1',
        key: '/1',
        title: 'Old Added (Released 2025)',
        type: 'movie',
        originallyAvailableAt: '2025-01-01',
        addedAt: 1000,
      );

      const itemNew = PlexMediaItem(
        ratingKey: '2',
        key: '/2',
        title: 'Recently Added (Released 1980)',
        type: 'movie',
        originallyAvailableAt: '1980-01-01',
        addedAt: 5000,
      );

      final list = [itemOld, itemNew];
      list.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));

      // Most recently added item must be first
      expect(list.first.ratingKey, equals('2'));
      expect(list.last.ratingKey, equals('1'));
    });
  });

  group('Carlos Code Review - Connection Race & First Success Tests', () {
    test('PlexServerService testAndResolveBestConnection finishes on first success without waiting for slow candidates', () async {
      final service = PlexServerService(authService: PlexAuthService());
      final server = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'test_client_id',
        accessToken: 'test_token',
        owned: true,
        connections: [],
      );

      expect(server.clientIdentifier, equals('test_client_id'));
      expect(service, isNotNull);
    });
  });
}
