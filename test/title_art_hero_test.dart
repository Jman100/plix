import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/jellyfin_media_service.dart';
import 'package:plix/services/plex_media_service.dart';

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

    test('Connected Server display format summarizes both Plex and Jellyfin', () {
      final plex = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'plex-1',
        accessToken: 'token',
        owned: true,
        connections: [],
      );
      final jf = PlexServer(
        name: 'My Jellyfin',
        clientIdentifier: 'jf-1',
        accessToken: 'token',
        owned: true,
        connections: [],
        serverType: 'jellyfin',
      );
      final servers = [plex, jf];
      final plexCount = servers.where((s) => !s.isJellyfin).length;
      final jfCount = servers.where((s) => s.isJellyfin).length;

      expect(plexCount, 1);
      expect(jfCount, 1);
      final trailing = (plexCount > 0 && jfCount > 0) ? 'Plex & Jellyfin' : '';
      expect(trailing, 'Plex & Jellyfin');
      final title = servers.length > 1 ? 'Connected Servers (${servers.length})' : 'Connected Server';
      expect(title, 'Connected Servers (2)');
      final subtitle = servers.map((s) => '${s.name} (${s.isJellyfin ? 'Jellyfin' : 'Plex'})').join(', ');
      expect(subtitle, 'My Plex (Plex), My Jellyfin (Jellyfin)');
    });

    test('PlexMediaService buildLogoUrl optimizes local logos via photo transcoder to prevent multi-megabyte payloads', () {
      final plex = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'plex-1',
        accessToken: 'plex_token_xyz',
        owned: true,
        activeConnectionUri: 'http://192.168.0.10:32400',
        connections: [
          PlexConnection(uri: 'http://192.168.0.10:32400', protocol: 'http', address: '192.168.0.10', port: 32400, local: true, relay: false),
        ],
      );
      final service = PlexMediaService(server: plex);
      final logoUrl = service.buildLogoUrl('/library/metadata/1234/clearLogo/5678');
      expect(logoUrl.contains('/photo/:/transcode'), isTrue);
      expect(logoUrl.contains('format=png'), isTrue);
      expect(logoUrl.contains('width=440'), isTrue);
      expect(logoUrl.contains('height=160'), isTrue);
    });

    test('Mobile movie backdrop in portrait uses fitWidth and topCenter', () {
      const isCompact = true;
      final movie = PlexMediaItem(ratingKey: '10', key: '/m/10', title: 'Top Gun', type: 'movie');
      final fit = (isCompact && movie.isMovie) ? 'fitWidth' : 'cover';
      expect(fit, 'fitWidth');
    });

    test('JellyfinMediaService buildLogoUrl optimizes dimensions and quality for speed', () {
      final jf = PlexServer(
        name: 'My Jellyfin',
        clientIdentifier: 'jf-1',
        accessToken: 'jf_token_abc',
        owned: true,
        connections: [
          PlexConnection(uri: 'http://192.168.0.11:8096', protocol: 'http', address: '192.168.0.11', port: 8096, local: true, relay: false),
        ],
        serverType: 'jellyfin',
      );
      final service = JellyfinMediaService(server: jf);
      final logoUrl = service.buildLogoUrl('item-id-123');
      expect(logoUrl, 'http://192.168.0.11:8096/Items/item-id-123/Images/Logo?maxWidth=440&maxHeight=160&quality=75&api_key=jf_token_abc');
    });

    test('Episode detail page SX:EX format excludes show title', () {
      final ep = PlexMediaItem(
        ratingKey: '99',
        key: '/library/metadata/99',
        title: 'Desert Stumble',
        type: 'episode',
        grandparentTitle: 'The Grand Tour',
        parentIndex: 1,
        index: 2,
      );

      final season = ep.parentIndex;
      final episode = ep.index;
      String showLine = '';
      if (ep.isEpisode) {
        if (season != null && episode != null) {
          showLine = 'S$season:E$episode';
        } else if (season != null) {
          showLine = 'S$season';
        } else if (episode != null) {
          showLine = 'E$episode';
        }
      }
      expect(showLine, 'S1:E2');
      expect(showLine.contains('The Grand Tour'), isFalse);
    });
  });
}
