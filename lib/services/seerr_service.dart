import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import 'jellyfin_auth_service.dart';
import 'plex_auth_service.dart';
import 'plix_device_helper.dart';
import 'profile_service.dart';
import 'update_service.dart';

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
  subtitles(3, 'Subtitles', 'Missing subtitles, out of sync, bad format'),
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
    // 1. Profile-scoped key
    final pKey = _prefKey(serverId);
    final val = prefs.getString(pKey);
    if (val != null && val.trim().isNotEmpty) return normalizeUrl(val);

    // 2. Global fallback
    final globalKey = 'seerr_url_$serverId';
    final globalVal = prefs.getString(globalKey);
    if (globalVal != null && globalVal.trim().isNotEmpty) return normalizeUrl(globalVal);

    // 3. Alternative naming fallback
    final legacyKey = 'seerr_server_url_$serverId';
    final legacyVal = prefs.getString(legacyKey);
    if (legacyVal != null && legacyVal.trim().isNotEmpty) return normalizeUrl(legacyVal);

    return null;
  }

  Future<void> setSeerrUrl(String serverId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeUrl(url);
    final pKey = _prefKey(serverId);
    if (normalized.isEmpty) {
      await prefs.remove(pKey);
      await prefs.remove('seerr_url_$serverId');
    } else {
      await prefs.setString(pKey, normalized);
      await prefs.setString('seerr_url_$serverId', normalized);
    }
  }

  Future<void> removeSeerrUrl(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(serverId));
    await prefs.remove('seerr_url_$serverId');
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

  Future<bool> authenticate({
    required PlexServer server,
    required String seerrUrl,
  }) async {
    final baseUrl = normalizeUrl(seerrUrl);
    if (baseUrl.isEmpty) return false;

    if (server.isPlex) {
      return _authenticatePlex(server, baseUrl);
    } else if (server.isJellyfin) {
      return _authenticateJellyfin(server, baseUrl);
    }
    return false;
  }

  Future<bool> _authenticatePlex(PlexServer server, String baseUrl) async {
    try {
      String token = server.accessToken;
      if (token.isEmpty) {
        token = (await PlexAuthService().getSavedToken()) ?? '';
      }
      if (token.isEmpty) {
        debugPrint('[SeerrService] Plex auth failed: No access token available');
        return false;
      }

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
          _sessionCookies[baseUrl] = cookie;
          debugPrint('[SeerrService] Plex authenticated successfully with Seerr');
          return true;
        }
      }
      debugPrint('[SeerrService] Plex auth returned status ${res.statusCode}: ${res.body}');
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
          _sessionCookies[baseUrl] = cookie;
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
    final parts = rawCookie.split(';');
    for (final p in parts) {
      final trimmed = p.trim();
      if (trimmed.startsWith('connect.sid=')) {
        return trimmed;
      }
    }
    return parts.first.trim();
  }

  Future<http.Response?> _getAuthenticated(PlexServer server, String baseUrl, String path) async {
    String? cookie = _sessionCookies[baseUrl];
    if (cookie == null) {
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return null;
      cookie = _sessionCookies[baseUrl];
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
      _sessionCookies.remove(baseUrl);
      final ok = await authenticate(server: server, seerrUrl: baseUrl);
      if (!ok) return res;
      cookie = _sessionCookies[baseUrl];
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
      String? cookie = _sessionCookies[seerrUrl];
      if (cookie == null) {
        final ok = await authenticate(server: server, seerrUrl: seerrUrl);
        if (!ok) {
          return SeerrResult.error('Failed to authenticate with Seerr.');
        }
        cookie = _sessionCookies[seerrUrl];
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
        _sessionCookies.remove(seerrUrl);
        final ok = await authenticate(server: server, seerrUrl: seerrUrl);
        if (ok) {
          cookie = _sessionCookies[seerrUrl];
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
}
