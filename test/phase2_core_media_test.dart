import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/native_player_service.dart';
import 'package:plix/services/plex_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2: Core Media & Engine Verification', () {
    test('PlexMediaService isolates cache by server clientIdentifier', () {
      final serverA = PlexServer(
        name: 'Server A',
        clientIdentifier: 'server_id_AAA',
        accessToken: 'token_a',
        owned: true,
        connections: [],
      );
      final serverB = PlexServer(
        name: 'Server B',
        clientIdentifier: 'server_id_BBB',
        accessToken: 'token_b',
        owned: true,
        connections: [],
      );

      final serviceA = PlexMediaService(server: serverA);
      final serviceB = PlexMediaService(server: serverB);

      // Invalidate everything first
      serviceA.invalidateCache();
      serviceB.invalidateCache();

      const itemA = PlexMediaItem(
        key: '/library/metadata/42',
        ratingKey: '42',
        title: 'Movie on Server A',
        type: 'movie',
      );
      const itemB = PlexMediaItem(
        key: '/library/metadata/42',
        ratingKey: '42',
        title: 'Movie on Server B',
        type: 'movie',
      );

      serviceA.cacheMetadata(itemA);
      serviceB.cacheMetadata(itemB);

      // Neither server's item should overwrite the other
      expect(serviceA.getCachedMetadata('42')?.title, 'Movie on Server A');
      expect(serviceB.getCachedMetadata('42')?.title, 'Movie on Server B');

      // Invalidating '42' on server A should not affect server B
      serviceA.invalidateCache('42');
      expect(serviceA.getCachedMetadata('42'), isNull);
      expect(serviceB.getCachedMetadata('42')?.title, 'Movie on Server B');
    });

    test('NativePlayerService behaves as a singleton', () {
      final p1 = NativePlayerService();
      final p2 = NativePlayerService();
      final p3 = NativePlayerService.instance;

      expect(identical(p1, p2), isTrue);
      expect(identical(p1, p3), isTrue);
    });

    test('PlexSubtitleStream identifies bitmap vs text subtitles correctly', () {
      const srt = PlexSubtitleStream(
        id: '1',
        key: '/sub/1',
        streamIndex: 2,
        codec: 'srt',
        language: 'English',
        languageCode: 'eng',
        displayTitle: 'English (SRT)',
      );
      const pgs = PlexSubtitleStream(
        id: '2',
        key: '/sub/2',
        streamIndex: 3,
        codec: 'pgs',
        language: 'English',
        languageCode: 'eng',
        displayTitle: 'English (PGS)',
      );
      const vobsub = PlexSubtitleStream(
        id: '3',
        key: '/sub/3',
        streamIndex: 4,
        codec: 'vobsub',
        language: 'Spanish',
        languageCode: 'spa',
        displayTitle: 'Spanish (VOBSUB)',
      );

      expect(srt.isBitmapSubtitle, isFalse);
      expect(pgs.isBitmapSubtitle, isTrue);
      expect(vobsub.isBitmapSubtitle, isTrue);
    });
  });
}
