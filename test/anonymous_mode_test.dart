import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/plex_timeline_service.dart';

void main() {
  group('Anonymous Mode in PlexTimelineService', () {
    const testItem = PlexMediaItem(
      ratingKey: '12345',
      key: '/library/metadata/12345',
      title: 'Test Movie',
      type: 'movie',
      duration: 1000000,
      viewOffset: 0,
    );

    final plexServer = PlexServer(
      name: 'Test Plex Server',
      clientIdentifier: 'plex_server_1',
      accessToken: 'test_token',
      owned: true,
      connections: [
        PlexConnection(
          protocol: 'http',
          address: '127.0.0.1',
          port: 32400,
          uri: 'http://127.0.0.1:32400',
          local: true,
          relay: false,
        ),
      ],
    );

    final jellyfinServer = PlexServer(
      name: 'Test Jellyfin Server',
      clientIdentifier: 'jellyfin_server_1',
      accessToken: 'jf_token',
      owned: true,
      serverType: 'jellyfin',
      connections: [
        PlexConnection(
          protocol: 'http',
          address: '127.0.0.1',
          port: 8096,
          uri: 'http://127.0.0.1:8096',
          local: true,
          relay: false,
        ),
      ],
    );

    test('Plex: Normal mode sends timeline requests and scrobbles', () async {
      int requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('<MediaContainer/>', 200);
      });

      final service = PlexTimelineService(
        server: plexServer,
        clientId: 'client_1',
        isAnonymous: false,
        client: client,
      );

      service.startPlayback(testItem, 0);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(requestCount, greaterThan(0));

      service.pause(50000);
      service.resume(60000);
      service.stop(70000);
    });

    test('Plex: Anonymous mode does NOT send any timeline or scrobble requests', () async {
      int requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('<MediaContainer/>', 200);
      });

      final service = PlexTimelineService(
        server: plexServer,
        clientId: 'client_1',
        isAnonymous: true,
        client: client,
      );

      expect(service.isAnonymous, isTrue);

      service.startPlayback(testItem, 0);
      service.updatePosition(950000); // 95% threshold for scrobble
      service.pause(950000);
      service.resume(950000);
      service.stop(950000);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(requestCount, equals(0));
    });

    test('Jellyfin: Anonymous mode does NOT send /Sessions/Playing or Progress requests', () async {
      int requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('{}', 200);
      });

      final service = PlexTimelineService(
        server: jellyfinServer,
        clientId: 'client_1',
        isAnonymous: true,
        client: client,
      );

      expect(service.isAnonymous, isTrue);

      service.startPlayback(testItem, 0);
      service.updatePosition(950000);
      service.pause(950000);
      service.resume(950000);
      service.stop(950000);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(requestCount, equals(0));
    });
  });
}
