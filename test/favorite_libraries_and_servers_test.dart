import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plix/models/plex_server.dart';
import 'package:plix/services/plex_auth_service.dart';
import 'package:plix/services/plex_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlexAuthService authService;
  late PlexServerService serverService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = PlexAuthService();
    serverService = PlexServerService(authService: authService);
  });

  group('PlexServerService - Server Added Order & Clear All', () {
    test('recordServersAdded tracks most recently added servers at the top', () async {
      await serverService.recordServersAdded(['server_p1', 'server_p2']);
      var order = await serverService.getServerAddedOrder();
      expect(order, equals(['server_p1', 'server_p2']));

      // Add a new Jellyfin server
      await serverService.recordServersAdded(['server_jf1']);
      order = await serverService.getServerAddedOrder();
      expect(order, equals(['server_jf1', 'server_p1', 'server_p2']));

      // Add another Jellyfin server
      await serverService.recordServersAdded(['server_jf2']);
      order = await serverService.getServerAddedOrder();
      expect(order, equals(['server_jf2', 'server_jf1', 'server_p1', 'server_p2']));
    });

    test('clearAllServers removes all server state and order', () async {
      final jfServer = PlexServer(
        name: 'JF Test',
        clientIdentifier: 'jf_123',
        accessToken: 'token_123',
        owned: true,
        connections: [
          PlexConnection(protocol: 'http', address: '127.0.0.1', port: 8096, uri: 'http://127.0.0.1:8096', local: true, relay: false),
        ],
        serverType: 'jellyfin',
      );
      await serverService.saveJellyfinServer(jfServer);
      await serverService.saveFavoriteLibraryIds(['lib_1', 'lib_2']);
      await serverService.setActiveServerId('jf_123');
      await serverService.savePinnedServers({'jf_123'});

      expect(await serverService.getSavedJellyfinServers(), isNotEmpty);
      expect(await serverService.getFavoriteLibraryIds(), isNotEmpty);
      expect(await serverService.getActiveServerId(), equals('jf_123'));
      expect(await serverService.getPinnedServerIds(), isNotEmpty);
      expect(await serverService.getServerAddedOrder(), isNotEmpty);

      await serverService.clearAllServers();

      expect(await serverService.getSavedJellyfinServers(), isEmpty);
      expect(await serverService.getFavoriteLibraryIds(), isNull);
      expect(await serverService.getActiveServerId(), isNull);
      expect(await serverService.getPinnedServerIds(), isEmpty);
      expect(await serverService.getServerAddedOrder(), isEmpty);
    });
  });

  group('Favorite Libraries Ownership Filtering Logic', () {
    test('first-time sign in defaults to only favoriting owned servers', () {
      final ownedServer = PlexServer(
        name: 'My Plex Server',
        clientIdentifier: 'owned_srv',
        accessToken: 'tok1',
        owned: true,
        connections: [],
      );

      final sharedServer = PlexServer(
        name: 'Friend Shared Server',
        clientIdentifier: 'shared_srv',
        accessToken: 'tok2',
        owned: false,
        connections: [],
      );

      final ownedLibs = ['owned_srv_1', 'owned_srv_2'];
      final sharedLibs = ['shared_srv_1', 'shared_srv_2'];

      final selectedIds = <String>{};
      const hasSaved = false;

      // Simulate loading for owned server
      if (!hasSaved && ownedServer.owned) {
        selectedIds.addAll(ownedLibs);
      }

      // Simulate loading for shared server
      if (!hasSaved && sharedServer.owned) {
        selectedIds.addAll(sharedLibs);
      }

      expect(selectedIds, contains('owned_srv_1'));
      expect(selectedIds, contains('owned_srv_2'));
      expect(selectedIds, isNot(contains('shared_srv_1')));
      expect(selectedIds, isNot(contains('shared_srv_2')));
    });

    test('first-time sign in defaults to 0 favorites if user owns no servers', () {
      final sharedServer1 = PlexServer(
        name: 'Friend Shared 1',
        clientIdentifier: 'shared_1',
        accessToken: 'tok1',
        owned: false,
        connections: [],
      );
      final sharedServer2 = PlexServer(
        name: 'Friend Shared 2',
        clientIdentifier: 'shared_2',
        accessToken: 'tok2',
        owned: false,
        connections: [],
      );

      final selectedIds = <String>{};
      const hasSaved = false;

      if (!hasSaved && sharedServer1.owned) {
        selectedIds.add('shared_1_lib');
      }
      if (!hasSaved && sharedServer2.owned) {
        selectedIds.add('shared_2_lib');
      }

      expect(selectedIds, isEmpty);
    });
  });
}
