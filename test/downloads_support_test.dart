import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/download_service.dart';
import 'package:plix/services/plix_device_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Downloads Support & Permissions Tests', () {
    test('Plex server download permissions check owned and allowSync', () async {
      final ownedServer = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'plex_1',
        accessToken: 'tok_1',
        owned: true,
        connections: [],
      );
      expect(ownedServer.canDownload, isTrue);

      final sharedAllowedServer = PlexServer(
        name: 'Shared Plex Allowed',
        clientIdentifier: 'plex_2',
        accessToken: 'tok_2',
        owned: false,
        allowSync: true,
        connections: [],
      );
      expect(sharedAllowedServer.canDownload, isTrue);

      final sharedRestrictedServer = PlexServer(
        name: 'Shared Plex Restricted',
        clientIdentifier: 'plex_3',
        accessToken: 'tok_3',
        owned: false,
        allowSync: false,
        connections: [],
      );
      expect(sharedRestrictedServer.canDownload, isFalse);
    });

    test('canUserDownload returns false on TV interfaces', () async {
      final ds = DownloadService.instance;
      final server = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'plex_1',
        accessToken: 'tok_1',
        owned: true,
        connections: [],
      );

      // On TV, downloads are strictly prohibited
      if (PlixDeviceHelper.isTelevision) {
        final allowed = await ds.canUserDownload(server);
        expect(allowed, isFalse);
      }
    });

    test('DownloadTask correctly computes progress and completion status', () {
      final task = DownloadTask(
        ratingKey: '1001',
        title: 'Hellboy',
        type: 'movie',
        downloadUrl: 'http://example.com/video.mp4',
        localFilePath: '/tmp/1001.mp4',
        serverId: 'srv_1',
        serverName: 'Server 1',
        serverType: 'plex',
        totalBytes: 1000,
        receivedBytes: 450,
      );

      expect(task.progress, closeTo(0.45, 0.001));
      expect(task.isRunning, isTrue);
      expect(task.isCompleted, isFalse);

      task.receivedBytes = 1000;
      task.status = DownloadStatus.completed;
      expect(task.progress, closeTo(1.0, 0.001));
      expect(task.isCompleted, isTrue);
      expect(task.isRunning, isFalse);
    });

    test('TV Shows grouping from downloaded episodes', () {
      // Create two episodes of the same show and one of another show
      const ep1 = PlexMediaItem(
        ratingKey: 'ep_1',
        key: 'ep_1',
        title: 'Pilot',
        type: 'episode',
        grandparentTitle: 'Breaking Bad',
        grandparentRatingKey: 'show_bb',
        parentTitle: 'Season 1',
        parentIndex: 1,
        index: 1,
      );

      const ep2 = PlexMediaItem(
        ratingKey: 'ep_2',
        key: 'ep_2',
        title: 'Cat\'s in the Bag...',
        type: 'episode',
        grandparentTitle: 'Breaking Bad',
        grandparentRatingKey: 'show_bb',
        parentTitle: 'Season 1',
        parentIndex: 1,
        index: 2,
      );

      const ep3 = PlexMediaItem(
        ratingKey: 'ep_3',
        key: 'ep_3',
        title: 'Winter Is Coming',
        type: 'episode',
        grandparentTitle: 'Game of Thrones',
        grandparentRatingKey: 'show_got',
        parentTitle: 'Season 1',
        parentIndex: 1,
        index: 1,
      );

      // Verify that episodes maintain grandparent metadata needed to group by show
      expect(ep1.grandparentTitle, equals('Breaking Bad'));
      expect(ep1.grandparentRatingKey, equals('show_bb'));
      expect(ep2.grandparentRatingKey, equals('show_bb'));
      expect(ep3.grandparentRatingKey, equals('show_got'));
    });

    test('Downloaded episodes sort order chooses the earliest season and episode', () {
      final episodes = [
        const PlexMediaItem(
          ratingKey: 'ep_203',
          key: 'ep_203',
          title: 'Episode 3',
          type: 'episode',
          parentIndex: 2,
          index: 3,
        ),
        const PlexMediaItem(
          ratingKey: 'ep_102',
          key: 'ep_102',
          title: 'Episode 2',
          type: 'episode',
          parentIndex: 1,
          index: 2,
        ),
        const PlexMediaItem(
          ratingKey: 'ep_201',
          key: 'ep_201',
          title: 'Episode 1',
          type: 'episode',
          parentIndex: 2,
          index: 1,
        ),
      ];

      episodes.sort((a, b) {
        final sA = a.parentIndex ?? 0;
        final sB = b.parentIndex ?? 0;
        if (sA != sB) return sA.compareTo(sB);
        final eA = a.index ?? 0;
        final eB = b.index ?? 0;
        return eA.compareTo(eB);
      });

      expect(episodes.first.ratingKey, equals('ep_102'));
      expect(episodes[1].ratingKey, equals('ep_201'));
      expect(episodes[2].ratingKey, equals('ep_203'));
    });
  });
}
