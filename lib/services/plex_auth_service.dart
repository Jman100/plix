import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/plex_pin.dart';
import '../models/plex_user.dart';
import 'plix_device_helper.dart';
import 'update_service.dart';

class PlexAuthService {
  static const String _prefTokenKey = 'plix_auth_token';
  static const String _prefClientIdKey = 'plix_client_id';
  static const String _prefUserKey = 'plix_user_data';

  static const String plexTvApiBase = 'https://plex.tv/api/v2';

  String? _clientIdentifier;
  String? _cachedToken;
  PlexUser? _cachedUser;

  Future<String> getClientIdentifier() async {
    if (_clientIdentifier != null) return _clientIdentifier!;
    final prefs = await SharedPreferences.getInstance();
    var clientId = prefs.getString(_prefClientIdKey);
    if (clientId == null || clientId.isEmpty) {
      clientId = const Uuid().v4();
      await prefs.setString(_prefClientIdKey, clientId);
    }
    _clientIdentifier = clientId;
    return clientId;
  }

  Map<String, String> getHeaders(String clientId, {String? token}) {
    final headers = {
      'Accept': 'application/json',
      'X-Plex-Product': PlixDeviceHelper.clientName,
      'X-Plex-Version': UpdateService.currentVersion,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Device': PlixDeviceHelper.clientDevice,
      'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
      'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
      'X-Plex-Platform-Version': PlixDeviceHelper.clientPlatformVersion,
      'X-Plex-Model': PlixDeviceHelper.clientDevice,
    };
    if (token != null && token.isNotEmpty) {
      headers['X-Plex-Token'] = token;
    }
    return headers;
  }

  Future<PlexPin> createPin() async {
    final clientId = await getClientIdentifier();
    // Do NOT pass strong=true. strong=true generates 25-character cryptographic OAuth tokens.
    // Standard pins endpoint generates the 4-digit code required by plex.tv/link.
    final url = Uri.parse('$plexTvApiBase/pins');
    final response = await http.post(
      url,
      headers: getHeaders(clientId),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return PlexPin.fromJson(json);
    } else {
      throw Exception('Failed to create Plex PIN: ${response.statusCode} - ${response.body}');
    }
  }

  Future<PlexPin> checkPin(int pinId, String code) async {
    final clientId = await getClientIdentifier();
    final url = Uri.parse('$plexTvApiBase/pins/$pinId?code=$code');
    final response = await http.get(
      url,
      headers: getHeaders(clientId),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return PlexPin.fromJson(json);
    } else {
      throw Exception('Failed to check Plex PIN: ${response.statusCode}');
    }
  }

  Future<PlexUser?> fetchUser(String token) async {
    final clientId = await getClientIdentifier();
    final url = Uri.parse('$plexTvApiBase/user');
    final response = await http.get(
      url,
      headers: getHeaders(clientId, token: token),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final user = PlexUser.fromJson(json);
      _cachedUser = user;
      return user;
    }
    return null;
  }

  Future<void> saveSession(String token, PlexUser? user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTokenKey, token);
    _cachedToken = token;
    if (user != null) {
      await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));
      _cachedUser = user;
    }
  }

  Future<String?> getSavedToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_prefTokenKey);
    return _cachedToken;
  }

  Future<PlexUser?> getSavedUser() async {
    if (_cachedUser != null) return _cachedUser;
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_prefUserKey);
    if (userJson != null) {
      try {
        _cachedUser = PlexUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    return _cachedUser;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefTokenKey);
    await prefs.remove(_prefUserKey);
    await prefs.remove('plix_pinned_servers');
    await prefs.remove('plix_active_server');
    _cachedToken = null;
    _cachedUser = null;
  }
}
