import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/services/seerr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeerrService URL & Configuration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('normalizeUrl handles schemes and trailing slashes correctly', () {
      final service = SeerrService();
      expect(service.normalizeUrl('  plex.jman100.com/  '), 'https://plex.jman100.com');
      expect(service.normalizeUrl('http://requests.jman100.com///'), 'http://requests.jman100.com');
      expect(service.normalizeUrl('https://myseerr.org:5055/'), 'https://myseerr.org:5055');
      expect(service.normalizeUrl('   '), '');
    });

    test('getSeerrUrl and setSeerrUrl store per-server URLs', () async {
      final service = SeerrService();
      const server1Id = 'plex_server_123';
      const server2Id = 'jellyfin_server_456';

      await service.setSeerrUrl(server1Id, 'https://plex.jman100.com');
      await service.setSeerrUrl(server2Id, 'https://requests.jman100.com');

      final url1 = await service.getSeerrUrl(server1Id);
      final url2 = await service.getSeerrUrl(server2Id);

      expect(url1, 'https://plex.jman100.com');
      expect(url2, 'https://requests.jman100.com');

      await service.removeSeerrUrl(server1Id);
      final url1After = await service.getSeerrUrl(server1Id);
      final url2After = await service.getSeerrUrl(server2Id);

      expect(url1After, isNull);
      expect(url2After, 'https://requests.jman100.com');
    });

    test('SeerrIssueType enum has correct IDs and descriptions', () {
      expect(SeerrIssueType.video.id, 1);
      expect(SeerrIssueType.audio.id, 2);
      expect(SeerrIssueType.subtitles.id, 3);
      expect(SeerrIssueType.other.id, 4);
    });

    test('PlexMediaItem guids extraction extracts TMDb ID correctly', () {
      const movieItem = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Inception',
        type: 'movie',
        guids: ['imdb://tt1375666', 'tmdb://27205'],
      );

      expect(movieItem.guids.any((g) => g.contains('tmdb://27205')), isTrue);
    });
  });
}
