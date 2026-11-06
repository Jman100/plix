import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plex_server.dart';
import '../models/plex_library.dart';
import 'plex_auth_service.dart';

class PlexServerService {
  final PlexAuthService authService;
  static const String _prefPinnedServersKey = 'plix_pinned_servers';
  static const String _prefActiveServerIdKey = 'plix_active_server_id';
  static const String _prefSavedJellyfinServersKey = 'plix_saved_jellyfin_servers';
  static const String _prefFavoriteLibrariesKey = 'plix_favorite_library_composite_ids';
  static const String _prefCachedLibrariesPrefix = 'plix_cached_libraries_';
  static const String _prefServerAddedOrderKey = 'plix_server_added_order';

  PlexServerService({required this.authService});

  Future<List<String>> getServerAddedOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefServerAddedOrderKey) ?? [];
  }

  Future<void> recordServersAdded(List<String> serverIds) async {
    if (serverIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefServerAddedOrderKey) ?? [];
    current.removeWhere((id) => serverIds.contains(id));
    current.insertAll(0, serverIds);
    await prefs.setStringList(_prefServerAddedOrderKey, current);
  }

  Future<void> clearAllServers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSavedJellyfinServersKey);
    await prefs.remove(_prefFavoriteLibrariesKey);
    await prefs.remove(_prefPinnedServersKey);
    await prefs.remove(_prefActiveServerIdKey);
    await prefs.remove(_prefServerAddedOrderKey);
  }

  Future<List<PlexServer>> getSavedJellyfinServers() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_prefSavedJellyfinServersKey) ?? [];
    final List<PlexServer> list = [];
    final pinnedIds = await getPinnedServerIds();
    for (final raw in rawList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final server = PlexServer.fromJson(map);
        server.isPinned = pinnedIds.contains(server.clientIdentifier);
        list.add(server);
      } catch (_) {}
    }
    return list;
  }

  Future<void> saveJellyfinServer(PlexServer server) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getSavedJellyfinServers();
    existing.removeWhere((s) => s.clientIdentifier == server.clientIdentifier);
    existing.insert(0, server);
    final rawList = existing.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_prefSavedJellyfinServersKey, rawList);
    await recordServersAdded([server.clientIdentifier]);
  }

  Future<void> removeServer(String clientIdentifier) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getSavedJellyfinServers();
    existing.removeWhere((s) => s.clientIdentifier == clientIdentifier);
    final rawList = existing.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_prefSavedJellyfinServersKey, rawList);
    final order = prefs.getStringList(_prefServerAddedOrderKey) ?? [];
    if (order.contains(clientIdentifier)) {
      order.remove(clientIdentifier);
      await prefs.setStringList(_prefServerAddedOrderKey, order);
    }
  }

  Future<List<PlexServer>> fetchServers(String authToken) async {
    final List<PlexServer> servers = [];
    final pinnedIds = await getPinnedServerIds();

    if (authToken.isNotEmpty) {
      try {
        final clientId = await authService.getClientIdentifier();
        final url = Uri.parse('https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1');
        final response = await http.get(
          url,
          headers: authService.getHeaders(clientId, token: authToken),
        );

        if (response.statusCode == 200) {
          final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
          for (final item in jsonList) {
            final map = item as Map<String, dynamic>;
            final provides = map['provides'] as String? ?? '';
            if (provides.contains('server')) {
              final server = PlexServer.fromJson(map);
              if (server.accessToken.isEmpty) {
                server.accessToken = authToken;
              }
              server.isPinned = pinnedIds.contains(server.clientIdentifier);
              servers.add(server);
            }
          }
        }
      } catch (_) {}
    }

    // Always include any saved Jellyfin servers
    final jfServers = await getSavedJellyfinServers();
    servers.addAll(jfServers);

    return servers;
  }

  static Future<T?> _firstSuccess<T>(List<Future<T?>> futures) {
    if (futures.isEmpty) return Future.value(null);
    final completer = Completer<T?>();
    int remaining = futures.length;
    for (final f in futures) {
      f.then((val) {
        if (val != null && !completer.isCompleted) {
          completer.complete(val);
        } else {
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }
    return completer.future;
  }

  Future<String?> testAndResolveBestConnection(PlexServer server, {bool fallbackToFirstCandidate = false}) async {
    if (server.isJellyfin) {
      final candidates = <String>[];
      if (server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty) {
        candidates.add(server.activeConnectionUri!);
      }
      for (final conn in server.connections) {
        if (conn.uri.isNotEmpty && !candidates.contains(conn.uri)) {
          candidates.add(conn.uri);
        }
      }

      // Quick test for active connection first if present
      if (server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse('${server.activeConnectionUri}/System/Info/Public'))
              .timeout(const Duration(milliseconds: 1200));
          if (res.statusCode == 200) {
            return server.activeConnectionUri;
          }
        } catch (_) {}
      }

      // Test all candidates concurrently for fastest response
      final futures = candidates.map((uri) async {
        try {
          final testUrl = Uri.parse('$uri/System/Info/Public');
          final res = await http.get(testUrl).timeout(const Duration(milliseconds: 1500));
          if (res.statusCode == 200) {
            return uri;
          }
        } catch (_) {}
        return null;
      });

      final working = await _firstSuccess(futures.toList());
      if (working != null) {
        server.activeConnectionUri = working;
        return working;
      }

      if (fallbackToFirstCandidate && candidates.isNotEmpty) {
        server.activeConnectionUri = candidates.first;
        return server.activeConnectionUri;
      }
      server.activeConnectionUri = null;
      return null;
    }

    // Plex Server connection resolution
    // First, test existing activeConnectionUri with short timeout
    final token = server.accessToken.isNotEmpty
        ? server.accessToken
        : (await authService.getSavedToken() ?? '');

    if (server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('${server.activeConnectionUri}/identity'),
          headers: {'Accept': 'application/json', 'X-Plex-Token': token},
        ).timeout(const Duration(milliseconds: 1200));
        if (res.statusCode == 200) {
          return server.activeConnectionUri;
        }
      } catch (_) {}
    }

    final sorted = List<PlexConnection>.from(server.connections);
    sorted.sort((a, b) {
      if (a.local && !b.local) return -1;
      if (!a.local && b.local) return 1;
      if (!a.relay && b.relay) return -1;
      if (a.relay && !b.relay) return 1;
      return 0;
    });

    // Test local connections first concurrently (LAN responds in <100ms)
    final localConns = sorted.where((c) => c.local && c.uri.isNotEmpty).toList();
    if (localConns.isNotEmpty) {
      final localFutures = localConns.map((conn) async {
        try {
          final res = await http.get(
            Uri.parse('${conn.uri}/identity'),
            headers: {'Accept': 'application/json', 'X-Plex-Token': token},
          ).timeout(const Duration(milliseconds: 1000));
          if (res.statusCode == 200) return conn.uri;
        } catch (_) {}
        return null;
      });
      final workingLocal = await _firstSuccess(localFutures.toList());
      if (workingLocal != null) {
        server.activeConnectionUri = workingLocal;
        return workingLocal;
      }
    }

    // Test remote/remaining connections concurrently
    final remoteConns = sorted.where((c) => !c.local && c.uri.isNotEmpty).toList();
    if (remoteConns.isNotEmpty) {
      final remoteFutures = remoteConns.map((conn) async {
        try {
          final res = await http.get(
            Uri.parse('${conn.uri}/identity'),
            headers: {'Accept': 'application/json', 'X-Plex-Token': token},
          ).timeout(const Duration(milliseconds: 1500));
          if (res.statusCode == 200) return conn.uri;
        } catch (_) {}
        return null;
      });
      final workingRemote = await _firstSuccess(remoteFutures.toList());
      if (workingRemote != null) {
        server.activeConnectionUri = workingRemote;
        return workingRemote;
      }
    }

    if (fallbackToFirstCandidate && sorted.isNotEmpty && sorted.first.uri.isNotEmpty) {
      server.activeConnectionUri = sorted.first.uri;
      return server.activeConnectionUri;
    }
    server.activeConnectionUri = null;
    return null;
  }

  Future<Set<String>> getPinnedServerIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefPinnedServersKey) ?? [];
    return list.toSet();
  }

  Future<void> savePinnedServers(Set<String> serverIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefPinnedServersKey, serverIds.toList());
  }

  Future<void> togglePinServer(String serverId, bool pin) async {
    final pinned = await getPinnedServerIds();
    if (pin) {
      pinned.add(serverId);
    } else {
      pinned.remove(serverId);
    }
    await savePinnedServers(pinned);
  }

  Future<String?> getActiveServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefActiveServerIdKey);
  }

  Future<void> setActiveServerId(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveServerIdKey, serverId);
  }

  Future<List<String>?> getFavoriteLibraryIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefFavoriteLibrariesKey);
  }

  Future<void> saveFavoriteLibraryIds(List<String> compositeIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefFavoriteLibrariesKey, compositeIds);
  }

  Future<bool> hasSavedFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefFavoriteLibrariesKey);
  }

  Future<void> cacheServerLibraries(String serverId, List<PlexLibrary> libraries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = libraries.map((lib) => jsonEncode(lib.toJson())).toList();
      await prefs.setStringList('$_prefCachedLibrariesPrefix$serverId', jsonList);
    } catch (_) {}
  }

  Future<List<PlexLibrary>> getCachedServerLibraries(String serverId, PlexServer server) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList('$_prefCachedLibrariesPrefix$serverId') ?? [];
      final List<PlexLibrary> result = [];
      for (final raw in rawList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final lib = PlexLibrary.fromJson(map).copyWith(
            serverId: server.clientIdentifier,
            serverName: server.name,
            isJellyfin: server.isJellyfin,
            server: server,
            isServerOnline: server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty,
          );
          result.add(lib);
        } catch (_) {}
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}
