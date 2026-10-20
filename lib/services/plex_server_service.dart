import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plex_server.dart';
import 'plex_auth_service.dart';

class PlexServerService {
  final PlexAuthService authService;
  static const String _prefPinnedServersKey = 'plix_pinned_servers';
  static const String _prefActiveServerIdKey = 'plix_active_server_id';
  static const String _prefSavedJellyfinServersKey = 'plix_saved_jellyfin_servers';

  PlexServerService({required this.authService});

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
    existing.add(server);
    final rawList = existing.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_prefSavedJellyfinServersKey, rawList);
  }

  Future<void> removeServer(String clientIdentifier) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getSavedJellyfinServers();
    existing.removeWhere((s) => s.clientIdentifier == clientIdentifier);
    final rawList = existing.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_prefSavedJellyfinServersKey, rawList);
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

  Future<String?> testAndResolveBestConnection(PlexServer server) async {
    if (server.isJellyfin) {
      // For Jellyfin, test active URI or configured connection URLs
      final candidates = <String>[];
      if (server.activeConnectionUri != null && server.activeConnectionUri!.isNotEmpty) {
        candidates.add(server.activeConnectionUri!);
      }
      for (final conn in server.connections) {
        if (conn.uri.isNotEmpty && !candidates.contains(conn.uri)) {
          candidates.add(conn.uri);
        }
      }

      for (final uri in candidates) {
        try {
          final testUrl = Uri.parse('$uri/System/Info/Public');
          final res = await http.get(testUrl).timeout(const Duration(milliseconds: 2500));
          if (res.statusCode == 200) {
            server.activeConnectionUri = uri;
            return uri;
          }
        } catch (_) {}
      }

      if (candidates.isNotEmpty) {
        server.activeConnectionUri = candidates.first;
        return server.activeConnectionUri;
      }
      return null;
    }

    // Plex Server connection resolution
    final sorted = List<PlexConnection>.from(server.connections);
    sorted.sort((a, b) {
      if (a.local && !b.local) return -1;
      if (!a.local && b.local) return 1;
      if (!a.relay && b.relay) return -1;
      if (a.relay && !b.relay) return 1;
      return 0;
    });

    final token = server.accessToken.isNotEmpty
        ? server.accessToken
        : (await authService.getSavedToken() ?? '');

    for (final conn in sorted) {
      final uri = conn.uri;
      if (uri.isEmpty) continue;
      final testUrl = Uri.parse('$uri/identity');
      try {
        final res = await http.get(
          testUrl,
          headers: {
            'Accept': 'application/json',
            'X-Plex-Token': token,
          },
        ).timeout(const Duration(milliseconds: 2500));

        if (res.statusCode == 200) {
          server.activeConnectionUri = uri;
          return uri;
        }
      } catch (_) {}
    }

    if (sorted.isNotEmpty && sorted.first.uri.isNotEmpty) {
      server.activeConnectionUri = sorted.first.uri;
      return server.activeConnectionUri;
    }
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
}
