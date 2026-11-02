import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_library.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/screens/favorite_libraries_screen.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlexAuthService authService;
  late PlexServerService serverService;

  final ownedServer = PlexServer(
    name: 'Owned Plex Server',
    clientIdentifier: 'owned_srv',
    accessToken: 'tok_owned',
    owned: true,
    connections: [],
  );

  final sharedServer = PlexServer(
    name: 'Shared Plex Server',
    clientIdentifier: 'shared_srv',
    accessToken: 'tok_shared',
    owned: false,
    connections: [],
  );

  final ownedLib1 = PlexLibrary(
    key: '1',
    title: 'Owned Movies',
    type: 'movie',
    serverId: 'owned_srv',
  );

  final sharedLib1 = PlexLibrary(
    key: '2',
    title: 'Shared Movies',
    type: 'movie',
    serverId: 'shared_srv',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = PlexAuthService();
    serverService = PlexServerService(authService: authService);
  });

  group('FavoriteLibrariesScreen tests', () {
    testWidgets('Initial sign in defaults to only favoriting owned server libraries', (tester) async {
      await serverService.cacheServerLibraries('owned_srv', [ownedLib1]);
      await serverService.cacheServerLibraries('shared_srv', [sharedLib1]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [ownedServer, sharedServer],
            isInitialSetup: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1 heart in banner + 1 heart on Owned Movies card = 2 total
      final favIcons = find.byIcon(Icons.favorite_rounded);
      expect(favIcons, findsNWidgets(2));

      // Shared Movies should be unfavorited (Icons.favorite_border_rounded)
      final unFavIcons = find.byIcon(Icons.favorite_border_rounded);
      expect(unFavIcons, findsOneWidget);
    });

    testWidgets('Initial sign in with NO owned servers defaults to 0 favorited libraries', (tester) async {
      await serverService.cacheServerLibraries('shared_srv', [sharedLib1]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [sharedServer],
            isInitialSetup: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Only the 1 heart in banner, 0 on library cards
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('Save changes with 0 favorites selected shows toast and blocks saving', (tester) async {
      await serverService.cacheServerLibraries('shared_srv', [sharedLib1]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [sharedServer],
            isInitialSetup: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Save Changes in AppBar
      final saveBtn = find.text('Save Changes').first;
      await tester.tap(saveBtn);
      await tester.pump();

      // Verify toast message appeared
      expect(find.text('You must pick at least one favorite library.'), findsOneWidget);

      // Verify no favorites saved
      expect(await serverService.getFavoriteLibraryIds(), isNull);
    });

    testWidgets('Back attempt with 0 favorites selected shows toast and blocks leaving', (tester) async {
      await serverService.cacheServerLibraries('shared_srv', [sharedLib1]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [sharedServer],
            isInitialSetup: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Back button in AppBar
      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pump();

      // Verify toast message appeared
      expect(find.text('You must pick at least one favorite library.'), findsOneWidget);

      // Still on FavoriteLibrariesScreen
      expect(find.text('Favorite Libraries'), findsOneWidget);
    });

    testWidgets('Selecting a favorite library and clicking Save Changes succeeds', (tester) async {
      await serverService.cacheServerLibraries('shared_srv', [sharedLib1]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [sharedServer],
            isInitialSetup: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Shared Movies to favorite it
      await tester.tap(find.text('Shared Movies'));
      await tester.pumpAndSettle();

      // Now tap Save Changes
      await tester.tap(find.text('Save Changes').first);
      await tester.pumpAndSettle();

      // Verify favorite was saved
      final saved = await serverService.getFavoriteLibraryIds();
      expect(saved, isNotNull);
      expect(saved, contains(sharedLib1.compositeId));
    });

    testWidgets('Newly added server is sorted to the top of FavoriteLibrariesScreen', (tester) async {
      final oldServer = PlexServer(
        name: 'Old Server',
        clientIdentifier: 'old_srv',
        accessToken: 'tok_old',
        owned: true,
        connections: [],
      );

      final newServer = PlexServer(
        name: 'New Server',
        clientIdentifier: 'new_srv',
        accessToken: 'tok_new',
        owned: true,
        connections: [],
      );

      // Record old server first, then new server
      await serverService.recordServersAdded(['old_srv']);
      await serverService.recordServersAdded(['new_srv']);

      await serverService.cacheServerLibraries('old_srv', []);
      await serverService.cacheServerLibraries('new_srv', []);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoriteLibrariesScreen(
            authService: authService,
            serverService: serverService,
            servers: [oldServer, newServer],
            isInitialSetup: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find all server header texts
      final newServerTextFinder = find.text('New Server');
      final oldServerTextFinder = find.text('Old Server');

      expect(newServerTextFinder, findsOneWidget);
      expect(oldServerTextFinder, findsOneWidget);

      final newServerTop = tester.getTopLeft(newServerTextFinder).dy;
      final oldServerTop = tester.getTopLeft(oldServerTextFinder).dy;

      // New server must be above old server
      expect(newServerTop, lessThan(oldServerTop));
    });
  });
}
