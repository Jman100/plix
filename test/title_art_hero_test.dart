import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/jellyfin_media_service.dart';

void main() {
  group('Title Art & clearLogo Parsing Tests', () {
    test('PlexMediaItem parses clearLogo from direct clearLogo field', () {
      final json = {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'title': 'Inception',
        'type': 'movie',
        'clearLogo': '/library/metadata/101/clearLogo/12345',
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.clearLogo, '/library/metadata/101/clearLogo/12345');
    });

    test('PlexMediaItem parses clearLogo from Image array with type clearLogo', () {
      final json = {
        'ratingKey': '202',
        'key': '/library/metadata/202',
        'title': 'The Matrix',
        'type': 'movie',
        'Image': [
          {'type': 'coverPoster', 'url': '/library/metadata/202/thumb/111'},
          {'type': 'clearLogo', 'url': '/library/metadata/202/clearLogo/222'},
        ],
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.clearLogo, '/library/metadata/202/clearLogo/222');
    });

    test('PlexMediaItem parses clearLogo from grandparentClearLogo for episodes', () {
      final json = {
        'ratingKey': '303',
        'key': '/library/metadata/303',
        'title': 'Episode 1',
        'type': 'episode',
        'grandparentTitle': 'Severance',
        'grandparentClearLogo': '/library/metadata/300/clearLogo/333',
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.clearLogo, '/library/metadata/300/clearLogo/333');
    });

    test('JellyfinMediaService parses clearLogo from ImageTags Logo', () {
      final server = PlexServer(
        name: 'JF Test',
        clientIdentifier: 'jf-test-1',
        accessToken: 'token',
        owned: true,
        connections: [
          PlexConnection(uri: 'http://127.0.0.1:8096', protocol: 'http', address: '127.0.0.1', port: 8096, local: true, relay: false),
        ],
        serverType: 'jellyfin',
      );
      final service = JellyfinMediaService(server: server);
      final json = {
        'Id': 'item-abc',
        'Name': 'Breaking Bad',
        'Type': 'Series',
        'ImageTags': {
          'Primary': 'tag1',
          'Logo': 'tag-logo',
        },
      };
      final item = service.parseItem(json);
      expect(item.clearLogo, '/Items/item-abc/Images/Logo');
    });

    test('JellyfinMediaService parses clearLogo from ParentLogoItemId for episodes', () {
      final server = PlexServer(
        name: 'JF Test',
        clientIdentifier: 'jf-test-2',
        accessToken: 'token',
        owned: true,
        connections: [
          PlexConnection(uri: 'http://127.0.0.1:8096', protocol: 'http', address: '127.0.0.1', port: 8096, local: true, relay: false),
        ],
        serverType: 'jellyfin',
      );
      final service = JellyfinMediaService(server: server);
      final json = {
        'Id': 'ep-123',
        'Name': 'Ozymandias',
        'Type': 'Episode',
        'SeriesId': 'series-789',
        'ParentLogoItemId': 'series-789',
        'ParentLogoImageTag': 'logo-tag',
        'ImageTags': {
          'Primary': 'ep-tag',
        },
      };
      final item = service.parseItem(json);
      expect(item.clearLogo, '/Items/series-789/Images/Logo');
    });

    test('PlexMediaItem copyWith preserves or updates clearLogo', () {
      final item = PlexMediaItem(
        ratingKey: '1',
        key: '/library/metadata/1',
        title: 'Original',
        type: 'movie',
        clearLogo: '/logo/1',
      );
      expect(item.clearLogo, '/logo/1');

      final copied = item.copyWith(title: 'Updated');
      expect(copied.clearLogo, '/logo/1');

      final updatedLogo = item.copyWith(clearLogo: '/logo/2');
      expect(updatedLogo.clearLogo, '/logo/2');
    });
    test('PlexMediaItem prioritizes English clearLogo over Russian or other language variants', () {
      final json = {
        'ratingKey': '404',
        'key': '/library/metadata/404',
        'title': 'Phony',
        'type': 'show',
        'Image': [
          {'type': 'clearLogo', 'url': '/library/metadata/404/clearLogo/ru_logo', 'language': 'ru'},
          {'type': 'clearLogo', 'url': '/library/metadata/404/clearLogo/en_logo', 'language': 'en'},
        ],
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.clearLogo, '/library/metadata/404/clearLogo/en_logo');
    });

    test('PlexMediaItem parses grandparentArt as art when art is missing on episode', () {
      final json = {
        'ratingKey': '505',
        'key': '/library/metadata/505',
        'title': 'Episode 5',
        'type': 'episode',
        'grandparentArt': '/library/metadata/500/art/backdrop123',
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.art, '/library/metadata/500/art/backdrop123');
    });
  });
}
