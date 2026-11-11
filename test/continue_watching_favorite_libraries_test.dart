import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_library.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';

void main() {
  group('PlexMediaItem library properties parsing', () {
    test('parses librarySectionID, librarySectionKey, librarySectionTitle from Plex JSON', () {
      final json = {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'title': 'Test Movie',
        'type': 'movie',
        'librarySectionID': 2,
        'librarySectionKey': '/library/sections/2',
        'librarySectionTitle': 'Movies',
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.librarySectionId, '2');
      expect(item.librarySectionTitle, 'Movies');
    });

    test('parses AncestorIds and ParentId from Jellyfin JSON', () {
      final json = {
        'Id': 'item_101',
        'Name': 'Test Episode',
        'Type': 'Episode',
        'ParentId': 'season_1',
        'AncestorIds': ['lib_view_guid', 'series_guid', 'season_1'],
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.ancestorIds, contains('lib_view_guid'));
      expect(item.ancestorIds, contains('series_guid'));
      expect(item.ancestorIds, contains('season_1'));
    });

    test('copyWith preserves librarySectionId, librarySectionTitle, and ancestorIds', () {
      const item = PlexMediaItem(
        ratingKey: '1',
        key: '/library/metadata/1',
        title: 'Title',
        type: 'movie',
        librarySectionId: '3',
        librarySectionTitle: 'Anime',
        ancestorIds: ['ancestor_1', 'ancestor_2'],
      );

      final copy = item.copyWith(
        title: 'New Title',
        serverId: 'srv_1',
      );

      expect(copy.title, 'New Title');
      expect(copy.serverId, 'srv_1');
      expect(copy.librarySectionId, '3');
      expect(copy.librarySectionTitle, 'Anime');
      expect(copy.ancestorIds, ['ancestor_1', 'ancestor_2']);
    });
  });

  group('Continue Watching favorited library filtering logic', () {
    final server1 = PlexServer(
      name: 'Server 1',
      clientIdentifier: 'srv_1',
      accessToken: 'tok_1',
      owned: true,
      connections: [],
    );

    // Favorited libraries:
    // Server 1 (Plex):
    // Section 1: Movies
    // Section 2: TV Shows
    // Unfavorited on Server 1: Section 3: Anime
    // Server JF (Jellyfin):
    // 1 library favorited: Jellyfin 4K (type: movie)
    final favoritedLibraries = [
      PlexLibrary(
        key: '1',
        title: 'Movies',
        type: 'movie',
        serverId: 'srv_1',
        server: server1,
      ),
      PlexLibrary(
        key: '2',
        title: 'TV Shows',
        type: 'show',
        serverId: 'srv_1',
        server: server1,
      ),
      PlexLibrary(
        key: 'jf_lib_guid_123',
        title: 'Jellyfin 4K',
        type: 'movie',
        serverId: 'srv_jf',
        isJellyfin: true,
      ),
    ];

    bool isItemInFavoritedLibraries(PlexMediaItem item, List<PlexLibrary> libraries) {
      if (libraries.isEmpty) return false;

      final itemServerId = item.serverId ?? item.server?.clientIdentifier;

      final serverLibs = (itemServerId != null && itemServerId.isNotEmpty)
          ? libraries.where((l) => l.serverId == itemServerId).toList()
          : libraries;

      if (serverLibs.isEmpty) return false;

      for (final lib in serverLibs) {
        if (item.librarySectionId != null && item.librarySectionId!.isNotEmpty) {
          final normItemKey = item.librarySectionId!.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          final normLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          if (item.librarySectionId == lib.key || normItemKey == normLibKey) {
            return true;
          }
        }

        if (item.ancestorIds.isNotEmpty) {
          final normalizedLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          for (final ancestor in item.ancestorIds) {
            final normalizedAncestor = ancestor.replaceAll('-', '').replaceAll('_', '').toLowerCase();
            if (normalizedAncestor == normalizedLibKey) {
              return true;
            }
          }
        }

        if (item.librarySectionTitle != null && item.librarySectionTitle!.isNotEmpty &&
            item.librarySectionTitle!.toLowerCase() == lib.title.toLowerCase()) {
          return true;
        }

        if (serverLibs.length == 1) {
          final singleLib = serverLibs.first;
          if (singleLib.isMovie && item.isMovie) return true;
          if (singleLib.isShow && (item.isEpisode || item.isShow)) return true;
          if (!singleLib.isMovie && !singleLib.isShow) return true;
        }
      }

      return false;
    }

    test('retains Continue Watching items belonging to favorited Plex libraries', () {
      const movieItem = PlexMediaItem(
        ratingKey: '10',
        key: '/library/metadata/10',
        title: 'Favorited Movie',
        type: 'movie',
        serverId: 'srv_1',
        librarySectionId: '1',
      );

      const episodeItem = PlexMediaItem(
        ratingKey: '20',
        key: '/library/metadata/20',
        title: 'Favorited Episode',
        type: 'episode',
        serverId: 'srv_1',
        librarySectionId: '2',
      );

      expect(isItemInFavoritedLibraries(movieItem, favoritedLibraries), isTrue);
      expect(isItemInFavoritedLibraries(episodeItem, favoritedLibraries), isTrue);
    });

    test('excludes Continue Watching items belonging to unfavorited Plex libraries on same server', () {
      const unfavoritedAnimeItem = PlexMediaItem(
        ratingKey: '30',
        key: '/library/metadata/30',
        title: 'Unfavorited Anime',
        type: 'episode',
        serverId: 'srv_1',
        librarySectionId: '3',
      );

      expect(isItemInFavoritedLibraries(unfavoritedAnimeItem, favoritedLibraries), isFalse);
    });

    test('excludes Continue Watching items belonging to a server with no favorited libraries', () {
      const otherServerItem = PlexMediaItem(
        ratingKey: '40',
        key: '/library/metadata/40',
        title: 'Server 2 Movie',
        type: 'movie',
        serverId: 'srv_2',
        librarySectionId: '1',
      );

      expect(isItemInFavoritedLibraries(otherServerItem, favoritedLibraries), isFalse);
    });

    test('retains Jellyfin Continue Watching items with matching View GUID in librarySectionId', () {
      const jellyfinItem = PlexMediaItem(
        ratingKey: '50',
        key: '/Items/50',
        title: 'Jellyfin 4K Movie',
        type: 'movie',
        serverId: 'srv_jf',
        librarySectionId: 'jf_lib_guid_123',
      );

      expect(isItemInFavoritedLibraries(jellyfinItem, favoritedLibraries), isTrue);
    });

    test('retains Jellyfin Continue Watching item on server with single favorited library matching type', () {
      const jellyfinItemWithoutSection = PlexMediaItem(
        ratingKey: '51',
        key: '/Items/51',
        title: 'Jellyfin Resumable Movie',
        type: 'movie',
        serverId: 'srv_jf',
      );

      expect(isItemInFavoritedLibraries(jellyfinItemWithoutSection, favoritedLibraries), isTrue);
    });

    test('excludes Jellyfin Continue Watching item if single favorited library has incompatible type', () {
      const jellyfinEpisode = PlexMediaItem(
        ratingKey: '52',
        key: '/Items/52',
        title: 'Jellyfin Resumable Episode',
        type: 'episode',
        serverId: 'srv_jf',
      );

      expect(isItemInFavoritedLibraries(jellyfinEpisode, favoritedLibraries), isFalse);
    });
  });

  group('Continue Watching Sorting Tests', () {
    test('sorts by most recently watched (lastViewedAt descending) regardless of library or server', () {
      const item1 = PlexMediaItem(
        ratingKey: '1',
        key: '/library/metadata/1',
        title: 'Older Watched on Server A (Library 0)',
        type: 'movie',
        serverId: 'srv_a',
        librarySectionId: 'lib_0',
        lastViewedAt: 1000,
      );

      const item2 = PlexMediaItem(
        ratingKey: '2',
        key: '/library/metadata/2',
        title: 'Most Recently Watched on Server B (Library 3)',
        type: 'movie',
        serverId: 'srv_b',
        librarySectionId: 'lib_3',
        lastViewedAt: 5000,
      );

      const item3 = PlexMediaItem(
        ratingKey: '3',
        key: '/library/metadata/3',
        title: 'Middle Watched on Server A (Library 1)',
        type: 'episode',
        serverId: 'srv_a',
        librarySectionId: 'lib_1',
        lastViewedAt: 3000,
      );

      final list = [item1, item2, item3];

      list.sort((a, b) {
        final timeA = a.lastViewedAt ?? 0;
        final timeB = b.lastViewedAt ?? 0;
        if (timeA != timeB) {
          return timeB.compareTo(timeA);
        }
        return 0;
      });

      expect(list.map((it) => it.ratingKey).toList(), ['2', '3', '1']);
    });
  });
}
