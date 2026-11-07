import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_library.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/jellyfin_media_service.dart';

void main() {
  group('Subtitle Byte Decoding and Accents (Issue 2)', () {
    test('decodeSubtitleBytes properly decodes accented UTF-8 characters', () {
      const original = 'El más rápido lo hizo en 1:17. David Hasselhoff, ¿estás listo?';
      final utf8Bytes = utf8.encode(original);

      final decoded = JellyfinMediaService.decodeSubtitleBytes(utf8Bytes);
      expect(decoded, equals(original));
      expect(decoded.contains('más'), isTrue);
      expect(decoded.contains('rápido'), isTrue);
      expect(decoded.contains('¿'), isTrue);
    });

    test('decodeSubtitleBytes strips UTF-8 BOM', () {
      const original = '1\n00:00:01,000 --> 00:00:04,000\n¡Hola Señor!';
      final utf8Bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(original)];

      final decoded = JellyfinMediaService.decodeSubtitleBytes(utf8Bytes);
      expect(decoded.startsWith('\uFEFF'), isFalse);
      expect(decoded, equals(original));
      expect(decoded.contains('Señor'), isTrue);
    });

    test('decodeSubtitleBytes decodes UTF-16LE with BOM', () {
      const original = 'Hello World';
      final units = <int>[0xFF, 0xFE];
      for (final code in original.codeUnits) {
        units.add(code & 0xFF);
        units.add((code >> 8) & 0xFF);
      }

      final decoded = JellyfinMediaService.decodeSubtitleBytes(units);
      expect(decoded, equals(original));
    });
  });

  group('Plex Stream Parsing (All Audio and Subtitle Streams)', () {
    test('PlexMediaItem parses all subtitle streams, not just the first one', () {
      final plexJson = {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'title': 'Test Movie',
        'type': 'movie',
        'Media': [
          {
            'Part': [
              {
                'id': '201',
                'key': '/library/parts/201/file.mkv',
                'Stream': [
                  {
                    'id': '301',
                    'streamType': 1,
                    'codec': 'hevc',
                    'width': 3840,
                    'height': 2160,
                  },
                  {
                    'id': '302',
                    'streamType': 2,
                    'codec': 'eac3',
                    'channels': 6,
                    'displayTitle': 'English (EAC3 5.1)',
                  },
                  {
                    'id': '303',
                    'streamType': 2,
                    'codec': 'ac3',
                    'channels': 2,
                    'displayTitle': 'Spanish (AC3 Stereo)',
                  },
                  {
                    'id': '304',
                    'streamType': 3,
                    'codec': 'srt',
                    'language': 'English',
                    'languageCode': 'en',
                    'displayTitle': 'English',
                  },
                  {
                    'id': '305',
                    'streamType': 3,
                    'codec': 'srt',
                    'language': 'Spanish',
                    'languageCode': 'es',
                    'displayTitle': 'Spanish (Downloaded)',
                  },
                ],
              }
            ],
          }
        ],
      };

      final item = PlexMediaItem.fromJson(plexJson);
      expect(item.audioStreams.length, equals(2));
      expect(item.audioStreams[0].displayTitle, contains('English'));
      expect(item.audioStreams[1].displayTitle, contains('Spanish'));

      expect(item.subtitleStreams.length, equals(2));
      expect(item.subtitleStreams[0].language, equals('English'));
      expect(item.subtitleStreams[1].language, equals('Spanish'));
    });

    test('PlexSubtitleStream copyWith preserves or modifies fields', () {
      const stream = PlexSubtitleStream(
        id: '1',
        key: '/sub1',
        codec: 'srt',
        language: 'English',
        languageCode: 'en',
        displayTitle: 'English Track',
        streamIndex: 2,
        isSelected: false,
      );

      final updated = stream.copyWith(streamIndex: -1, isSelected: true);
      expect(updated.id, equals('1'));
      expect(updated.key, equals('/sub1'));
      expect(updated.streamIndex, equals(-1));
      expect(updated.isSelected, isTrue);
    });
  });

  group('Continue Watching Library Sort Order (Issue 5)', () {
    final serverJF = PlexServer(
      name: 'Jellyfin Server',
      clientIdentifier: 'srv_jf',
      accessToken: 'token_jf',
      owned: true,
      connections: const [],
      serverType: 'jellyfin',
    );

    final serverPlex = PlexServer(
      name: 'Plex Server',
      clientIdentifier: 'srv_plex',
      accessToken: 'token_plex',
      owned: true,
      connections: const [],
    );

    // Scenario: User chose Jellyfin TV first, then Plex TV second
    final jfTvLib = PlexLibrary(
      key: 'jf_tv_key',
      title: 'Jellyfin TV Shows',
      type: 'show',
      serverId: 'srv_jf',
      server: serverJF,
      isJellyfin: true,
    );

    final plexTvLib = PlexLibrary(
      key: 'plex_tv_key',
      title: 'Plex TV Shows',
      type: 'show',
      serverId: 'srv_plex',
      server: serverPlex,
    );

    final userLibraries = [jfTvLib, plexTvLib];

    int getLibrarySortIndex(PlexMediaItem item, List<PlexLibrary> libraries) {
      if (libraries.isEmpty) return 999999;
      final itemServerId = item.serverId ?? item.server?.clientIdentifier;

      for (int i = 0; i < libraries.length; i++) {
        final lib = libraries[i];
        if (itemServerId != null && itemServerId.isNotEmpty && lib.serverId != itemServerId) {
          continue;
        }

        if (item.librarySectionId != null && item.librarySectionId!.isNotEmpty) {
          final normItemKey = item.librarySectionId!.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          final normLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          if (item.librarySectionId == lib.key || normItemKey == normLibKey) {
            return i;
          }
        }

        if (item.ancestorIds.isNotEmpty) {
          final normalizedLibKey = lib.key.replaceAll('-', '').replaceAll('_', '').toLowerCase();
          for (final ancestor in item.ancestorIds) {
            final normalizedAncestor = ancestor.replaceAll('-', '').replaceAll('_', '').toLowerCase();
            if (normalizedAncestor == normalizedLibKey) {
              return i;
            }
          }
        }

        if (item.librarySectionTitle != null && item.librarySectionTitle!.isNotEmpty &&
            item.librarySectionTitle!.toLowerCase() == lib.title.toLowerCase()) {
          return i;
        }

        final serverLibs = libraries.where((l) => l.serverId == lib.serverId).toList();
        if (serverLibs.length == 1) {
          final singleLib = serverLibs.first;
          if (singleLib.isMovie && item.isMovie) return i;
          if (singleLib.isShow && (item.isEpisode || item.isShow)) return i;
          if (!singleLib.isMovie && !singleLib.isShow) return i;
        }
      }

      return 999999;
    }

    void sortContinueWatching(List<PlexMediaItem> list, List<PlexLibrary> libraries) {
      list.sort((a, b) {
        final idxA = getLibrarySortIndex(a, libraries);
        final idxB = getLibrarySortIndex(b, libraries);
        if (idxA != idxB) return idxA.compareTo(idxB);
        return (b.lastViewedAt ?? 0).compareTo(a.lastViewedAt ?? 0);
      });
    }

    test('Continue watching items are sorted by user library order first', () {
      const plexItem = PlexMediaItem(
        ratingKey: 'p1',
        key: '/p1',
        title: 'Plex Grand Tour',
        type: 'episode',
        serverId: 'srv_plex',
        librarySectionId: 'plex_tv_key',
        lastViewedAt: 10000,
      );

      const jfItem = PlexMediaItem(
        ratingKey: 'jf1',
        key: '/jf1',
        title: 'Jellyfin Grand Tour',
        type: 'episode',
        serverId: 'srv_jf',
        librarySectionId: 'jf_tv_key',
        lastViewedAt: 5000,
      );

      final list = [plexItem, jfItem];
      sortContinueWatching(list, userLibraries);

      expect(list.first.ratingKey, equals('jf1'));
      expect(list.last.ratingKey, equals('p1'));
    });

    test('Continue watching items in same library are sorted by lastViewedAt descending', () {
      const jfItem1 = PlexMediaItem(
        ratingKey: 'jf1',
        key: '/jf1',
        title: 'Jellyfin Ep 1',
        type: 'episode',
        serverId: 'srv_jf',
        librarySectionId: 'jf_tv_key',
        lastViewedAt: 2000,
      );

      const jfItem2 = PlexMediaItem(
        ratingKey: 'jf2',
        key: '/jf2',
        title: 'Jellyfin Ep 2',
        type: 'episode',
        serverId: 'srv_jf',
        librarySectionId: 'jf_tv_key',
        lastViewedAt: 8000,
      );

      final list = [jfItem1, jfItem2];
      sortContinueWatching(list, userLibraries);

      expect(list.first.ratingKey, equals('jf2'));
      expect(list.last.ratingKey, equals('jf1'));
    });
  });
}
