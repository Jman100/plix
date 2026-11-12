import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plix_profile.dart';
import 'package:plix/screens/auth_chooser_screen.dart';
import 'package:plix/screens/login_screen.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';
import 'package:plix/services/profile_service.dart';
import 'package:plix/widgets/plix_back_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlexAuthService authService;
  late PlexServerService serverService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = PlexAuthService();
    serverService = PlexServerService(authService: authService);
  });

  group('Profile Creation Cancellation', () {
    test('ProfileService.cancelProfileCreation deletes draft and restores previous profile', () async {
      final prefs = await SharedPreferences.getInstance();
      await ProfileService.instance.init();

      // Create an initial active profile (Profile 1)
      final prof1 = await ProfileService.instance.createProfile(
        name: 'Profile 1',
        avatarId: 'avatar_default',
      );
      await ProfileService.instance.setActiveProfile(prof1.id);
      expect(ProfileService.instance.activeProfile?.id, equals(prof1.id));
      expect(ProfileService.instance.profiles.length, equals(1));

      // Simulate starting to create Profile 2 (draft)
      final prof2 = await ProfileService.instance.createProfile(
        name: 'Profile 2',
        avatarId: 'avatar_popcorn',
      );
      await ProfileService.instance.setActiveProfile(prof2.id);
      await prefs.setString(ProfileService.key('plix_auth_token'), 'draft_token');
      expect(ProfileService.instance.profiles.length, equals(2));
      expect(ProfileService.instance.activeProfile?.id, equals(prof2.id));

      // Now cancel creation of Profile 2
      await ProfileService.instance.cancelProfileCreation(prof2.id, restoreProfileId: prof1.id);

      // Verify Profile 2 was cleanly removed
      expect(ProfileService.instance.profiles.length, equals(1));
      expect(ProfileService.instance.profiles.any((p) => p.id == prof2.id), isFalse);
      expect(ProfileService.instance.activeProfile?.id, equals(prof1.id));
      expect(prefs.containsKey('prof_${prof2.id}_plix_auth_token'), isFalse);
    });

    testWidgets('AuthChooserScreen shows PlixBackButton and cancels creation when pressed', (tester) async {
      await ProfileService.instance.init();

      final prof1 = await ProfileService.instance.createProfile(
        name: 'Profile 1',
        avatarId: 'avatar_default',
      );
      await ProfileService.instance.setActiveProfile(prof1.id);

      final draftProf = await ProfileService.instance.createProfile(
        name: 'Draft Profile',
        avatarId: 'avatar_popcorn',
      );
      await ProfileService.instance.setActiveProfile(draftProf.id);

      expect(ProfileService.instance.profiles.length, equals(2));
      expect(ProfileService.instance.activeProfile?.id, equals(draftProf.id));

      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onPopPage: (route, result) {
              popped = true;
              return route.didPop(result);
            },
            pages: [
              const MaterialPage(child: Scaffold(body: Text('Previous Screen'))),
              MaterialPage(
                child: AuthChooserScreen(
                  authService: authService,
                  serverService: serverService,
                  isCreatingProfile: true,
                  draftProfileId: draftProf.id,
                  previousProfileId: prof1.id,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // PlixBackButton must be present when isCreatingProfile is true
      final backButton = find.byType(PlixBackButton);
      expect(backButton, findsOneWidget);

      // Tap PlixBackButton
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      // Draft profile must be removed and previous profile restored
      expect(ProfileService.instance.profiles.length, equals(1));
      expect(ProfileService.instance.profiles.any((p) => p.id == draftProf.id), isFalse);
      expect(ProfileService.instance.activeProfile?.id, equals(prof1.id));
    });

    testWidgets('LoginScreen shows PlixBackButton for navigating back to AuthChooser', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            authService: authService,
            serverService: serverService,
            isCreatingProfile: true,
            draftProfileId: 'draft_id',
            previousProfileId: 'prev_id',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PlixBackButton), findsOneWidget);
    });
  });
}
