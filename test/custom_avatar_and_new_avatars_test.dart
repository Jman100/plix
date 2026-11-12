import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plix_profile.dart';
import 'package:plix/services/custom_avatar_service.dart';
import 'package:plix/widgets/profile_avatar_widget.dart';
import 'package:plix/widgets/custom_avatar_upload_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('New Avatars and Avatar List Tests', () {
    test('availableAvatars contains avatar_plex, avatar_jellyfin, windows, android, linux', () {
      final avatarIds = PlixProfile.availableAvatars.map((a) => a.id).toList();

      expect(avatarIds.contains('avatar_default'), isTrue);
      expect(avatarIds.contains('avatar_plex'), isTrue);
      expect(avatarIds.contains('avatar_jellyfin'), isTrue);
      expect(avatarIds.contains('avatar_windows'), isTrue);
      expect(avatarIds.contains('avatar_android'), isTrue);
      expect(avatarIds.contains('avatar_linux'), isTrue);

      final plex = PlixProfile.availableAvatars.firstWhere((a) => a.id == 'avatar_plex');
      expect(plex.label, 'Plex');
      expect(plex.assetPath, 'assets/avatars/avatar_plex.png');

      final jf = PlixProfile.availableAvatars.firstWhere((a) => a.id == 'avatar_jellyfin');
      expect(jf.label, 'Jellyfin');
      expect(jf.assetPath, 'assets/avatars/avatar_jellyfin.png');
    });

    test('CustomAvatarService.isCustomAvatar correctly identifies custom vs built-in IDs', () {
      expect(CustomAvatarService.isCustomAvatar('avatar_default'), isFalse);
      expect(CustomAvatarService.isCustomAvatar('avatar_plex'), isFalse);
      expect(CustomAvatarService.isCustomAvatar('avatar_jellyfin'), isFalse);
      expect(CustomAvatarService.isCustomAvatar('custom_1731448800000.png'), isTrue);
      expect(CustomAvatarService.isCustomAvatar('/data/user/0/com.plix.plix/custom_123.jpg'), isTrue);
    });
  });

  group('CustomAvatarService Validation Tests', () {
    test('validateImageBytes rejects empty bytes', () async {
      expect(
        () => CustomAvatarService.validateImageBytes(Uint8List(0)),
        throwsA(predicate((e) => e.toString().contains('empty'))),
      );
    });

    test('validateImageBytes rejects files larger than 10MB', () async {
      // 10MB + 1 byte
      final oversizedBytes = Uint8List(10 * 1024 * 1024 + 1);
      expect(
        () => CustomAvatarService.validateImageBytes(oversizedBytes),
        throwsA(predicate((e) => e.toString().contains('too large') || e.toString().contains('10 MB'))),
      );
    });

    test('validateImageBytes rejects non-image corrupted bytes', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        () => CustomAvatarService.validateImageBytes(invalidBytes),
        throwsA(predicate((e) => e.toString().contains('supported image format'))),
      );
    });

    test('downloadFromUrl rejects invalid or non-HTTP/HTTPS URLs', () async {
      expect(
        () => CustomAvatarService.downloadFromUrl(''),
        throwsA(predicate((e) => e.toString().contains('enter an image URL'))),
      );
      expect(
        () => CustomAvatarService.downloadFromUrl('ftp://example.com/image.png'),
        throwsA(predicate((e) => e.toString().contains('valid HTTP or HTTPS'))),
      );
      expect(
        () => CustomAvatarService.downloadFromUrl('not_a_url'),
        throwsA(predicate((e) => e.toString().contains('valid HTTP or HTTPS'))),
      );
    });
  });

  group('CustomAvatarUploadDialog UI Tests', () {
    testWidgets('CustomAvatarUploadDialog renders file upload button and URL input', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomAvatarUploadDialog(),
          ),
        ),
      );

      expect(find.text('Add Custom Avatar'), findsOneWidget);
      expect(find.text('Choose Image File'), findsOneWidget);
      expect(find.text('OR ENTER URL'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('CustomAvatarUploadDialog validates empty URL on Apply', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomAvatarUploadDialog(),
          ),
        ),
      );

      final applyFinder = find.widgetWithText(ElevatedButton, 'Apply');
      expect(applyFinder, findsOneWidget);
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      expect(find.text('Please enter an image URL.'), findsOneWidget);
    });
  });

  group('ProfileAvatarWidget Rendering Tests', () {
    testWidgets('ProfileAvatarWidget renders built-in avatar without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatarWidget(
              avatarId: 'avatar_plex',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.byType(ProfileAvatarWidget), findsOneWidget);
    });

    testWidgets('ProfileAvatarWidget handles custom avatar gracefully with fallback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatarWidget(
              avatarId: 'custom_nonexistent_123.png',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.byType(ProfileAvatarWidget), findsOneWidget);
    });
  });
}
