import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../models/seerr_models.dart';
import 'jellyfin_auth_service.dart';
import 'plex_auth_service.dart';
import 'plix_device_helper.dart';
import 'profile_service.dart';
import 'update_service.dart';

class SeerrPagedResult {
  final List<SeerrMediaItem> items;
  final int page;
  final int totalPages;

  const SeerrPagedResult({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;
}

class SeerrResult {
  final bool success;
  final String? message;
  final int? issueId;

  const SeerrResult({required this.success, this.message, this.issueId});

  factory SeerrResult.success({String? message, int? issueId}) =>
      SeerrResult(success: true, message: message, issueId: issueId);

  factory SeerrResult.error(String message) =>
      SeerrResult(success: false, message: message);
}

enum SeerrIssueType {
  video(1, 'Video', 'Playback, stuttering, video corruption'),
  audio(2, 'Audio', 'Out of sync, missing track, distortion'),
  subtitles(3, 'Subtitle', 'Missing subtitles, out of sync, bad format'),
  other(4, 'Other', 'Wrong metadata, wrong episode, other issue');

  final int id;
  final String label;
  final String description;
  const SeerrIssueType(this.id, this.label, this.description);
}

class SeerrService {
  static final SeerrService _instance = SeerrService._internal();
  factory SeerrService() => _instance;
  SeerrService._internal();

  final http.Client _client = http.Client();
  final Map<String, String> _sessionCookies = {};
  final ValueNotifier<bool> requestsEnabledNotifier = ValueNotifier<bool>(false);

  String _cookieKey(String baseUrl) =>
      '${ProfileService.activeProfileId ?? ''}|${normalizeUrl(baseUrl)}';

  Future<bool> isRequestsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(ProfileService.key('enable_media_requests')) ?? false;
    requestsEnabledNotifier.value = enabled;
    return enabled;
  }

  Future<void> setRequestsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileService.key('enable_media_requests'), enabled);
    // Clean up legacy global key so newly created profiles never inherit it
    if (ProfileService.activeProfileId != null &&
        ProfileService.activeProfileId!.isNotEmpty) {
      await prefs.remove('enable_media_requests');
    }
    requestsEnabledNotifier.value = enabled;
  }

  Future<bool> hasAnySeerrUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = ProfileService.key('seerr_url_');
    for (final k in prefs.getKeys()) {
      if (k.startsWith(prefix)) {
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  String normalizeUrl(String input) {
    String url = input.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String _prefKey(String serverId) => ProfileService.key('seerr_url_$serverId');

  Future<String?> getSeerrUrl(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_prefKey(serverId));
    if (val != null && val.trim().isNotEmpty) return normalizeUrl(val);
    return null;
  }

  Future<void> setSeerrUrl(String serverId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeUrl(url);
    final pKey = _prefKey(serverId);
    if (normalized.isEmpty) {
      await prefs.remove(pKey);
    } else {
      await prefs.setString(pKey, normalized);
    }
    // Clean up legacy global key so newly created profiles never inherit it
    if (ProfileService.activeProfileId != null &&
        ProfileService.activeProfileId!.isNotEmpty) {
      await prefs.remove('seerr_url_$serverId');
    }
  }

  Future<void> removeSeerrUrl(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(serverId));
    if (ProfileService.activeProfileId != null &&
        ProfileService.activeProfileId!.isNotEmpty) {
      await prefs.remove('seerr_url_$serverId');
    }
  }

  Future<bool> testConnection(String rawUrl) async {
    final url = normalizeUrl(rawUrl);
    if (url.isEmpty) return false;
    try {
      final res = await _client.get(
        Uri.parse('$url/api/v1/status'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
        },
      ).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[SeerrService] testConnection failed: $e');
      return false;
    }
  }

  final Map<String, Future<bool>> _inFlightAuth = {};

  Future<bool> authenticate({
    required PlexServer server,
    required String seerrUrl,
  }) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return false;

    final cKey = _cookieKey(baseUrl);
    final existing = _inFlightAuth[cKey];
    if (existing != null) return existing;

    final future = () async {
      if (server.isPlex) {
        return _authenticatePlex(server, baseUrl);
      } else if (server.isJellyfin) {
        return _authenticateJellyfin(server, baseUrl);
      }
      return false;
    }();

    _inFlightAuth[cKey] = future;
    try {
      return await future;
    } finally {
      _inFlightAuth.remove(cKey);
    }
  }

  Future<bool> _postPlexAuthToken(String baseUrl, String token) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/plex'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Plix/${UpdateService.currentVersion}',
      },
      body: jsonEncode({'authToken': token}),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final cookie = _extractCookie(res);
      if (cookie != null) {
        _sessionCookies[_cookieKey(baseUrl)] = cookie;
        debugPrint('[SeerrService] Plex authenticated successfully with Seerr');
        return true;
      }
    }
    debugPrint('[SeerrService] Plex auth returned status ${res.statusCode}: ${res.body}');
    return false;
  }

  Future<bool> _authenticatePlex(PlexServer server, String baseUrl) async {
    try {
      // Seerr /api/v1/auth/plex expects the user's plex.tv account token rather than
      // a shared server's resource accessToken; try the saved plex.tv token first.
      final savedToken = (await PlexAuthService().getSavedToken()) ?? '';
      final serverToken = server.accessToken;

      final candidates = <String>[
        if (savedToken.isNotEmpty) savedToken,
        if (serverToken.isNotEmpty && serverToken != savedToken) serverToken,
      ];

      if (candidates.isEmpty) {
        debugPrint('[SeerrService] Plex auth failed: No access token available');
        return false;
      }

      for (final token in candidates) {
        if (await _postPlexAuthToken(baseUrl, token)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[SeerrService] Plex auth error: $e');
      return false;
    }
  }

  Future<bool> _authenticateJellyfin(PlexServer server, String baseUrl) async {
    try {
      // Step 1: Initiate Quick Connect on Seerr
      final initRes = await _client.post(
        Uri.parse('$baseUrl/api/v1/auth/jellyfin/quickconnect/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
        },
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));

      if (initRes.statusCode != 200) {
        debugPrint('[SeerrService] Jellyfin QC initiate failed: ${initRes.statusCode}');
        return false;
      }

      final initData = jsonDecode(initRes.body) as Map<String, dynamic>;
      final code = initData['code']?.toString() ?? '';
      final secret = initData['secret']?.toString() ?? '';

      if (code.isEmpty || secret.isEmpty) {
        debugPrint('[SeerrService] Jellyfin QC initiate returned empty code/secret');
        return false;
      }

      // Step 2: Authorize code on Jellyfin server using user's existing Jellyfin session
      final jfBaseUri = server.activeConnectionUri ??
          (server.connections.isNotEmpty ? server.connections.first.uri : '');
      final jfBase = normalizeUrl(jfBaseUri);
      if (jfBase.isEmpty) {
        debugPrint('[SeerrService] No Jellyfin server URI available to authorize');
        return false;
      }

      final authHeader = JellyfinAuthService.buildAuthHeader(
        clientId: server.clientIdentifier,
        clientName: PlixDeviceHelper.clientName,
        version: UpdateService.currentVersion,
        token: server.accessToken,
      );

      final authRes = await _client.post(
        Uri.parse('$jfBase/QuickConnect/Authorize?code=$code'),
        headers: {
          'Authorization': authHeader,
          'X-Emby-Token': server.accessToken,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
        },
        body: jsonEncode({'code': code}),
      ).timeout(const Duration(seconds: 10));

      if (authRes.statusCode != 200 && authRes.statusCode != 204) {
        debugPrint('[SeerrService] Jellyfin server Authorize returned ${authRes.statusCode}');
        return false;
      }

      // Step 3: Complete authentication on Seerr
      final completeRes = await _client.post(
        Uri.parse('$baseUrl/api/v1/auth/jellyfin/quickconnect/authenticate'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
        },
        body: jsonEncode({'secret': secret}),
      ).timeout(const Duration(seconds: 10));

      if (completeRes.statusCode == 200) {
        final cookie = _extractCookie(completeRes);
        if (cookie != null) {
          _sessionCookies[_cookieKey(baseUrl)] = cookie;
          debugPrint('[SeerrService] Jellyfin QuickConnect authenticated successfully with Seerr');
          return true;
        }
      }
      debugPrint('[SeerrService] Jellyfin QC authenticate returned ${completeRes.statusCode}: ${completeRes.body}');
      return false;
    } catch (e) {
      debugPrint('[SeerrService] Jellyfin QC auth error: $e');
      return false;
    }
  }

  String? _extractCookie(http.Response response) {
    final rawCookie = response.headers['set-cookie'];
    if (rawCookie == null || rawCookie.isEmpty) return null;
    final match = RegExp(r'connect\.sid=[^;,\s]+').firstMatch(rawCookie);
    if (match != null) {
      return match.group(0);
    }
    final parts = rawCookie.split(';');
    return parts.first.trim();
  }

  Future<http.Response?> _getAuthenticated(PlexServer server, String baseUrl, String path) async {
    final cKey = _cookieKey(baseUrl);
    String? cookie = _sessionCookies[cKey];
    if (cookie == null) {
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return null;
      cookie = _sessionCookies[cKey];
    }

    http.Response res = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Plix/${UpdateService.currentVersion}',
        if (cookie != null) 'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 401) {
      _sessionCookies.remove(cKey);
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return res;
      cookie = _sessionCookies[cKey];
      res = await _client.get(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
          if (cookie != null) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 10));
    }
    return res;
  }

  int? _extractTmdbId(PlexMediaItem item, {bool preferGrandparent = false}) {
    final guidsToCheck = <String>[];
    if (preferGrandparent && item.grandparentGuid != null) {
      guidsToCheck.add(item.grandparentGuid!);
    }
    guidsToCheck.addAll(item.guids);
    if (item.guid != null) guidsToCheck.add(item.guid!);

    for (final g in guidsToCheck) {
      final match = RegExp(r'tmdb://(\d+)').firstMatch(g);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  Future<int?> resolveMediaId({
    required PlexServer server,
    required PlexMediaItem item,
    required String seerrUrl,
  }) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return null;

    final isTv = item.isEpisode || item.isShow;

    // 1. Direct TMDb ID lookup if available
    final tmdbId = _extractTmdbId(item, preferGrandparent: isTv);
    if (tmdbId != null) {
      try {
        final path = isTv ? '/api/v1/tv/$tmdbId' : '/api/v1/movie/$tmdbId';
        final res = await _getAuthenticated(server, baseUrl, path);
        if (res != null && res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final mediaInfo = data['mediaInfo'] as Map<String, dynamic>?;
          final mId = mediaInfo?['id'] as int?;
          if (mId != null) return mId;
        }
      } catch (e) {
        debugPrint('[SeerrService] Direct TMDb lookup error: $e');
      }
    }

    // 2. Search Seerr by title
    final queryTitle = (item.isEpisode && item.grandparentTitle != null && item.grandparentTitle!.isNotEmpty)
        ? item.grandparentTitle!
        : item.title;

    if (queryTitle.isNotEmpty) {
      try {
        final searchRes = await _getAuthenticated(
          server,
          baseUrl,
          '/api/v1/search?query=${Uri.encodeComponent(queryTitle)}',
        );
        if (searchRes != null && searchRes.statusCode == 200) {
          final sData = jsonDecode(searchRes.body) as Map<String, dynamic>;
          final results = sData['results'] as List<dynamic>? ?? [];
          final targetType = isTv ? 'tv' : 'movie';
          for (final r in results) {
            if (r is Map<String, dynamic>) {
              if (r['mediaType'] == targetType) {
                final mediaInfo = r['mediaInfo'] as Map<String, dynamic>?;
                final mId = mediaInfo?['id'] as int?;
                if (mId != null) return mId;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[SeerrService] Search lookup error: $e');
      }

      // 3. Media list lookup
      try {
        final mediaRes = await _getAuthenticated(
          server,
          baseUrl,
          '/api/v1/media?take=10&search=${Uri.encodeComponent(queryTitle)}',
        );
        if (mediaRes != null && mediaRes.statusCode == 200) {
          final mData = jsonDecode(mediaRes.body) as Map<String, dynamic>;
          final results = mData['results'] as List<dynamic>? ?? [];
          final targetType = isTv ? 'tv' : 'movie';
          for (final r in results) {
            if (r is Map<String, dynamic>) {
              if (r['mediaType'] == targetType) {
                final id = r['id'] as int?;
                if (id != null) return id;
              }
            }
          }
          if (results.isNotEmpty && results.first is Map<String, dynamic>) {
            return results.first['id'] as int?;
          }
        }
      } catch (e) {
        debugPrint('[SeerrService] Media list lookup error: $e');
      }
    }

    return null;
  }

  Future<SeerrResult> submitIssue({
    required PlexServer server,
    required PlexMediaItem item,
    required int issueType,
    required String message,
  }) async {
    final seerrUrl = await getSeerrUrl(server.clientIdentifier);
    if (seerrUrl == null || seerrUrl.isEmpty) {
      return SeerrResult.error('No Seerr URL configured for ${server.name}.');
    }

    final mediaId = await resolveMediaId(server: server, item: item, seerrUrl: seerrUrl);
    if (mediaId == null) {
      return SeerrResult.error(
        'Could not match "${item.title}" in Seerr. Please ensure this title is indexed in Seerr.',
      );
    }

    String formattedMessage = message.trim();
    if (item.isEpisode) {
      final s = item.parentIndex ?? 1;
      final e = item.index ?? 1;
      final epTag = '[S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')} - ${item.title}]';
      formattedMessage = formattedMessage.isNotEmpty ? '$epTag $formattedMessage' : epTag;
    }

    final payload = <String, dynamic>{
      'mediaId': mediaId,
      'issueType': issueType,
      'message': formattedMessage.isNotEmpty ? formattedMessage : 'Issue reported via Plix',
    };

    if (item.isEpisode) {
      if (item.parentIndex != null && item.parentIndex! > 0) {
        payload['problemSeason'] = item.parentIndex;
      }
      if (item.index != null && item.index! > 0) {
        payload['problemEpisode'] = item.index;
      }
    }

    try {
      final cKey = _cookieKey(seerrUrl);
      String? cookie = _sessionCookies[cKey];
      if (cookie == null) {
        final ok = await authenticate(server: server, seerrUrl: seerrUrl);
        if (!ok) {
          return SeerrResult.error('Failed to authenticate with Seerr.');
        }
        cookie = _sessionCookies[cKey];
      }

      http.Response res = await _client.post(
        Uri.parse('$seerrUrl/api/v1/issue'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
          if (cookie != null) 'Cookie': cookie,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 401) {
        _sessionCookies.remove(cKey);
        final ok = await authenticate(server: server, seerrUrl: seerrUrl);
        if (ok) {
          cookie = _sessionCookies[cKey];
          res = await _client.post(
            Uri.parse('$seerrUrl/api/v1/issue'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Plix/${UpdateService.currentVersion}',
              if (cookie != null) 'Cookie': cookie,
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 15));
        }
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final id = data['id'] as int?;
        return SeerrResult.success(
          message: 'Issue reported successfully!',
          issueId: id,
        );
      } else {
        String errMsg = 'Failed to submit issue (HTTP ${res.statusCode})';
        try {
          final errJson = jsonDecode(res.body);
          if (errJson is Map && errJson['message'] != null) {
            errMsg = errJson['message'].toString();
          }
        } catch (_) {}
        return SeerrResult.error(errMsg);
      }
    } catch (e) {
      return SeerrResult.error('Error submitting issue: $e');
    }
  }

  Future<http.Response?> _postAuthenticated(
    PlexServer server,
    String baseUrl,
    String path,
    Map<String, dynamic> body,
  ) async {
    final cKey = _cookieKey(baseUrl);
    String? cookie = _sessionCookies[cKey];
    if (cookie == null) {
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return null;
      cookie = _sessionCookies[cKey];
    }

    http.Response res = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Plix/${UpdateService.currentVersion}',
        if (cookie != null) 'Cookie': cookie,
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) {
      _sessionCookies.remove(cKey);
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return res;
      cookie = _sessionCookies[cKey];
      res = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Plix/${UpdateService.currentVersion}',
          if (cookie != null) 'Cookie': cookie,
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
    }
    return res;
  }

  Future<SeerrPagedResult> getTrendingPage(
    PlexServer server,
    String seerrUrl, {
    int page = 1,
  }) async {
    return _fetchDiscoverPage(server, seerrUrl, '/api/v1/discover/trending?page=$page', page, 'getTrendingPage');
  }

  Future<List<SeerrMediaItem>> getTrending(PlexServer server, String seerrUrl) async {
    final res = await getTrendingPage(server, seerrUrl, page: 1);
    return res.items;
  }

  Future<SeerrPagedResult> getUpcomingMoviesPage(
    PlexServer server,
    String seerrUrl, {
    int page = 1,
  }) async {
    return _fetchDiscoverPage(server, seerrUrl, '/api/v1/discover/movies/upcoming?page=$page', page, 'getUpcomingMoviesPage');
  }

  Future<List<SeerrMediaItem>> getUpcomingMovies(PlexServer server, String seerrUrl) async {
    final res = await getUpcomingMoviesPage(server, seerrUrl, page: 1);
    return res.items;
  }

  Future<SeerrPagedResult> getUpcomingTvPage(
    PlexServer server,
    String seerrUrl, {
    int page = 1,
  }) async {
    return _fetchDiscoverPage(server, seerrUrl, '/api/v1/discover/tv/upcoming?page=$page', page, 'getUpcomingTvPage');
  }

  Future<List<SeerrMediaItem>> getUpcomingTv(PlexServer server, String seerrUrl) async {
    final res = await getUpcomingTvPage(server, seerrUrl, page: 1);
    return res.items;
  }

  Future<SeerrPagedResult> _fetchDiscoverPage(
    PlexServer server,
    String seerrUrl,
    String path,
    int page,
    String logTag,
  ) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return SeerrPagedResult(items: const [], page: page, totalPages: 1);
    try {
      final res = await _getAuthenticated(server, baseUrl, path);
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        final totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        final currentPage = (data['page'] as num?)?.toInt() ?? page;
        final items = results
            .whereType<Map<String, dynamic>>()
            .map((e) => SeerrMediaItem.fromJson(e))
            .where((item) => item.id > 0)
            .toList();
        return SeerrPagedResult(items: items, page: currentPage, totalPages: totalPages);
      }
    } catch (e) {
      debugPrint('[SeerrService] $logTag error: $e');
    }
    return SeerrPagedResult(items: const [], page: page, totalPages: page);
  }

  Future<int?> getCurrentUserId(PlexServer server, String seerrUrl) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return null;
    try {
      final res = await _getAuthenticated(server, baseUrl, '/api/v1/auth/me');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final id = data['id'] as int?;
        debugPrint('[SeerrService] Authenticated Seerr user ID: $id');
        return id;
      }
    } catch (e) {
      debugPrint('[SeerrService] getCurrentUserId error: $e');
    }
    return null;
  }

  Future<SeerrPagedResult> getRecentRequestsPage(
    PlexServer server,
    String seerrUrl, {
    int page = 1,
    int take = 24,
  }) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return SeerrPagedResult(items: const [], page: page, totalPages: 1);
    final skip = (page - 1) * take;
    try {
      // 1. Get logged in user's ID to filter requests created by this user
      final currentUserId = await getCurrentUserId(server, baseUrl);

      http.Response? res;
      if (currentUserId != null) {
        // Try user-specific requests endpoint first
        res = await _getAuthenticated(
          server,
          baseUrl,
          '/api/v1/user/$currentUserId/requests?take=$take&skip=$skip&sort=added',
        );
      }

      if (res == null || res.statusCode != 200) {
        // Fallback to /api/v1/request
        final path = currentUserId != null
            ? '/api/v1/request?take=$take&skip=$skip&filter=all&sort=added&requestedBy=$currentUserId'
            : '/api/v1/request?take=$take&skip=$skip&filter=all&sort=added';
        res = await _getAuthenticated(server, baseUrl, path);
      }

      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final pageInfo = data['pageInfo'] as Map<String, dynamic>?;
        final totalPages = (pageInfo?['pages'] as num?)?.toInt() ?? 1;
        final results = data['results'] as List<dynamic>? ?? [];
        final items = <SeerrMediaItem>[];
        for (final r in results) {
          if (r is Map<String, dynamic>) {
            // Strictly enforce current user filter so admin accounts don't see everyone's requests
            if (currentUserId != null) {
              final reqBy = r['requestedBy'] as Map<String, dynamic>?;
              final reqById = reqBy?['id'] as int?;
              if (reqById != null && reqById != currentUserId) {
                continue;
              }
            }

            final item = SeerrMediaItem.fromJson(r);
            if (item.id > 0) {
              items.add(item);
            }
          }
        }
        // Enrich any items missing titles or posters
        final enriched = await Future.wait(items.map((it) async {
          if (it.title.isNotEmpty && it.posterPath != null && it.posterPath!.isNotEmpty) {
            return it;
          }
          final details = await getMediaDetails(server, baseUrl, it.mediaType, it.id);
          if (details != null) {
            return it.copyWith(
              title: it.title.isNotEmpty ? it.title : details.title,
              posterPath: it.posterPath ?? details.posterPath,
              backdropPath: it.backdropPath ?? details.backdropPath,
              overview: it.overview ?? details.overview,
              releaseDate: it.releaseDate ?? details.releaseDate,
            );
          }
          return it;
        }));
        return SeerrPagedResult(items: enriched, page: page, totalPages: totalPages);
      }
    } catch (e) {
      debugPrint('[SeerrService] getRecentRequestsPage error: $e');
    }
    return SeerrPagedResult(items: const [], page: page, totalPages: page);
  }

  Future<List<SeerrMediaItem>> getRecentRequests(PlexServer server, String seerrUrl) async {
    final res = await getRecentRequestsPage(server, seerrUrl, page: 1, take: 20);
    return res.items;
  }

  Future<List<SeerrMediaItem>> searchSeerr(PlexServer server, String seerrUrl, String query) async {
    final baseUrl = normalizeUrl(seerrUrl);
    final q = query.trim();
    if (baseUrl.isEmpty || q.isEmpty) return [];
    try {
      final res = await _getAuthenticated(
        server,
        baseUrl,
        '/api/v1/search?query=${Uri.encodeComponent(q)}&page=1',
      );
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        return results
            .whereType<Map<String, dynamic>>()
            .map((e) => SeerrMediaItem.fromJson(e))
            .where((item) => (item.isMovie || item.isTv) && item.id > 0)
            .toList();
      }
    } catch (e) {
      debugPrint('[SeerrService] searchSeerr error: $e');
    }
    return [];
  }

  Future<SeerrMediaDetails?> getMediaDetails(
    PlexServer server,
    String seerrUrl,
    String mediaType,
    int tmdbId,
  ) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty || tmdbId <= 0) return null;
    final type = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
    try {
      final res = await _getAuthenticated(server, baseUrl, '/api/v1/$type/$tmdbId');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return SeerrMediaDetails.fromJson(data, type);
      }
    } catch (e) {
      debugPrint('[SeerrService] getMediaDetails error: $e');
    }
    return null;
  }

  Future<SeerrResult> submitRequest(
    PlexServer server,
    String seerrUrl, {
    required String mediaType,
    required int mediaId,
    bool is4k = false,
    List<int>? seasons,
  }) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) {
      return SeerrResult.error('No Seerr URL configured for ${server.name}.');
    }

    final isTv = mediaType.toLowerCase() == 'tv';
    final payload = <String, dynamic>{
      'mediaType': isTv ? 'tv' : 'movie',
      'mediaId': mediaId,
      'is4k': is4k,
    };
    if (isTv) {
      if (seasons != null && seasons.isNotEmpty) {
        payload['seasons'] = seasons;
      } else {
        payload['seasons'] = 'all';
      }
    }

    try {
      final res = await _postAuthenticated(server, baseUrl, '/api/v1/request', payload);
      if (res == null) {
        return SeerrResult.error('Failed to authenticate with Seerr.');
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final id = data['id'] as int?;
        return SeerrResult.success(
          message: 'Request submitted successfully!',
          issueId: id,
        );
      } else {
        String errMsg = 'Failed to submit request (HTTP ${res.statusCode})';
        try {
          final errJson = jsonDecode(res.body);
          if (errJson is Map && errJson['message'] != null) {
            errMsg = errJson['message'].toString();
          }
        } catch (_) {}
        return SeerrResult.error(errMsg);
      }
    } catch (e) {
      return SeerrResult.error('Error submitting request: $e');
    }
  }

  static const String _trailerCacheKey = 'seerr_trailer_cache_v2';
  static const int _trailerCacheTtlMs = 14 * 24 * 60 * 60 * 1000; // 14 days
  static final Map<int, String> _memoryTrailerCache = {};

  bool _looksLikeShort(String? titleOrName, String? url) {
    final lowerUrl = (url ?? '').toLowerCase();
    if (lowerUrl.contains('/shorts/')) return true;
    final lowerName = (titleOrName ?? '').toLowerCase();
    return lowerName.contains('#short') ||
        lowerName.contains('youtube short') ||
        lowerName.contains('vertical trailer') ||
        lowerName.contains('vertical teaser');
  }

  /// Checks YouTube oEmbed metadata to verify the video is landscape (width >= height)
  /// and not a YouTube Short. Returns `true` if landscape or if check is inconclusive.
  Future<bool> _isLandscapeYoutubeVideo(String videoKey) async {
    try {
      final oembedUrl = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoKey&format=json',
      );
      final res = await http
          .get(oembedUrl, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          final width = (data['width'] as num?)?.toDouble();
          final height = (data['height'] as num?)?.toDouble();
          final title = data['title']?.toString() ?? '';
          if (_looksLikeShort(title, null)) return false;
          if (width != null && height != null && height > width) {
            return false; // Portrait / YouTube Short
          }
          return true;
        }
      }
    } catch (_) {}
    return true;
  }

  /// Resolves a full-size landscape YouTube trailer key for [tmdbId] using:
  /// 1. Local cache (14-day TTL)
  /// 2. TMDB/Seerr [relatedVideos] (preferring official landscape YouTube trailers)
  /// 3. Curated fallback via KinoCheck API
  Future<String?> resolveYoutubeTrailerKey(
    int tmdbId, {
    List<SeerrVideo> relatedVideos = const [],
  }) async {
    if (tmdbId <= 0) return null;

    if (_memoryTrailerCache.containsKey(tmdbId)) {
      return _memoryTrailerCache[tmdbId];
    }

    // 1. Check persisted SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_trailerCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final entry = decoded[tmdbId.toString()];
        if (entry is Map) {
          final key = entry['key']?.toString();
          final ts = entry['ts'] as int? ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (key != null && key.isNotEmpty && (now - ts) < _trailerCacheTtlMs) {
            _memoryTrailerCache[tmdbId] = key;
            return key;
          }
        }
      }
    } catch (_) {}

    // 2. Build prioritized list of candidate YouTube keys (excluding obvious Shorts)
    final candidates = <String>[];
    void addCandidate(String? k) {
      if (k != null && k.isNotEmpty && !candidates.contains(k)) {
        candidates.add(k);
      }
    }

    // Tier A: Official TMDB Trailers
    for (final v in relatedVideos) {
      if (v.isYouTube &&
          (v.type?.toLowerCase() == 'trailer') &&
          v.official &&
          !_looksLikeShort(v.name, v.url)) {
        addCandidate(v.youtubeKey);
      }
    }
    // Tier B: Any TMDB Trailers
    for (final v in relatedVideos) {
      if (v.isYouTube &&
          (v.type?.toLowerCase() == 'trailer') &&
          !_looksLikeShort(v.name, v.url)) {
        addCandidate(v.youtubeKey);
      }
    }
    // Tier C: Official TMDB Teasers / Clips
    for (final v in relatedVideos) {
      if (v.isYouTube && v.isTrailer && v.official && !_looksLikeShort(v.name, v.url)) {
        addCandidate(v.youtubeKey);
      }
    }
    // Tier D: KinoCheck curated trailers (1080p/4K landscape)
    final kinoKeys = await _fetchKinoCheckTrailerKeys(tmdbId);
    for (final k in kinoKeys) {
      addCandidate(k);
    }
    // Tier E: Any remaining YouTube videos from TMDB
    for (final v in relatedVideos) {
      if (v.isYouTube && !_looksLikeShort(v.name, v.url)) {
        addCandidate(v.youtubeKey);
      }
    }

    // 3. Pick the first candidate verified to be landscape (not a YouTube Short)
    String? resolvedKey;
    for (final key in candidates) {
      if (await _isLandscapeYoutubeVideo(key)) {
        resolvedKey = key;
        break;
      }
    }
    resolvedKey ??= candidates.firstOrNull;

    if (resolvedKey != null && resolvedKey.isNotEmpty) {
      _memoryTrailerCache[tmdbId] = resolvedKey;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_trailerCacheKey);
        final Map<String, dynamic> map = (raw != null && raw.isNotEmpty)
            ? (jsonDecode(raw) as Map<String, dynamic>)
            : {};
        map[tmdbId.toString()] = {
          'key': resolvedKey,
          'ts': DateTime.now().millisecondsSinceEpoch,
        };
        if (map.length > 200) {
          final oldestKey = map.keys.first;
          map.remove(oldestKey);
        }
        await prefs.setString(_trailerCacheKey, jsonEncode(map));
      } catch (_) {}
    }

    return resolvedKey;
  }

  Future<List<String>> _fetchKinoCheckTrailerKeys(int tmdbId) async {
    final keys = <String>[];
    final urls = [
      'https://api.kinocheck.com/movies?tmdb_id=$tmdbId&language=en&categories=Trailer',
      'https://api.kinocheck.com/movies?tmdb_id=$tmdbId',
    ];
    for (final url in urls) {
      try {
        final res = await http
            .get(Uri.parse(url), headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic>) {
            final trailer = data['trailer'];
            if (trailer is Map && trailer['youtube_video_id'] != null) {
              final ytId = trailer['youtube_video_id'].toString();
              final title = trailer['title']?.toString();
              if (ytId.isNotEmpty && !_looksLikeShort(title, null) && !keys.contains(ytId)) {
                keys.add(ytId);
              }
            }
            final videos = data['videos'];
            if (videos is List) {
              for (final v in videos) {
                if (v is Map && v['youtube_video_id'] != null) {
                  final ytId = v['youtube_video_id'].toString();
                  final title = v['title']?.toString();
                  if (ytId.isNotEmpty && !_looksLikeShort(title, null) && !keys.contains(ytId)) {
                    keys.add(ytId);
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[SeerrService] KinoCheck lookup failed ($url): $e');
      }
      if (keys.isNotEmpty) break;
    }
    return keys;
  }
}
