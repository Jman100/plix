import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/services/guest_mode_service.dart';
import 'package:plix/models/plex_media_item.dart';
import 'package:plix/widgets/incognito_icon.dart';
import 'package:plix/widgets/plix_button.dart';
import 'package:plix/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GuestModeService Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await GuestModeService.instance.exitGuestMode();
    });

    tearDown(() async {
      await GuestModeService.instance.exitGuestMode();
    });

    test('Guest mode toggle and temporary watch history lifecycle', () async {
      final service = GuestModeService.instance;
      await service.init();
      expect(service.isGuestMode, false);
      expect(service.continueWatching, isEmpty);

      // Enable guest mode
      await service.setGuestMode(true);
      expect(service.isGuestMode, true);
      expect(service.continueWatching, isEmpty);

      // Record in-progress item
      const testItem = PlexMediaItem(
        ratingKey: '101',
        key: '/library/metadata/101',
        title: 'Guest Movie',
        type: 'movie',
        duration: 6000000,
      );

      service.recordPlaybackProgress(testItem, 1200000, 6000000);
      expect(service.continueWatching.length, 1);
      expect(service.continueWatching.first.ratingKey, '101');
      expect(service.getViewOffset('101'), 1200000);

      // Finish item (95%)
      service.recordPlaybackProgress(testItem, 5800000, 6000000);
      expect(service.continueWatching, isEmpty);

      // Record another item
      const testItem2 = PlexMediaItem(
        ratingKey: '102',
        key: '/library/metadata/102',
        title: 'Guest Episode',
        type: 'episode',
        duration: 3000000,
      );
      service.recordPlaybackProgress(testItem2, 500000, 3000000);
      expect(service.continueWatching.length, 1);
      expect(service.continueWatching.first.ratingKey, '102');

      // Exit guest mode - must delete all temporary data
      await service.exitGuestMode();
      expect(service.isGuestMode, false);
      expect(service.continueWatching, isEmpty);
      expect(service.getViewOffset('102'), isNull);
    });

    test('Media watch progress from main account is completely hidden in guest mode', () async {
      final service = GuestModeService.instance;
      await service.exitGuestMode();

      // Item with 50% watch progress on main account (e.g. The Matrix)
      const matrix = PlexMediaItem(
        ratingKey: '999',
        key: '/library/metadata/999',
        title: 'The Matrix',
        type: 'movie',
        duration: 7200000, // 2 hours
        viewOffset: 3600000, // 1 hour (50%)
      );

      // In regular mode, watch progress and resume are active
      expect(matrix.viewOffset, 3600000);
      expect(matrix.isInProgress, true);
      expect(matrix.progressPercentage, 0.5);

      // Switch to guest mode
      await service.setGuestMode(true);
      expect(service.isGuestMode, true);

      // In guest mode, main account's progress MUST be completely hidden
      expect(matrix.viewOffset, isNull);
      expect(matrix.isInProgress, false);
      expect(matrix.progressPercentage, 0.0);

      // If guest watches 10 minutes of The Matrix in this guest session
      service.recordPlaybackProgress(matrix, 600000, 7200000);
      expect(matrix.viewOffset, 600000);
      expect(matrix.isInProgress, true);
      expect(matrix.progressPercentage, closeTo(600000 / 7200000, 0.001));

      // Exit guest mode - main account's original 50% progress is restored untouched
      await service.exitGuestMode();
      expect(matrix.viewOffset, 3600000);
      expect(matrix.isInProgress, true);
      expect(matrix.progressPercentage, 0.5);
    });

    test('App start/init always purges guest mode and starts in regular mode', () async {
      final service = GuestModeService.instance;
      await service.setGuestMode(true);
      expect(service.isGuestMode, true);

      // Simulate app restart / crash recovery
      await service.init();
      expect(service.isGuestMode, false);
      expect(service.continueWatching, isEmpty);
    });

    testWidgets('IncognitoIcon renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: IncognitoIcon(size: 24, color: Colors.amber),
            ),
          ),
        ),
      );

      expect(find.byType(IncognitoIcon), findsOneWidget);
    });

    testWidgets('PlixButton with highlightTextColor and theme color', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlixButton(
                focusNode: focusNode,
                label: 'Enable',
                icon: const Icon(Icons.check_rounded, size: 18),
                backgroundColor: Colors.white.withOpacity(0.1),
                borderColor: Colors.white.withOpacity(0.2),
                textColor: PlixTheme.textPrimary,
                highlightColor: PlixTheme.plexGold,
                highlightTextColor: Colors.black,
                highlightBorderColor: PlixTheme.plexGold,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Enable'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Focus the button
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, true);
    });
  });
}
