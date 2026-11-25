import 'package:flutter_test/flutter_test.dart';
import 'package:plix/models/seerr_models.dart';

void main() {
  group('SeerrMediaItem & SeerrMediaDetails Tests', () {
    test('SeerrMediaItem parses discovery item correctly', () {
      final json = {
        'id': 603,
        'mediaType': 'movie',
        'title': 'The Matrix',
        'overview': 'A computer hacker learns about the true nature of reality.',
        'posterPath': '/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg',
        'backdropPath': '/hEpWvX6Bp79eLxY1W95ZZ0123.jpg',
        'releaseDate': '1999-03-30',
        'voteAverage': 8.2,
        'mediaInfo': {
          'status': 5,
        },
      };

      final item = SeerrMediaItem.fromJson(json);
      expect(item.id, 603);
      expect(item.isMovie, isTrue);
      expect(item.isTv, isFalse);
      expect(item.title, 'The Matrix');
      expect(item.year, '1999');
      expect(item.isAvailable, isTrue);
      expect(item.posterUrl, contains('https://image.tmdb.org/t/p/w500/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg'));
      expect(item.backdropUrl, contains('https://image.tmdb.org/t/p/w780/hEpWvX6Bp79eLxY1W95ZZ0123.jpg'));
    });

    test('SeerrMediaItem parses request response correctly', () {
      final json = {
        'id': 101,
        'status': 2, // approved
        'type': 'tv',
        'media': {
          'id': 50,
          'tmdbId': 1399,
          'mediaType': 'tv',
          'title': 'Game of Thrones',
          'status': 4, // partially available
          'poster': '/u3bZgnGQ9T01sWNhyveQz0wH0Hl.jpg',
        },
        'seasons': [
          {'seasonNumber': 1},
          {'seasonNumber': 2},
        ],
      };

      final item = SeerrMediaItem.fromJson(json);
      expect(item.id, 1399);
      expect(item.isTv, isTrue);
      expect(item.requestId, 101);
      expect(item.requestStatus, 2);
      expect(item.mediaStatus, 4);
      expect(item.isPartiallyAvailable, isTrue);
      expect(item.requestedSeasons, [1, 2]);
    });

    test('SeerrMediaDetails parses TV show with seasons and availability correctly', () {
      final json = {
        'id': 1399,
        'name': 'Game of Thrones',
        'firstAirDate': '2011-04-17',
        'genres': [
          {'id': 18, 'name': 'Drama'},
          {'id': 10765, 'name': 'Sci-Fi & Fantasy'},
        ],
        'seasons': [
          {
            'id': 1,
            'seasonNumber': 0,
            'name': 'Specials',
            'episodeCount': 20,
          },
          {
            'id': 2,
            'seasonNumber': 1,
            'name': 'Season 1',
            'episodeCount': 10,
          },
          {
            'id': 3,
            'seasonNumber': 2,
            'name': 'Season 2',
            'episodeCount': 10,
          },
        ],
        'mediaInfo': {
          'status': 4,
          'seasons': [
            {
              'seasonNumber': 1,
              'status': 5, // Available
            },
            {
              'seasonNumber': 2,
              'status': 1, // Unknown / Not available
            },
          ],
        },
      };

      final details = SeerrMediaDetails.fromJson(json, 'tv');
      expect(details.id, 1399);
      expect(details.title, 'Game of Thrones');
      expect(details.year, '2011');
      expect(details.genres, ['Drama', 'Sci-Fi & Fantasy']);
      // Season 0 (specials) skipped, seasons 1 and 2 present
      expect(details.seasons.length, 2);
      expect(details.seasons[0].seasonNumber, 1);
      expect(details.seasons[0].isAvailable, isTrue);
      expect(details.seasons[0].isAvailableOrRequested, isTrue);
      expect(details.seasons[1].seasonNumber, 2);
      expect(details.seasons[1].isAvailableOrRequested, isFalse);
    });

    test('SeerrMediaDetails handles 4K status and availability for movies', () {
      final json = {
        'id': 550,
        'title': 'Fight Club',
        'releaseDate': '1999-10-15',
        'genres': [
          {'id': 18, 'name': 'Drama'},
        ],
        'mediaInfo': {
          'status': 5, // Standard Available
          'status4k': 1, // 4K not available/not requested
          'ratingKey': '12345',
          'requests': [
            {'is4k': false, 'status': 2}, // Standard approved
          ],
        },
      };

      final details = SeerrMediaDetails.fromJson(json, 'movie');
      expect(details.id, 550);
      expect(details.isStandardAvailable, isTrue);
      expect(details.isStandardRequestedOrAvailable, isTrue);
      expect(details.is4kAvailable, isFalse);
      expect(details.is4kRequestedOrAvailable, isFalse);
      expect(details.isAnyAvailable, isTrue);
      expect(details.ratingKey, '12345');
    });

    test('SeerrMediaDetails handles 4K requested but not standard requested', () {
      final json = {
        'id': 551,
        'title': 'The Matrix Reloaded',
        'releaseDate': '2003-05-15',
        'genres': [],
        'mediaInfo': {
          'status': 1,
          'status4k': 2, // 4K pending
          'requests': [
            {'is4k': true, 'status': 1}, // 4K pending
          ],
        },
      };

      final details = SeerrMediaDetails.fromJson(json, 'movie');
      expect(details.isStandardAvailable, isFalse);
      expect(details.isStandardRequestedOrAvailable, isFalse);
      expect(details.is4kAvailable, isFalse);
      expect(details.is4kRequestedOrAvailable, isTrue);
      expect(details.isAnyAvailable, isFalse);
    });
  });
}
