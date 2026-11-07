import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/subtitle_search_result.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/jellyfin_media_service.dart';

void main() {
  group('Phase 4 Features Unit Tests', () {
    test('PlexMarker credits detection and creditsMarker getter', () {
      const intro = PlexMarker(
        id: 1,
        type: 'intro',
        startTimeOffset: 1000,
        endTimeOffset: 15000,
      );
      const credits = PlexMarker(
        id: 2,
        type: 'credits',
        startTimeOffset: 120000,
        endTimeOffset: 135000,
      );

      expect(intro.isIntro, isTrue);
      expect(intro.isCredits, isFalse);
      expect(credits.isIntro, isFalse);
      expect(credits.isCredits, isTrue);

      const item = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Test Episode',
        type: 'episode',
        duration: 140000,
        markers: [intro, credits],
      );

      expect(item.introMarker, equals(intro));
      expect(item.creditsMarker, equals(credits));
      expect(item.creditsMarker?.startTimeOffset, equals(120000));
    });

    test('SubtitleSearchResult Plex JSON parsing', () {
      final json = {
        'ratingKey': 'sub_123',
        'key': '/library/metadata/101/subtitles?key=abc',
        'title': 'English (OpenSubtitles)',
        'language': 'English',
        'languageCode': 'en',
        'format': 'srt',
        'provider': 'OpenSubtitles',
        'hearingImpaired': 1,
        'score': 95,
      };

      final result = SubtitleSearchResult.fromPlexJson(json);
      expect(result.id, 'sub_123');
      expect(result.key, '/library/metadata/101/subtitles?key=abc');
      expect(result.title, 'English (OpenSubtitles)');
      expect(result.language, 'English');
      expect(result.languageCode, 'en');
      expect(result.format, 'srt');
      expect(result.provider, 'OpenSubtitles');
      expect(result.isHearingImpaired, isTrue);
      expect(result.score, 95);
    });

    test('SubtitleSearchResult Jellyfin JSON parsing', () {
      final json = {
        'Id': 'jf_sub_456',
        'Name': 'Spanish Forced',
        'ThreeLetterISOLanguageName': 'spa',
        'Format': 'srt',
        'ProviderName': 'OpenSubtitles',
        'IsForHearingImpaired': false,
        'CommunityRating': 8.5,
      };

      final result = SubtitleSearchResult.fromJellyfinJson(json);
      expect(result.id, 'jf_sub_456');
      expect(result.title, 'Spanish Forced');
      expect(result.language, 'spa');
      expect(result.format, 'srt');
      expect(result.provider, 'OpenSubtitles');
      expect(result.isHearingImpaired, isFalse);
      expect(result.score, 85);
    });

    test('PlexMediaItem genres parsing from Genre list and tags', () {
      final plexJson = {
        'ratingKey': '201',
        'title': 'Action Movie',
        'type': 'movie',
        'Genre': [
          {'tag': 'Action'},
          {'tag': 'Sci-Fi'},
          {'tag': 'Adventure'},
        ],
      };

      final item = PlexMediaItem.fromJson(plexJson);
      expect(item.genres, containsAll(['Action', 'Sci-Fi', 'Adventure']));
    });

    test('JellyfinMediaService parses Genres correctly into PlexMediaItem', () {
      final server = PlexServer(
        name: 'Test Jellyfin',
        clientIdentifier: 'jf_test_1',
        accessToken: 'token123',
        owned: true,
        connections: const [],
        serverType: 'jellyfin',
        userId: 'user_abc',
      );
      final jfService = JellyfinMediaService(server: server);
      final item = jfService.parseItem({
        'Id': 'item_123',
        'Name': 'Test Show',
        'Type': 'Series',
        'Genres': ['Comedy', 'Animation', 'Adventure'],
      });
      expect(item.genres, equals(['Comedy', 'Animation', 'Adventure']));
    });
  });
}
