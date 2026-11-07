import 'package:plix/screens/splash_screen.dart';
import 'package:plix/screens/favorite_libraries_screen.dart';
import 'package:plix/widgets/plix_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/screens/auth_chooser_screen.dart';
import 'package:plix/screens/home_screen.dart';
import 'package:plix/screens/jellyfin_connect_screen.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';
import 'package:plix/widgets/brand_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlexAuthService authService;
  late PlexServerService serverService;

  final testServer = PlexServer(
    name: 'Test Server',
    clientIdentifier: 'test_srv',
    accessToken: 'tok_test',
    owned: true,
    connections: [],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = PlexAuthService();
    serverService = PlexServerService(authService: authService);
  });

  group('AuthChooserScreen Brand & Logo Styling', () {
    testWidgets('uses official PlixAppLogo and PlixWordmark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthChooserScreen(
            authService: authService,
            serverService: serverService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlixAppLogo), findsOneWidget);
      expect(find.byType(PlixWordmark), findsOneWidget);
    });

    testWidgets('uses PlexLogo and JellyfinLogo with official Jellyfin purple', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthChooserScreen(
            authService: authService,
            serverService: serverService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlexLogo), findsOneWidget);
      expect(find.byType(JellyfinLogo), findsOneWidget);

      final jfLogo = tester.widget<JellyfinLogo>(find.byType(JellyfinLogo));
      expect(jfLogo.color, equals(const Color(0xFF8E51DC)));
    });
  });

  group('JellyfinConnectScreen Focus Behavior', () {
    testWidgets('cursor defaults to Continue to Quick Connect button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: JellyfinConnectScreen(
            authService: authService,
            serverService: serverService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Continue to Quick Connect button exists and is in the active focus tree
      final continueTextFinder = find.text('Continue to Quick Connect');
      expect(continueTextFinder, findsOneWidget);

      // Verify the Focus wrapper around Continue to Quick Connect has autofocus enabled
      final focusWidgets = tester.widgetList<Focus>(find.byType(Focus));
      final continueFocusWidget = focusWidgets.firstWhere(
        (f) => f.autofocus == true && f.debugLabel != 'Navigator',
      );
      expect(continueFocusWidget.autofocus, isTrue);
    });
  });

  group('Welcome Tour Splash Screen on HomeScreen', () {
    testWidgets('shows on fresh install first time login and locks focus', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('plix_fresh_install_pending_tour', true);
      await serverService.saveFavoriteLibraryIds(['test_srv_lib1']);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            server: testServer,
            authService: authService,
            serverService: serverService,
          ),
        ),
      );

      // Pump post-frame callback
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // The Welcome Tour dialog should appear with all 4 TV features visible
      expect(find.text('Atmosphere Themes & Styles'), findsOneWidget);
      expect(find.text('Unified Multi-Server Experience'), findsOneWidget);
      expect(find.text('Living Room D-Pad Navigation'), findsOneWidget);
      expect(find.text('4K HDR & Direct Audio Passthrough'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);

      // On TV, there should be NO SingleChildScrollView in the dialog (fits all on screen at once)
      final dialogFinder = find.byType(Dialog);
      expect(dialogFinder, findsOneWidget);
      final scrollFinder = find.descendant(of: dialogFinder, matching: find.byType(SingleChildScrollView));
      expect(scrollFinder, findsNothing);

      // Verify focus lock properties on Get Started button
      final buttonFinder = find.descendant(of: dialogFinder, matching: find.byType(PlixButton));
      expect(buttonFinder, findsOneWidget);
      final plixBtn = tester.widget<PlixButton>(buttonFinder);
      expect(plixBtn.blockUp, isTrue);
      expect(plixBtn.blockDown, isTrue);
      expect(plixBtn.blockLeft, isTrue);
      expect(plixBtn.blockRight, isTrue);

      // Check SharedPreferences flag was set to true and pending removed
      expect(prefs.getBool('plix_welcome_tour_shown'), isTrue);
      expect(prefs.containsKey('plix_fresh_install_pending_tour'), isFalse);

      // Tap Get Started to dismiss
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('Atmosphere Themes & Styles'), findsNothing);
    });

    testWidgets('never shows for existing users or updates without fresh install flag', (tester) async {
      // An existing user or app update will NOT have plix_fresh_install_pending_tour
      await serverService.saveFavoriteLibraryIds(['test_srv_lib1']);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            server: testServer,
            authService: authService,
            serverService: serverService,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Atmosphere Themes & Styles'), findsNothing);
      expect(find.text('Get Started'), findsNothing);
    });

    testWidgets('does not show if already shown previously', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('plix_welcome_tour_shown', true);
      await prefs.setBool('plix_fresh_install_pending_tour', true);
      await serverService.saveFavoriteLibraryIds(['test_srv_lib1']);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            server: testServer,
            authService: authService,
            serverService: serverService,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Atmosphere Themes & Styles'), findsNothing);
      expect(find.text('Get Started'), findsNothing);
    });
  });

  group('SplashScreen v1.6.0 Update Migration', () {
    testWidgets('updating users without v1.6.0 favorites prompted are shown favorite libraries screen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final prefs = await SharedPreferences.getInstance();
      // Prior version install: token and active server exist, but v160 not prompted
      await prefs.setString('auth_token', 'saved_token_123');
      await prefs.setString('active_server_id', 'test_srv');
      await serverService.saveJellyfinServer(testServer);

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            authService: authService,
            serverService: serverService,
          ),
        ),
      );

      // Splash delay
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // Should be navigated to FavoriteLibrariesScreen
      expect(find.byType(FavoriteLibrariesScreen), findsOneWidget);
      expect(prefs.getBool('plix_v160_favorites_prompted'), isTrue);
    });

    testWidgets('users with v1.6.0 favorites already prompted bypass to HomeScreen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'saved_token_123');
      await prefs.setString('active_server_id', 'test_srv');
      await prefs.setBool('plix_v160_favorites_prompted', true);
      await serverService.saveFavoriteLibraryIds(['test_srv_lib1']);
      await serverService.saveJellyfinServer(testServer);

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            authService: authService,
            serverService: serverService,
          ),
        ),
      );

      // Splash delay
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // Should be navigated directly to HomeScreen, not FavoriteLibrariesScreen
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(FavoriteLibrariesScreen), findsNothing);
    });
  });
}
