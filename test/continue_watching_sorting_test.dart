import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';

int getContinueWatchingTimestamp(PlexMediaItem item) {
  final viewed = item.lastViewedAt ?? 0;
  final added = item.addedAt ?? 0;
  final isUnplayedEpisode = item.type == 'episode' &&
      (item.viewOffset == null || item.viewOffset == 0) &&
      (item.viewCount == null || item.viewCount == 0);

  if (isUnplayedEpisode) {
    final airDate = DateTime.tryParse(item.originallyAvailableAt ?? '')?.millisecondsSinceEpoch;
    final airSecs = airDate != null ? airDate ~/ 1000 : 0;
    final recency = added > airSecs ? added : airSecs;
    if (recency > 0) {
      return recency > viewed ? recency : viewed;
    }
    return viewed > 0 ? viewed : DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }
  return viewed > 0 ? viewed : added;
}

void sortContinueWatching(List<PlexMediaItem> list) {
  list.sort((a, b) {
    final timeA = getContinueWatchingTimestamp(a);
    final timeB = getContinueWatchingTimestamp(b);
    if (timeA != timeB) {
      return timeB.compareTo(timeA);
    }
    return (b.addedAt ?? 0).compareTo(a.addedAt ?? 0);
  });
}

void main() {
  group('Continue Watching Sorting Tests', () {
    test('Newly added episode of a show appears at the front of continue watching', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final yesterday = now - 86400;

      // In-progress movie watched 2 weeks ago
      const movie1 = PlexMediaItem(
        ratingKey: '101',
        key: '/movie1',
        title: 'Older In-Progress Movie',
        type: 'movie',
        lastViewedAt: 1762000000,
        viewOffset: 3600000,
      );

      // In-progress movie watched yesterday
      final movie2 = PlexMediaItem(
        ratingKey: '102',
        key: '/movie2',
        title: 'Recent Movie',
        type: 'movie',
        lastViewedAt: yesterday,
        viewOffset: 1200000,
      );

      // Brand new episode of a show, added today with no view offset (unplayed)
      final newEpisode = PlexMediaItem(
        ratingKey: '201',
        key: '/ep201',
        title: 'New Episode',
        grandparentTitle: 'Show A',
        type: 'episode',
        addedAt: now,
        viewOffset: 0,
        viewCount: 0,
        lastViewedAt: null,
      );

      final list = [movie1, movie2, newEpisode];
      sortContinueWatching(list);

      // The new episode must be at index 0 (front of the row)
      expect(list.first.ratingKey, equals('201'));
      expect(list[1].ratingKey, equals('102'));
      expect(list[2].ratingKey, equals('101'));
    });
  });
}
