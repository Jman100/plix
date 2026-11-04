import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';

void main() {
  group('Watchlist Resolution & GUID Matching Tests', () {
    test('PlexMediaItem guids parsing collects primary and secondary IDs', () {
      final json = {
        'ratingKey': '616bf60d8575f9def58a793e',
        'key': '/library/metadata/616bf60d8575f9def58a793e',
        'title': "Richard Hammond's Workshop",
        'type': 'show',
        'year': 2021,
        'guid': 'plex://show/616bf60d8575f9def58a793e',
        'Guid': [
          {'id': 'imdb://tt14906022'},
          {'id': 'tmdb://136638'},
          {'id': 'tvdb://411496'},
        ],
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.guid, equals('plex://show/616bf60d8575f9def58a793e'));
      expect(item.guids, contains('plex://show/616bf60d8575f9def58a793e'));
      expect(item.guids, contains('imdb://tt14906022'));
      expect(item.guids, contains('tmdb://136638'));
      expect(item.guids, contains('tvdb://411496'));
    });

    test('Watchlist matching logic matches exact GUIDs across Discover and local server items', () {
      final discoverItem = const PlexMediaItem(
        ratingKey: '616bf60d8575f9def58a793e',
        key: '/library/metadata/616bf60d8575f9def58a793e',
        title: "Richard Hammond's Workshop",
        type: 'show',
        year: 2021,
        guid: 'plex://show/616bf60d8575f9def58a793e',
        guids: [
          'plex://show/616bf60d8575f9def58a793e',
          'imdb://tt14906022',
        ],
      );

      final localServerItem = const PlexMediaItem(
        ratingKey: '47341',
        key: '/library/metadata/47341',
        title: "Richard Hammond's Workshop",
        type: 'show',
        year: 2021,
        guid: 'plex://show/616bf60d8575f9def58a793e',
        guids: [
          'imdb://tt14906022',
          'tmdb://136638',
          'tvdb://411496',
        ],
      );

      String cleanGuid(String g) => g.trim().toLowerCase().split('?').first;
      final targetGuids = <String>{
        if (discoverItem.guid != null) cleanGuid(discoverItem.guid!),
        for (final g in discoverItem.guids) cleanGuid(g),
      };
      final localGuids = <String>{
        if (localServerItem.guid != null) cleanGuid(localServerItem.guid!),
        for (final g in localServerItem.guids) cleanGuid(g),
      };

      final hasGuidMatch = targetGuids.any((g) => localGuids.contains(g));
      expect(hasGuidMatch, isTrue);
    });

    test('Watchlist matching logic handles word token overlap match with matching year', () {
      final discoverItem = const PlexMediaItem(
        ratingKey: '616bf60d8575f9def58a793e',
        key: '/library/metadata/616bf60d8575f9def58a793e',
        title: "Richard Hammond's Workshop",
        type: 'show',
        year: 2021,
      );

      final localServerItem = const PlexMediaItem(
        ratingKey: '47341',
        key: '/library/metadata/47341',
        title: "Richard Hammond's Car Workshop",
        type: 'show',
        year: 2021,
      );

      Set<String> toTokens(String s) => s
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3)
          .toSet();
      final wTokens = toTokens(discoverItem.title);
      final rTokens = toTokens(localServerItem.title);
      final isYearClose = discoverItem.year != null &&
          localServerItem.year != null &&
          (discoverItem.year! - localServerItem.year!).abs() <= 1;

      final common = wTokens.intersection(rTokens);
      final isMatch = (common.length == wTokens.length || common.length == rTokens.length) && isYearClose;
      expect(isMatch, isTrue);
    });

    test('PlexServer activeConnectionUri is preserved when refreshing server list', () {
      final activeServer = PlexServer(
        name: 'Jman100-Plex',
        clientIdentifier: 'ced5b55ac3585de561f21411db67d565638a4e00',
        accessToken: 'token123',
        owned: true,
        connections: [],
        activeConnectionUri: 'https://192-168-0-220.plex.direct:32400',
      );

      final uninitializedFetchedServer = PlexServer(
        name: 'Jman100-Plex',
        clientIdentifier: 'ced5b55ac3585de561f21411db67d565638a4e00',
        accessToken: 'token123',
        owned: true,
        connections: [],
        activeConnectionUri: null,
      );

      final allServers = [uninitializedFetchedServer];

      for (final s in allServers) {
        if (s.clientIdentifier == activeServer.clientIdentifier &&
            activeServer.activeConnectionUri != null &&
            activeServer.activeConnectionUri!.isNotEmpty) {
          s.activeConnectionUri = activeServer.activeConnectionUri;
        }
      }

      expect(uninitializedFetchedServer.activeConnectionUri, equals('https://192-168-0-220.plex.direct:32400'));
    });
  });
}
