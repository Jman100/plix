import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/services/ratings_service.dart';
import 'package:plix/services/plix_device_helper.dart';
import 'package:plix/services/update_service.dart';
import 'package:plix/services/download_service.dart';
import 'package:plix/widgets/ratings_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlexMediaItem Ratings Parsing', () {
    test('Parses Rotten Tomatoes critic and audience ratings from Rating array', () {
      final json = {
        'ratingKey': '101',
        'key': '/library/metadata/101',
        'title': 'Test Movie',
        'type': 'movie',
        'year': 2024,
        'Rating': [
          {
            'image': 'rottentomatoes://image.rating.certified',
            'value': 9.2,
            'type': 'critic',
          },
          {
            'image': 'rottentomatoes://image.rating.upright',
            'value': 8.8,
            'type': 'audience',
          },
          {
            'image': 'imdb://image.rating',
            'value': 8.1,
            'type': 'audience',
          },
        ],
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.rtCriticScore, equals(92));
      expect(item.isRtCertified, isTrue);
      expect(item.isRtFresh, isTrue);
      expect(item.rtAudienceScore, equals(88));
      expect(item.isRtAudienceFresh, isTrue);
      expect(item.hasRtRatings, isTrue);
      expect(item.hasRatings, isTrue);
    });

    test('Parses Rotten Tomatoes rotten score and spilled popcorn', () {
      final json = {
        'ratingKey': '102',
        'key': '/library/metadata/102',
        'title': 'Rotten Movie',
        'type': 'movie',
        'year': 2020,
        'rating': 3.5,
        'ratingImage': 'rottentomatoes://image.rating.rotten',
        'audienceRating': 4.2,
        'audienceRatingImage': 'rottentomatoes://image.rating.spilled',
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.rtCriticScore, equals(35));
      expect(item.isRtCertified, isFalse);
      expect(item.isRtFresh, isFalse);
      expect(item.rtAudienceScore, equals(42));
      expect(item.isRtAudienceFresh, isFalse);
      expect(item.hasRtRatings, isTrue);
    });

    test('Parses both critic and audience ratings from movie top-level and Rating list', () {
      final json = {
        'ratingKey': '160383',
        'key': '/library/metadata/160383',
        'title': 'Hellboy',
        'type': 'movie',
        'year': 2004,
        'rating': 8.1,
        'ratingImage': 'rottentomatoes://image.rating.ripe',
        'audienceRating': 6.6,
        'audienceRatingImage': 'rottentomatoes://image.rating.upright',
        'Rating': [
          {'image': 'imdb://image.rating', 'value': 6.9, 'type': 'audience'},
          {'image': 'rottentomatoes://image.rating.ripe', 'value': 8.1, 'type': 'critic'},
          {'image': 'rottentomatoes://image.rating.upright', 'value': 6.6, 'type': 'audience'},
        ],
      };

      final item = PlexMediaItem.fromJson(json);
      expect(item.rtCriticScore, equals(81));
      expect(item.isRtFresh, isTrue);
      expect(item.rtAudienceScore, equals(66));
      expect(item.isRtAudienceFresh, isTrue);
    });

    testWidgets('RottenTomatoesRatingBadge renders both critic and audience badges', (tester) async {
      final json = {
        'ratingKey': '160383',
        'key': '/library/metadata/160383',
        'title': 'Hellboy',
        'type': 'movie',
        'year': 2004,
        'rating': 8.1,
        'ratingImage': 'rottentomatoes://image.rating.ripe',
        'audienceRating': 6.6,
        'audienceRatingImage': 'rottentomatoes://image.rating.upright',
      };
      final item = PlexMediaItem.fromJson(json);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaRatingWidget(item: item),
          ),
        ),
      );

      expect(find.text('81%'), findsOneWidget);
      expect(find.text('66%'), findsOneWidget);
      expect(find.byType(TomatoIconWidget), findsOneWidget);
      expect(find.byType(PopcornIconWidget), findsOneWidget);
    });

    test('Parses IMDb rating for TV show and episode', () {
      final showJson = {
        'ratingKey': '201',
        'key': '/library/metadata/201',
        'title': 'Test Show',
        'type': 'show',
        'year': 2023,
        'Rating': [
          {
            'image': 'imdb://image.rating',
            'value': 8.7,
            'type': 'audience',
          },
        ],
      };

      final show = PlexMediaItem.fromJson(showJson);
      expect(show.imdbRating, equals(8.7));
      expect(show.formattedImdbRating, equals('8.7'));
      expect(show.hasImdbRating, isTrue);
      expect(show.hasRatings, isTrue);

      final epJson = {
        'ratingKey': '202',
        'key': '/library/metadata/202',
        'title': 'Test Episode',
        'type': 'episode',
        'rating': 8.6,
        'audienceRatingImage': 'imdb://image.rating',
      };

      final ep = PlexMediaItem.fromJson(epJson);
      expect(ep.formattedImdbRating, equals('8.6'));
      expect(ep.hasImdbRating, isTrue);
    });

    test('Jellyfin CriticRating and CommunityRating are mapped correctly', () {
      const jfMovie = PlexMediaItem(
        ratingKey: 'jf101',
        key: '/Items/jf101',
        title: 'JF Movie',
        type: 'movie',
        rating: 8.5,
        ratingImage: 'rottentomatoes://image.rating.ripe',
        audienceRating: 7.9,
        audienceRatingImage: 'imdb://image.rating',
        ratings: [
          {
            'image': 'rottentomatoes://image.rating.ripe',
            'value': 85.0,
            'type': 'critic',
          },
          {
            'image': 'imdb://image.rating',
            'value': 7.9,
            'type': 'audience',
          },
        ],
      );

      expect(jfMovie.rtCriticScore, equals(85));
      expect(jfMovie.isRtFresh, isTrue);
      expect(jfMovie.imdbRating, equals(7.9));
    });

    test('Movie with no RT scores falls back to TMDB rating and renders TmdbRatingBadge', () {
      final json = {
        'ratingKey': '160318',
        'key': '/library/metadata/160318',
        'title': 'Metalocalypse: The Doomstar Requiem',
        'type': 'movie',
        'Rating': [
          {
            'image': 'imdb://image.rating',
            'value': 7.9,
            'type': 'audience',
          },
          {
            'image': 'themoviedb://image.rating',
            'value': 7.7,
            'type': 'audience',
          },
        ],
      };
      final item = PlexMediaItem.fromJson(json);
      expect(item.hasRtRatings, isFalse);
      expect(item.rtAudienceScore, isNull);
      expect(item.hasTmdbRating, isTrue);
      expect(item.formattedTmdbRating, equals('7.7'));
    });

    testWidgets('Plex TV show with only themoviedb audienceRating in library renders ImdbRatingBadge', (tester) async {
      final showJson = {
        'ratingKey': '501',
        'key': '/library/metadata/501',
        'title': 'Plex TV Show',
        'type': 'show',
        'audienceRating': 8.3,
        'audienceRatingImage': 'themoviedb://image.rating',
      };
      final show = PlexMediaItem.fromJson(showJson);
      expect(show.hasRatings, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaRatingWidget(item: show),
          ),
        ),
      );
      expect(find.byType(ImdbRatingBadge), findsOneWidget);
      expect(find.text('8.3'), findsOneWidget);
    });

    testWidgets('Jellyfin TV show renders TmdbRatingBadge', (tester) async {
      const jfShow = PlexMediaItem(
        ratingKey: 'jf_show_1',
        key: '/Items/jf_show_1',
        title: 'Jellyfin TV Show',
        type: 'show',
        rating: 8.1,
      );
      expect(jfShow.isJellyfin, isTrue);
      expect(jfShow.hasRatings, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaRatingWidget(item: jfShow),
          ),
        ),
      );
      expect(find.byType(TmdbRatingBadge), findsOneWidget);
      expect(find.text('8.1'), findsOneWidget);
    });
  });

  group('RatingsService Mode Cycles and Defaults', () {
    test('Default mode is detailsOnly and cycles properly', () async {
      SharedPreferences.setMockInitialValues({});
      final service = RatingsService.instance;
      await service.init();

      expect(service.mode, equals(RatingsMode.detailsOnly));
      expect(service.showInDetails, isTrue);
      expect(service.showOnPosters, isFalse);
      expect(service.isOff, isFalse);

      await service.cycleMode();
      expect(service.mode, equals(RatingsMode.posters));
      expect(service.showInDetails, isTrue);
      expect(service.showOnPosters, isTrue);
      expect(service.isOff, isFalse);

      await service.cycleMode();
      expect(service.mode, equals(RatingsMode.off));
      expect(service.showInDetails, isFalse);
      expect(service.showOnPosters, isFalse);
      expect(service.isOff, isTrue);

      await service.cycleMode();
      expect(service.mode, equals(RatingsMode.detailsOnly));
    });
  });

  group('Client Name with Version reporting', () {
    test('Client name includes version number', () {
      final v = UpdateService.currentVersion;
      final name = PlixDeviceHelper.clientName;
      expect(name, contains('v$v'));
      if (Platform.isWindows) {
        expect(name, equals('Plix Windows v$v'));
      } else if (Platform.isLinux) {
        expect(name, equals('Plix Linux v$v'));
      }
    });
  });

  group('Download Directory & Permissions', () {
    test('testWritePermissions succeeds for existing temporary directory', () async {
      final tempDir = Directory.systemTemp.createTempSync('plix_test_dl_');
      try {
        final writable = await DownloadService.testWritePermissions(tempDir.path);
        expect(writable, isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('testWritePermissions returns false for non-writable invalid paths', () async {
      final badPath = Platform.isWindows ? r'Z:\non_existent_drive_plix\sub' : '/root/non_existent_plix/sub';
      final writable = await DownloadService.testWritePermissions(badPath);
      expect(writable, isFalse);
    });
  });
}
