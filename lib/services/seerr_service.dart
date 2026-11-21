import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'plex_auth_service.dart';
import 'profile_service.dart';

enum SeerrMediaStatus {
  none,
  unknown,
  pending,
  processing,
  partiallyAvailable,
  available,
  deleted;

  static SeerrMediaStatus fromCode(int? code) {
    switch (code) {
      case 1:
        return SeerrMediaStatus.unknown;
      case 2:
        return SeerrMediaStatus.pending;
      case 3:
        return SeerrMediaStatus.processing;
      case 4:
        return SeerrMediaStatus.partiallyAvailable;
      case 5:
        return SeerrMediaStatus.available;
      case 6:
        return SeerrMediaStatus.deleted;
      default:
        return SeerrMediaStatus.none;
    }
  }

  String get label {
    switch (this) {
      case SeerrMediaStatus.pending:
        return 'Requested';
      case SeerrMediaStatus.processing:
        return 'Processing';
      case SeerrMediaStatus.partiallyAvailable:
        return 'Partially Available';
      case SeerrMediaStatus.available:
        return 'Available';
      case SeerrMediaStatus.none:
      case SeerrMediaStatus.unknown:
      case SeerrMediaStatus.deleted:
        return 'Not Requested';
    }
  }

  bool get canRequest =>
      this == SeerrMediaStatus.none ||
      this == SeerrMediaStatus.unknown ||
      this == SeerrMediaStatus.deleted ||
      this == SeerrMediaStatus.partiallyAvailable;
}

enum SeerrAuthMode {
  plex,
  jellyfin,
  local;

  static SeerrAuthMode? fromKey(String? key) {
    for (final m in SeerrAuthMode.values) {
      if (m.name == key) return m;
    }
    return null;
  }

  String get label {
    switch (this) {
      case SeerrAuthMode.plex:
        return 'Plex';
      case SeerrAuthMode.jellyfin:
        return 'Jellyfin';
      case SeerrAuthMode.local:
        return 'Seerr Account';
    }
  }
}

class SeerrServerOption {
  final String id;
  final String name;
  final String url;
  final SeerrAuthMode serverType;

  const SeerrServerOption({
    required this.id,
    required this.name,
    required this.url,
    required this.serverType,
  });

  String get host => Uri.tryParse(url)?.host ?? url;
}

class SeerrSearchResult {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final SeerrMediaStatus status;

  const SeerrSearchResult({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.status = SeerrMediaStatus.none,
  });

  bool get isMovie => mediaType == 'movie';
  bool get isTv => mediaType == 'tv';

  String? get posterUrl =>
      (posterPath != null && posterPath!.isNotEmpty) ? 'https://image.tmdb.org/t/p/w342$posterPath' : null;

  String? get backdropUrl =>
      (backdropPath != null && backdropPath!.isNotEmpty) ? 'https://image.tmdb.org/t/p/w780$backdropPath' : null;

  SeerrSearchResult copyWith({SeerrMediaStatus? status}) {
    return SeerrSearchResult(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      voteAverage: voteAverage,
      status: status ?? this.status,
    );
  }

  static SeerrSearchResult? fromJson(Map<String, dynamic> json) {
    final type = json['mediaType']?.toString();
    if (type != 'movie' && type != 'tv') return null;
    final id = json['id'];
    if (id is! int) return null;
    final title = (type == 'movie' ? json['title'] : json['name'])?.toString() ??
        json['originalTitle']?.toString() ??
        json['originalName']?.toString() ??
        '';
    final date = (type == 'movie' ? json['releaseDate'] : json['firstAirDate'])?.toString() ?? '';
    final mediaInfo = json['mediaInfo'];
    final statusCode = mediaInfo is Map ? mediaInfo['status'] : null;
    return SeerrSearchResult(
      tmdbId: id,
      mediaType: type!,
      title: title,
      year: date.length >= 4 ? date.substring(0, 4) : null,
      overview: json['overview']?.toString(),
      posterPath: json['posterPath']?.toString(),
      backdropPath: json['backdropPath']?.toString(),
      voteAverage: (json['voteAverage'] is num) ? (json['voteAverage'] as num).toDouble() : null,
      status: SeerrMediaStatus.fromCode(statusCode is int ? statusCode : null),
    );
  }
}

class SeerrSeason {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final SeerrMediaStatus status;

  const SeerrSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.status = SeerrMediaStatus.none,
  });
}

class SeerrException implements Exception {
  final String message;
  const SeerrException(this.message);

  @override
  String toString() => message;
}

class SeerrService extends ChangeNotifier {
  static final SeerrService instance = SeerrService._internal();
  SeerrService._internal();

  static const List<SeerrServerOption> servers = [
    SeerrServerOption(
      id: 'plex1',
      name: 'Plex Server 1',
      url: 'https://plex.jman100.com',
      serverType: SeerrAuthMode.plex,
    ),
    SeerrServerOption(
      id: 'plex2',
      name: 'Plex Server 2',
      url: 'https://plex2.jman100.com',
      serverType: SeerrAuthMode.plex,
    ),
    SeerrServerOption(
      id: 'jellyfin',
      name: 'Jellyfin',
      url: 'https://requests.jman100.com',
      serverType: SeerrAuthMode.jellyfin,
    ),
  ];

  static SeerrServerOption? serverById(String? id) {
    for (final s in servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  static const String _serverKey = 'seerr_server_id';
  static const String _modeKey = 'seerr_auth_mode';
  static const String _cookieKey = 'seerr_session_cookie';
  static const String _userKey = 'seerr_user_name';
  static const Duration _timeout = Duration(seconds: 15);

  SeerrServerOption? _server;
  SeerrAuthMode? _authMode;
  String _sessionCookie = '';
  String _userName = '';
  String? _loadedProfileKey;

  SeerrServerOption? get server => _server;
  String get baseUrl => _server?.url ?? '';
  SeerrAuthMode? get authMode => _authMode;
  String get userName => _userName;

  bool get isConfigured {
    if (baseUrl.isEmpty || _authMode == null) return false;
    return _sessionCookie.isNotEmpty;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loadedProfileKey = ProfileService.key(_modeKey);
      _server = serverById(prefs.getString(ProfileService.key(_serverKey)));
      _authMode = SeerrAuthMode.fromKey(prefs.getString(ProfileService.key(_modeKey)));
      _sessionCookie = prefs.getString(ProfileService.key(_cookieKey)) ?? '';
      _userName = prefs.getString(ProfileService.key(_userKey)) ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('[SeerrService] Error loading settings: $e');
    }
  }

  Future<void> ensureLoaded() async {
    if (_loadedProfileKey != ProfileService.key(_modeKey)) await init();
  }

  Future<bool> hasPlexAccount() async {
    try {
      final token = await PlexAuthService().getSavedToken();
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_server == null) {
      await prefs.remove(ProfileService.key(_serverKey));
    } else {
      await prefs.setString(ProfileService.key(_serverKey), _server!.id);
    }
    if (_authMode == null) {
      await prefs.remove(ProfileService.key(_modeKey));
    } else {
      await prefs.setString(ProfileService.key(_modeKey), _authMode!.name);
    }
    await prefs.setString(ProfileService.key(_cookieKey), _sessionCookie);
    await prefs.setString(ProfileService.key(_userKey), _userName);
  }

  Future<void> _applySignIn({
    required SeerrServerOption server,
    required SeerrAuthMode mode,
    required String userName,
    required String cookie,
  }) async {
    _server = server;
    _authMode = mode;
    _sessionCookie = cookie;
    _userName = userName;
    _loadedProfileKey = ProfileService.key(_modeKey);
    notifyListeners();
    await _persist();
  }

  Future<void> signOut() async {
    await ensureLoaded();
    if (_sessionCookie.isNotEmpty && baseUrl.isNotEmpty) {
      try {
        await http.post(_uri(baseUrl, '/auth/logout'), headers: _headers()).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _server = null;
    _authMode = null;
    _sessionCookie = '';
    _userName = '';
    notifyListeners();
    await _persist();
  }

  static String _encode(String value) {
    return Uri.encodeComponent(value).replaceAllMapped(
          RegExp(r"[!'()*]"),
          (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
        );
  }

  Uri _uri(String base, String path, [Map<String, String>? query]) {
    final q = query == null || query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${_encode(e.key)}=${_encode(e.value)}').join('&')}';
    return Uri.parse('$base/api/v1$path$q');
  }

  Map<String, String> _headers({String? cookie}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final sid = cookie ?? _sessionCookie;
    if (sid.isNotEmpty) headers['Cookie'] = sid;
    return headers;
  }

  static String? _extractSessionCookie(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'connect\.sid=([^;,\s]+)').firstMatch(raw);
    if (match == null) return null;
    return 'connect.sid=${match.group(1)}';
  }

  static String _displayName(dynamic body, String fallback) {
    if (body is Map) {
      for (final k in ['displayName', 'username', 'plexUsername', 'jellyfinUsername', 'email']) {
        final v = body[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
    }
    return fallback;
  }

  String _errorFrom(http.Response res, {bool isLogin = false}) {
    String? serverMessage;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] != null) serverMessage = body['message'].toString();
    } catch (_) {}
    if (isLogin) {
      if (res.statusCode == 401) {
        return serverMessage ?? 'Sign-in failed. Check your username and password.';
      }
      if (res.statusCode == 403) {
        return 'Your account does not have access to this Seerr server. Ask the server owner to import your account or enable new sign-ins.${serverMessage != null ? ' ($serverMessage)' : ''}';
      }
    } else if (res.statusCode == 401 || res.statusCode == 403) {
      if (res.statusCode == 403 && serverMessage != null) return serverMessage;
      return 'Your Seerr session has expired. Sign in again in Settings.';
    }
    return serverMessage ?? 'Seerr request failed (HTTP ${res.statusCode}).';
  }

  Future<http.Response> _rawSend(String method, Uri uri, Map<String, String> headers, String? body) {
    final Future<http.Response> future;
    switch (method) {
      case 'POST':
        future = http.post(uri, headers: headers, body: body);
        break;
      default:
        future = http.get(uri, headers: headers);
    }
    return future.timeout(_timeout);
  }

  Future<http.Response> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    final uri = _uri(baseUrl, path, query);
    var res = await _rawSend(method, uri, _headers(), encoded);
    if ((res.statusCode == 401 || res.statusCode == 403) && _authMode == SeerrAuthMode.plex) {
      if (await _refreshPlexSession()) {
        res = await _rawSend(method, uri, _headers(), encoded);
      }
    }
    final refreshed = _extractSessionCookie(res);
    if (refreshed != null && _authMode != null && refreshed != _sessionCookie) {
      _sessionCookie = refreshed;
      unawaited(_persist());
    }
    return res;
  }

  Future<bool> _refreshPlexSession() async {
    try {
      final token = await PlexAuthService().getSavedToken();
      if (token == null || token.isEmpty) return false;
      final res = await http
          .post(_uri(baseUrl, '/auth/plex'), headers: _headers(cookie: ''), body: jsonEncode({'authToken': token}))
          .timeout(_timeout);
      final cookie = _extractSessionCookie(res);
      if (res.statusCode != 200 || cookie == null) return false;
      _sessionCookie = cookie;
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _sessionLogin(SeerrServerOption server, String path, Map<String, dynamic> payload, SeerrAuthMode mode) async {
    try {
      final res = await http
          .post(_uri(server.url, path), headers: _headers(cookie: ''), body: jsonEncode(payload))
          .timeout(_timeout);
      if (res.statusCode != 200) throw SeerrException(_errorFrom(res, isLogin: true));
      final cookie = _extractSessionCookie(res);
      if (cookie == null) {
        throw SeerrException('${server.name} did not return a session. Please try again later.');
      }
      dynamic body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {}
      final name = _displayName(body, mode.label);
      await _applySignIn(server: server, mode: mode, userName: name, cookie: cookie);
      return name;
    } on SeerrException {
      rethrow;
    } on TimeoutException {
      throw SeerrException('Timed out connecting to ${server.name}.');
    } catch (e) {
      throw SeerrException('Could not connect to ${server.name}: $e');
    }
  }

  Future<String> signInWithPlex(SeerrServerOption server) async {
    final token = await PlexAuthService().getSavedToken();
    if (token == null || token.isEmpty) {
      throw const SeerrException('This profile is not signed in to Plex.');
    }
    return _sessionLogin(server, '/auth/plex', {'authToken': token}, SeerrAuthMode.plex);
  }

  Future<String> signInWithJellyfin(SeerrServerOption server, String username, String password) {
    if (username.trim().isEmpty) throw const SeerrException('Username cannot be empty.');
    return _sessionLogin(server, '/auth/jellyfin', {'username': username.trim(), 'password': password}, SeerrAuthMode.jellyfin);
  }

  Future<String> signInWithLocal(SeerrServerOption server, String email, String password) {
    if (email.trim().isEmpty) throw const SeerrException('Email cannot be empty.');
    return _sessionLogin(server, '/auth/local', {'email': email.trim(), 'password': password}, SeerrAuthMode.local);
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const SeerrException('You are not signed in to Seerr. Sign in from Settings.');
    }
  }

  Future<List<SeerrSearchResult>> search(String query, {int page = 1}) async {
    await ensureLoaded();
    _ensureConfigured();
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final res = await _send('GET', '/search', query: {'query': q, 'page': '$page', 'language': 'en'});
      if (res.statusCode != 200) throw SeerrException(_errorFrom(res));
      final body = jsonDecode(res.body);
      final results = body is Map ? body['results'] : null;
      if (results is! List) return [];
      return results
          .whereType<Map>()
          .map((m) => SeerrSearchResult.fromJson(Map<String, dynamic>.from(m)))
          .whereType<SeerrSearchResult>()
          .toList();
    } on SeerrException {
      rethrow;
    } on TimeoutException {
      throw const SeerrException('Timed out searching Seerr.');
    } catch (e) {
      throw SeerrException('Seerr search failed: $e');
    }
  }

  Future<List<SeerrSeason>> getTvSeasons(int tmdbId) async {
    await ensureLoaded();
    _ensureConfigured();
    try {
      final res = await _send('GET', '/tv/$tmdbId');
      if (res.statusCode != 200) throw SeerrException(_errorFrom(res));
      final body = jsonDecode(res.body);
      if (body is! Map) return [];
      final statusBySeason = <int, SeerrMediaStatus>{};
      final mediaInfo = body['mediaInfo'];
      if (mediaInfo is Map && mediaInfo['seasons'] is List) {
        for (final s in (mediaInfo['seasons'] as List).whereType<Map>()) {
          final n = s['seasonNumber'];
          final st = s['status'];
          if (n is int) statusBySeason[n] = SeerrMediaStatus.fromCode(st is int ? st : null);
        }
      }
      if (mediaInfo is Map && mediaInfo['requests'] is List) {
        for (final r in (mediaInfo['requests'] as List).whereType<Map>()) {
          final reqStatus = r['status'];
          if (reqStatus == 3) continue;
          final seasons = r['seasons'];
          if (seasons is! List) continue;
          for (final s in seasons.whereType<Map>()) {
            final n = s['seasonNumber'];
            if (n is int) {
              final existing = statusBySeason[n] ?? SeerrMediaStatus.none;
              if (existing.canRequest && existing != SeerrMediaStatus.partiallyAvailable) {
                statusBySeason[n] = SeerrMediaStatus.pending;
              }
            }
          }
        }
      }
      final seasons = body['seasons'];
      if (seasons is! List) return [];
      return seasons
          .whereType<Map>()
          .where((s) => s['seasonNumber'] is int && (s['seasonNumber'] as int) > 0)
          .map((s) {
        final n = s['seasonNumber'] as int;
        return SeerrSeason(
          seasonNumber: n,
          name: s['name']?.toString() ?? 'Season $n',
          episodeCount: s['episodeCount'] is int ? s['episodeCount'] as int : 0,
          status: statusBySeason[n] ?? SeerrMediaStatus.none,
        );
      }).toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    } on SeerrException {
      rethrow;
    } on TimeoutException {
      throw const SeerrException('Timed out loading seasons from Seerr.');
    } catch (e) {
      throw SeerrException('Could not load seasons: $e');
    }
  }

  Future<SeerrMediaStatus> request(SeerrSearchResult item, {List<int>? seasons}) async {
    await ensureLoaded();
    _ensureConfigured();
    final payload = <String, dynamic>{
      'mediaType': item.mediaType,
      'mediaId': item.tmdbId,
    };
    if (item.isTv) {
      payload['seasons'] = (seasons == null || seasons.isEmpty) ? 'all' : seasons;
    }
    try {
      final res = await _send('POST', '/request', body: payload);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw SeerrException(_errorFrom(res));
      }
      try {
        final body = jsonDecode(res.body);
        if (body is Map) {
          final reqStatus = body['status'];
          if (reqStatus == 2) return SeerrMediaStatus.processing;
          final media = body['media'];
          if (media is Map && media['status'] is int) {
            final st = SeerrMediaStatus.fromCode(media['status'] as int);
            if (!st.canRequest || st == SeerrMediaStatus.partiallyAvailable) return st;
          }
        }
      } catch (_) {}
      return SeerrMediaStatus.pending;
    } on SeerrException {
      rethrow;
    } on TimeoutException {
      throw const SeerrException('Timed out sending request to Seerr.');
    } catch (e) {
      throw SeerrException('Request failed: $e');
    }
  }
}
