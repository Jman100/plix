import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/models/plex_media_item.dart';

void main() {
  group('Single server vs multi server content display logic', () {
    test('single server does not trigger multiServer flag', () {
      final servers = [
        PlexServer(
          name: 'HomeServer',
          clientIdentifier: 'srv_1',
          connections: [],
          accessToken: 'tok_1',
          owned: true,
          serverType: 'plex',
        ),
      ];
      final isMultiServer = servers.length > 1;
      expect(isMultiServer, isFalse);

      final item = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Movie Title',
        type: 'movie',
        server: servers.first,
      );

      final topServerName = isMultiServer ? item.server?.name : null;
      final bottomServerName = isMultiServer ? item.server?.name : null;

      expect(topServerName, isNull);
      expect(bottomServerName, isNull);
    });

    test('multi-server displays server labels', () {
      final servers = [
        PlexServer(
          name: 'PlexServer',
          clientIdentifier: 'srv_1',
          connections: [],
          accessToken: 'tok_1',
          owned: true,
          serverType: 'plex',
        ),
        PlexServer(
          name: 'JellyfinServer',
          clientIdentifier: 'srv_2',
          connections: [],
          accessToken: 'tok_2',
          owned: true,
          serverType: 'jellyfin',
        ),
      ];
      final isMultiServer = servers.length > 1;
      expect(isMultiServer, isTrue);

      final item = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Movie Title',
        type: 'movie',
        server: servers.first,
      );

      final topServerName = isMultiServer ? (item.server?.name ?? 'Plex') : null;
      final bottomServerName = isMultiServer ? (item.server?.name ?? 'Plex') : null;

      expect(topServerName, equals('PlexServer'));
      expect(bottomServerName, equals('PlexServer'));
    });
  });
}
