import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/screens/favorite_libraries_screen.dart';
import 'package:plix/screens/profile_setup_screen.dart';
import 'package:plix/services/guest_mode_service.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';
import 'package:plix/services/profile_service.dart';
import 'package:plix/widgets/incognito_icon.dart';
import 'package:plix/widgets/plix_tv_text_field.dart';
import 'package:plix/widgets/sidebar_nav.dart';
import 'package:plix/widgets/profile_avatar_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GuestModeService.instance.init();
    await GuestModeService.instance.setGuestMode(false);
    await ProfileService.instance.init();
  });

  group('FavoriteLibrariesScreen Refresh Button Tests', () {
    testWidgets('Refresh Servers button is visible and present up top in AppBar', (tester) async {
      final auth = PlexAuthService();
      final serverService = PlexServerService(authService: auth);
      final server = PlexServer(
        name: 'My Plex',
        clientIdentifier: 'my_plex_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: auth,
            serverService: serverService,
            servers: [server],
            isInitialSetup: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Refresh Servers'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.text('Save Changes'), findsNWidgets(2)); // top & bottom
    });

    testWidgets('Offline servers with 0 available libraries does not trap user on back', (tester) async {
      final auth = PlexAuthService();
      final serverService = PlexServerService(authService: auth);
      final offlineServer = PlexServer(
        name: 'Offline Server',
        clientIdentifier: 'offline_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: auth,
            serverService: serverService,
            servers: [offlineServer],
            isInitialSetup: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pump();

      expect(find.text('You must pick at least one favorite library.'), findsNothing);
    });
  });

  group('ProfileSetupScreen Keyboard & PlixTvTextField Tests', () {
    testWidgets('ProfileSetupScreen uses PlixTvTextField for profile name entry', (tester) async {
      final auth = PlexAuthService();
      final serverService = PlexServerService(authService: auth);

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileSetupScreen(
            authService: auth,
            serverService: serverService,
            isInitialSetup: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlixTvTextField), findsOneWidget);
    });
  });

  group('SidebarNav & Guest Mode Popup Tests', () {
    testWidgets('IncognitoIcon renders at requested size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: IncognitoIcon(size: 22, color: Colors.amber),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IncognitoIcon), findsOneWidget);
    });

    testWidgets('SidebarNav expanded width is 245.0', (tester) async {
      final server = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'srv_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SidebarNav(
              currentServer: server,
              libraries: const [],
              activeDestination: NavDestination.home,
              onDestinationSelected: (_) {},
              onLibrarySelected: (_) {},
              onSwitchServer: () {},
              onSignOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hover over SidebarNav to expand it
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SidebarNav)));
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(find.byType(SidebarNav));
      expect(box.size.width, equals(245.0));
    });

    testWidgets('Enter Guest Mode dialog defaults focus to Cancel', (tester) async {
      final server = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'srv_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SidebarNav(
              currentServer: server,
              libraries: const [],
              activeDestination: NavDestination.home,
              onDestinationSelected: (_) {},
              onLibrarySelected: (_) {},
              onSwitchServer: () {},
              onSignOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SidebarNav)));
      await tester.pumpAndSettle();

      final avatarFinder = find.byType(ProfileAvatarWidget).first;
      expect(avatarFinder, findsOneWidget);
      await tester.tap(avatarFinder);
      await tester.pumpAndSettle();

      // Profile popup menu should display 3 options in normal mode
      expect(find.text('Switch User'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Enter Guest Mode'), findsOneWidget);

      // Tap 'Enter Guest Mode'
      await tester.tap(find.text('Enter Guest Mode'));
      await tester.pumpAndSettle();

      // Info popup appears with explanation, Cancel, and Enable
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Enable'), findsOneWidget);

      // Default cursor / focus must be on Cancel button
      final cancelFocusFinder = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'guestCancel' && w.focusNode!.hasPrimaryFocus,
      );
      expect(cancelFocusFinder, findsOneWidget);

      // Tapping Cancel dismisses the dialog without enabling guest mode
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(GuestModeService.instance.isGuestMode, isFalse);
    });

    testWidgets('Enabling Guest Mode updates GuestModeService', (tester) async {
      final server = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'srv_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SidebarNav(
              currentServer: server,
              libraries: const [],
              activeDestination: NavDestination.home,
              onDestinationSelected: (_) {},
              onLibrarySelected: (_) {},
              onSwitchServer: () {},
              onSignOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SidebarNav)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ProfileAvatarWidget).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter Guest Mode'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(GuestModeService.instance.isGuestMode, isTrue);
    });

    testWidgets('Edit Profile button in popup calls onEditProfile callback', (tester) async {
      final server = PlexServer(
        name: 'Test Server',
        clientIdentifier: 'srv_1',
        accessToken: 'tok',
        owned: true,
        connections: [],
      );
      bool editProfileCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SidebarNav(
              currentServer: server,
              libraries: const [],
              activeDestination: NavDestination.home,
              onDestinationSelected: (_) {},
              onLibrarySelected: (_) {},
              onSwitchServer: () {},
              onSignOut: () {},
              onEditProfile: () => editProfileCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SidebarNav)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ProfileAvatarWidget).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(editProfileCalled, isTrue);
    });
  });
}
