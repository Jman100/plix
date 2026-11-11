import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/plex_media_item.dart';

void main() {
  group('PlexMediaItem SortTitle & Article Normalization Tests', () {
    test('normalizeSortTitle strips leading "The " and uses second word', () {
      expect(PlexMediaItem.normalizeSortTitle('The Matrix'), equals('Matrix'));
      expect(PlexMediaItem.normalizeSortTitle('The Dark Knight'), equals('Dark Knight'));
      expect(PlexMediaItem.normalizeSortTitle('the godfather'), equals('godfather'));
    });

    test('normalizeSortTitle strips leading "A " and "An "', () {
      expect(PlexMediaItem.normalizeSortTitle('A Beautiful Mind'), equals('Beautiful Mind'));
      expect(PlexMediaItem.normalizeSortTitle('An American Werewolf in London'), equals('American Werewolf in London'));
    });

    test('normalizeSortTitle preserves titles that are just "The", "A", or words starting with "the"', () {
      expect(PlexMediaItem.normalizeSortTitle('The'), equals('The'));
      expect(PlexMediaItem.normalizeSortTitle('A'), equals('A'));
      expect(PlexMediaItem.normalizeSortTitle('There Will Be Blood'), equals('There Will Be Blood'));
      expect(PlexMediaItem.normalizeSortTitle('They Live'), equals('They Live'));
      expect(PlexMediaItem.normalizeSortTitle('Theme Park'), equals('Theme Park'));
    });

    test('normalizeSortTitle handles server comma suffix like "Matrix, The"', () {
      expect(PlexMediaItem.normalizeSortTitle('The Matrix', 'Matrix, The'), equals('Matrix'));
      expect(PlexMediaItem.normalizeSortTitle('The Dark Knight', 'Dark Knight, The'), equals('Dark Knight'));
    });

    test('normalizeSortTitle respects server custom titleSort when provided', () {
      expect(PlexMediaItem.normalizeSortTitle('Star Wars: Episode IV', 'Star Wars 4'), equals('Star Wars 4'));
    });

    test('normalizeSortTitle strips leading quotes', () {
      expect(PlexMediaItem.normalizeSortTitle('"The Matrix"'), equals('Matrix'));
      expect(PlexMediaItem.normalizeSortTitle("'The Matrix'"), equals('Matrix'));
    });
  });

  group('Library View Sorting & Alphabet Rail Matching Tests', () {
    test('Items starting with "The" sort by second word, not lumped under T', () {
      const items = [
        PlexMediaItem(ratingKey: '1', key: '/1', title: 'The Avengers', type: 'movie'),
        PlexMediaItem(ratingKey: '2', key: '/2', title: 'Batman Begins', type: 'movie'),
        PlexMediaItem(ratingKey: '3', key: '/3', title: 'The Dark Knight', type: 'movie'),
        PlexMediaItem(ratingKey: '4', key: '/4', title: 'Fight Club', type: 'movie'),
        PlexMediaItem(ratingKey: '5', key: '/5', title: 'The Matrix', type: 'movie'),
        PlexMediaItem(ratingKey: '6', key: '/6', title: 'Matrix Reloaded', type: 'movie'),
      ];

      final sorted = List<PlexMediaItem>.from(items)
        ..sort((a, b) => a.sortTitle.toLowerCase().compareTo(b.sortTitle.toLowerCase()));

      final titles = sorted.map((e) => e.title).toList();
      expect(titles, equals([
        'The Avengers', // A
        'Batman Begins', // B
        'The Dark Knight', // D
        'Fight Club', // F
        'The Matrix', // M (Matrix)
        'Matrix Reloaded', // M (Matrix Reloaded)
      ]));
    });

    test('Alphabet jump letter for "The Matrix" is M, not T', () {
      String getItemLetter(PlexMediaItem item) {
        final title = item.sortTitle.trimLeft();
        if (title.isEmpty) return '#';
        final first = title[0].toUpperCase();
        if (first.compareTo('A') >= 0 && first.compareTo('Z') <= 0) {
          return first;
        }
        return '#';
      }

      const itemMatrix = PlexMediaItem(ratingKey: '1', key: '/1', title: 'The Matrix', type: 'movie');
      const itemDarkKnight = PlexMediaItem(ratingKey: '2', key: '/2', title: 'The Dark Knight', type: 'movie');
      const itemAvengers = PlexMediaItem(ratingKey: '3', key: '/3', title: 'The Avengers', type: 'movie');

      expect(getItemLetter(itemMatrix), equals('M'));
      expect(getItemLetter(itemDarkKnight), equals('D'));
      expect(getItemLetter(itemAvengers), equals('A'));
    });
  });

  group('Search Relevance & Query Matching Tests', () {
    int searchScore(PlexMediaItem item, String query) {
      final normQ = query.trim().toLowerCase();
      final strippedQ = PlexMediaItem.normalizeSortTitle(normQ).toLowerCase();
      final title = item.title.trim().toLowerCase();
      final sortTitle = item.sortTitle.trim().toLowerCase();
      final series = (item.grandparentTitle ?? '').trim().toLowerCase();
      final seriesSort = PlexMediaItem.normalizeSortTitle(series).toLowerCase();

      if (sortTitle == strippedQ || title == normQ || title == strippedQ || sortTitle == normQ) {
        return (item.isMovie || item.isShow) ? 0 : 1;
      }
      if (sortTitle.startsWith(strippedQ) || title.startsWith(normQ) || title.startsWith(strippedQ)) {
        return (item.isMovie || item.isShow) ? 2 : 3;
      }
      if (seriesSort == strippedQ || series == normQ || series == strippedQ) {
        return 4;
      }
      if (seriesSort.startsWith(strippedQ) || series.startsWith(normQ) || series.startsWith(strippedQ)) {
        return 5;
      }
      if (sortTitle.contains(strippedQ) || title.contains(normQ) || title.contains(strippedQ)) {
        return (item.isMovie || item.isShow) ? 6 : 7;
      }
      if (seriesSort.contains(strippedQ) || series.contains(normQ) || series.contains(strippedQ)) {
        return 8;
      }
      return 10;
    }

    test('Searching "matrix" gives exact match score 0 to "The Matrix"', () {
      const itemTheMatrix = PlexMediaItem(ratingKey: '1', key: '/1', title: 'The Matrix', type: 'movie');
      const itemReloaded = PlexMediaItem(ratingKey: '2', key: '/2', title: 'The Matrix Reloaded', type: 'movie');
      const itemDoc = PlexMediaItem(ratingKey: '3', key: '/3', title: 'Inside the Matrix', type: 'movie');

      expect(searchScore(itemTheMatrix, 'matrix'), equals(0));
      expect(searchScore(itemReloaded, 'matrix'), equals(2));
      expect(searchScore(itemDoc, 'matrix'), equals(6));
    });

    test('Searching "the matrix" matches both "The Matrix" and "Matrix"', () {
      const itemTheMatrix = PlexMediaItem(ratingKey: '1', key: '/1', title: 'The Matrix', type: 'movie');
      const itemMatrixOnly = PlexMediaItem(ratingKey: '2', key: '/2', title: 'Matrix', type: 'movie');

      expect(searchScore(itemTheMatrix, 'the matrix'), equals(0));
      expect(searchScore(itemMatrixOnly, 'the matrix'), equals(0));
    });

    test('Search results sort ranks "The Matrix" at the top when searching "matrix"', () {
      const list = [
        PlexMediaItem(ratingKey: '3', key: '/3', title: 'Inside the Matrix', type: 'movie'),
        PlexMediaItem(ratingKey: '2', key: '/2', title: 'The Matrix Revolutions', type: 'movie'),
        PlexMediaItem(ratingKey: '1', key: '/1', title: 'The Matrix', type: 'movie'),
        PlexMediaItem(ratingKey: '4', key: '/4', title: 'The Matrix Reloaded', type: 'movie'),
      ];

      final sorted = List<PlexMediaItem>.from(list)
        ..sort((a, b) {
          final scoreA = searchScore(a, 'matrix');
          final scoreB = searchScore(b, 'matrix');
          if (scoreA != scoreB) return scoreA.compareTo(scoreB);
          return a.sortTitle.toLowerCase().compareTo(b.sortTitle.toLowerCase());
        });

      expect(sorted.first.title, equals('The Matrix'));
      expect(sorted[1].title, equals('The Matrix Reloaded'));
      expect(sorted[2].title, equals('The Matrix Revolutions'));
      expect(sorted[3].title, equals('Inside the Matrix'));
    });
  });
}
