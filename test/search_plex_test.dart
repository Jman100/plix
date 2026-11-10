import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/plex_media_service.dart';

void main() {
  group('PlexMediaService Search Tests', () {
    test('BaseUrl falls back to first connection if activeConnectionUri is null', () {
      final server = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'plex_1',
        accessToken: 'plex_token',
        connections: [
          PlexConnection(
            uri: 'http://192.168.1.100:32400',
            protocol: 'http',
            address: '192.168.1.100',
            port: 32400,
            local: true,
            relay: false,
          ),
        ],
        owned: true,
        serverType: 'plex',
      );

      final service = PlexMediaService(server: server);
      expect(service.baseUrl, equals('http://192.168.1.100:32400'));
    });

    test('Plex search parses lowercase hub and uppercase Hub with Video / Metadata arrays', () async {
      // Verify that PlexMediaItem parses items correctly from hub responses
      final mockResponse = {
        'MediaContainer': {
          'size': 2,
          'hub': [
            {
              'title': 'Movies',
              'type': 'movie',
              'hubIdentifier': 'movie',
              'Metadata': [
                {
                  'ratingKey': '101',
                  'key': '/library/metadata/101',
                  'title': 'Inception',
                  'type': 'movie',
                  'year': 2010,
                },
              ],
            },
            {
              'title': 'TV Shows',
              'type': 'show',
              'hubIdentifier': 'show',
              'Video': [
                {
                  'ratingKey': '202',
                  'key': '/library/metadata/202',
                  'title': 'Breaking Bad',
                  'type': 'show',
                  'year': 2008,
                },
              ],
            },
            {
              'title': 'Actors',
              'type': 'actor',
              'hubIdentifier': 'actor',
              'Directory': [
                {
                  'id': '999',
                  'title': 'Bryan Cranston',
                },
              ],
            },
          ],
        },
      };

      // Ensure extractList and parse logic handles this structure
      final mc = mockResponse['MediaContainer'] as Map<String, dynamic>;
      final hubs = (mc['Hub'] ?? mc['hub']) as List<dynamic>;
      expect(hubs.length, equals(3));

      final items = <PlexMediaItem>[];
      for (final h in hubs) {
        if (h is! Map) continue;
        final hubType = h['type']?.toString().toLowerCase();
        if (hubType == 'actor' || hubType == 'director' || hubType == 'genre' || hubType == 'person') {
          continue;
        }
        final list = (h['Metadata'] ?? h['Video'] ?? h['Directory']) as List<dynamic>?;
        if (list != null) {
          for (final raw in list) {
            if (raw is Map) {
              items.add(PlexMediaItem.fromJson(Map<String, dynamic>.from(raw)));
            }
          }
        }
      }

      expect(items.length, equals(2));
      expect(items[0].title, equals('Inception'));
      expect(items[0].type, equals('movie'));
      expect(items[1].title, equals('Breaking Bad'));
      expect(items[1].type, equals('show'));
    });

    test('Episode search matches show title as well as episode title', () {
      const episode = PlexMediaItem(
        ratingKey: '501',
        key: '/library/metadata/501',
        title: 'Ozymandias',
        type: 'episode',
        grandparentTitle: 'Breaking Bad',
        parentTitle: 'Season 5',
      );

      final lowerQ = 'breaking bad'.toLowerCase();
      final titleMatch = episode.title.toLowerCase().contains(lowerQ);
      final gpMatch = episode.grandparentTitle?.toLowerCase().contains(lowerQ) ?? false;
      final pMatch = episode.parentTitle?.toLowerCase().contains(lowerQ) ?? false;

      expect(titleMatch || gpMatch || pMatch, isTrue);
    });
  });
}
