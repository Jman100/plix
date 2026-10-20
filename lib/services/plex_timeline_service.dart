import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import 'plix_device_helper.dart';
import 'update_service.dart';

class PlexTimelineService {
  final PlexServer server;
  final String clientId;
  Timer? _heartbeatTimer;
  PlexMediaItem? _currentItem;
  int _currentTimeMs = 0;
  bool _isPlaying = false;
  bool _scrobbled = false;
  int _missingSessionCount = 0;
  WebSocket? _ws;
  StreamSubscription? _wsSub;

  final StreamController<String?> _serverStopController = StreamController<String?>.broadcast();
  Stream<String?> get onServerStop => _serverStopController.stream;

  PlexTimelineService({
    required this.server,
    required this.clientId,
  });

  String get baseUrl => server.activeConnectionUri ?? '';
  String get token => server.accessToken;

  void startPlayback(PlexMediaItem item, int initialTimeMs) {
    _currentItem = item;
    _currentTimeMs = initialTimeMs;
    _isPlaying = true;
    _scrobbled = false;
    _missingSessionCount = 0;

    if (server.isJellyfin) {
      final itemId = item.ratingKey;
      final ticks = initialTimeMs * 10000;
      final endpoint = '$baseUrl/Sessions/Playing';
      final headers = {
        'Authorization': 'MediaBrowser Client="Plix", Device="${PlixDeviceHelper.deviceName}", DeviceId="$clientId", Version="${UpdateService.currentVersion}", Token="$token"',
        'Content-Type': 'application/json',
      };
      final body = jsonEncode({
        'ItemId': itemId,
        'MediaSourceId': itemId,
        'PositionTicks': ticks,
      });
      try {
        http.post(Uri.parse(endpoint), headers: headers, body: body);
      } catch (_) {}
    }

    _connectWebSocket();
    _reportTimeline(state: 'playing', timeMs: initialTimeMs);

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_isPlaying && _currentItem != null) {
        _reportTimeline(state: 'playing', timeMs: _currentTimeMs);
        _checkScrobble();
        if (!server.isJellyfin) {
          _checkSessionStatus();
        }
      }
    });
  }

  void _connectWebSocket() async {
    _closeWebSocket();
    if (server.isJellyfin) {
      try {
        final serverUri = Uri.parse(baseUrl);
        final wsScheme = serverUri.scheme == 'https' ? 'wss' : 'ws';
        final wsUrl = '$wsScheme://${serverUri.host}:${serverUri.port}/socket?api_key=$token&deviceId=$clientId';
        final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
        _ws = ws;
        _wsSub = ws.listen(
          (data) {
            if (data is String) {
              _handleJellyfinWsNotification(data);
            }
          },
          onError: (_) {},
          onDone: () {},
        );
      } catch (_) {}
      return;
    }
    try {
      final serverUri = Uri.parse(baseUrl);
      final wsScheme = serverUri.scheme == 'https' ? 'wss' : 'ws';
      final wsUrl = '$wsScheme://${serverUri.host}:${serverUri.port}/:/websockets/notifications?X-Plex-Token=$token';
      final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
      _ws = ws;
      _wsSub = ws.listen(
        (data) {
          if (data is String) {
            _handleWsNotification(data);
          }
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {}
  }

  void _closeWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  void _handleJellyfinWsNotification(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        final msgType = json['MessageType']?.toString().toLowerCase();
        if (msgType == 'playstate' || msgType == 'generalcommand') {
          final data = json['Data'] as Map<String, dynamic>? ?? {};
          final cmd = data['Command']?.toString().toLowerCase() ?? data['Name']?.toString().toLowerCase();
          if (cmd == 'stop' || cmd == 'stopplayback') {
            final reason = data['Reason']?.toString() ?? data['Message']?.toString() ?? 'Playback stopped by server.';
            _triggerServerStop(reason);
          }
        }
      }
    } catch (_) {}
  }

  void _handleWsNotification(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        final container = json['NotificationContainer'];
        if (container is Map<String, dynamic>) {
          final playSessions = container['PlaySessionStateNotification'];
          final list = playSessions is List ? playSessions : (playSessions is Map ? [playSessions] : null);
          if (list != null) {
            for (final s in list) {
              if (s is Map<String, dynamic>) {
                final sState = s['state']?.toString().toLowerCase();
                final sClient = s['clientIdentifier']?.toString();
                if (sState == 'stopped' && (sClient == null || sClient == clientId)) {
                  final reason = s['reason']?.toString() ?? s['message']?.toString();
                  _triggerServerStop(reason);
                  return;
                }
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  void _triggerServerStop(String? reason) {
    if (!_serverStopController.isClosed && _isPlaying) {
      _isPlaying = false;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _closeWebSocket();
      _serverStopController.add(reason);
    }
  }

  Future<void> _checkSessionStatus() async {
    try {
      final sessionsUrl = Uri.parse('$baseUrl/status/sessions?X-Plex-Token=$token');
      final res = await http.get(sessionsUrl, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = res.body.trim();
        if (body.isNotEmpty && !body.contains(clientId)) {
          _missingSessionCount++;
          if (_missingSessionCount >= 2) {
            _triggerServerStop(null);
          }
        } else {
          _missingSessionCount = 0;
        }
      }
    } catch (_) {}
  }

  void updatePosition(int timeMs) {
    _currentTimeMs = timeMs;
    _checkScrobble();
  }

  void pause(int timeMs) {
    _currentTimeMs = timeMs;
    _isPlaying = false;
    _reportTimeline(state: 'paused', timeMs: timeMs);
  }

  void resume(int timeMs) {
    _currentTimeMs = timeMs;
    _isPlaying = true;
    _reportTimeline(state: 'playing', timeMs: timeMs);
  }

  void stop(int timeMs) {
    _currentTimeMs = timeMs;
    _isPlaying = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _closeWebSocket();
    _reportTimeline(state: 'stopped', timeMs: timeMs);
  }

  void _checkScrobble() {
    if (_scrobbled || _currentItem == null) return;
    if (_currentItem!.isTrailer || _currentItem!.type == 'clip') return;
    final dur = _currentItem!.duration;
    if (dur != null && dur > 0) {
      if (_currentTimeMs >= (dur * 0.90)) {
        _scrobbled = true;
        _scrobbleItem(_currentItem!.ratingKey);
      }
    }
  }

  Future<void> _scrobbleItem(String ratingKey) async {
    if (server.isJellyfin) {
      final userId = server.userId ?? '';
      final url = Uri.parse('$baseUrl/Users/$userId/PlayedItems/$ratingKey');
      final headers = {
        'Authorization': 'MediaBrowser Client="Plix", Device="${PlixDeviceHelper.deviceName}", DeviceId="$clientId", Version="${UpdateService.currentVersion}", Token="$token"',
      };
      try {
        await http.post(url, headers: headers);
      } catch (_) {}
      return;
    }
    final url = Uri.parse(
        '$baseUrl/:/scrobble?key=$ratingKey&identifier=com.plexapp.plugins.library&X-Plex-Token=$token');
    try {
      await http.get(url);
    } catch (_) {}
  }

  Future<void> _reportTimeline({required String state, required int timeMs}) async {
    if (_currentItem == null) return;

    if (server.isJellyfin) {
      final itemId = _currentItem!.ratingKey;
      final ticks = timeMs * 10000;
      final isPaused = state == 'paused';
      String endpoint = '$baseUrl/Sessions/Playing/Progress';
      if (state == 'stopped') {
        endpoint = '$baseUrl/Sessions/Playing/Stopped';
      }
      final headers = {
        'Authorization': 'MediaBrowser Client="Plix", Device="${PlixDeviceHelper.deviceName}", DeviceId="$clientId", Version="${UpdateService.currentVersion}", Token="$token"',
        'Content-Type': 'application/json',
      };
      final body = jsonEncode({
        'ItemId': itemId,
        'PositionTicks': ticks,
        'IsPaused': isPaused,
      });
      try {
        await http.post(Uri.parse(endpoint), headers: headers, body: body).timeout(const Duration(seconds: 4));
      } catch (_) {}
      return;
    }
    final ratingKey = _currentItem!.ratingKey;
    final duration = _currentItem!.duration ?? 0;

    final productParam = Uri.encodeComponent(PlixDeviceHelper.clientName);
    final deviceParam = Uri.encodeComponent(PlixDeviceHelper.deviceName);
    final platformParam = Uri.encodeComponent(PlixDeviceHelper.clientPlatform);
    final versionParam = Uri.encodeComponent(UpdateService.currentVersion);

    final url = Uri.parse(
      '$baseUrl/:/timeline?ratingKey=$ratingKey'
      '&key=%2Flibrary%2Fmetadata%2F$ratingKey'
      '&state=$state'
      '&time=$timeMs'
      '&duration=$duration'
      '&X-Plex-Token=$token'
      '&X-Plex-Client-Identifier=$clientId'
      '&X-Plex-Product=$productParam'
      '&X-Plex-Device=$deviceParam'
      '&X-Plex-Device-Name=$deviceParam'
      '&X-Plex-Platform=$platformParam'
      '&X-Plex-Version=$versionParam',
    );

    final headers = {
      'Accept': 'application/json',
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Product': PlixDeviceHelper.clientName,
      'X-Plex-Device': PlixDeviceHelper.clientDevice,
      'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
      'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
      'X-Plex-Version': UpdateService.currentVersion,
    };

    try {
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 4));

      // Handle server stopping playback / terminating session
      if (response.statusCode >= 400) {
        // Any 4xx (404, 400, 401, 403, 410) or 5xx indicates session rejected/terminated
        final reason = _extractReasonFromBodyOrHeaders(response.body, response.headers);
        _triggerServerStop(reason);
      } else if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.isNotEmpty && _checkIfStopCommand(body, response.headers)) {
          final reason = _extractReasonFromBodyOrHeaders(body, response.headers);
          _triggerServerStop(reason);
        }
      }
    } catch (_) {}
  }

  bool _checkIfStopCommand(String body, Map<String, String> headers) {
    if (headers['x-plex-command']?.toLowerCase() == 'stop') return true;
    if (headers['x-plex-session-terminated'] == '1' ||
        headers['x-plex-session-terminated']?.toLowerCase() == 'true') {
      return true;
    }

    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final mc = json['MediaContainer'] ?? json['Response'] ?? json;
        if (mc is Map<String, dynamic>) {
          final cmd = mc['command']?.toString().toLowerCase();
          if (cmd == 'stop' || cmd == 'terminate') return true;
          if (mc.containsKey('terminateReason') || mc.containsKey('stopReason')) return true;
        }
      }
    } catch (_) {}

    final lower = body.toLowerCase();
    if (lower.contains('command="stop"') ||
        lower.contains("command='stop'") ||
        lower.contains('command="terminate"') ||
        lower.contains("command='terminate'") ||
        lower.contains('"command":"stop"') ||
        lower.contains('"command":"terminate"') ||
        (lower.contains('state="stopped"') && lower.contains('playqueuestatenotification'))) {
      return true;
    }
    return false;
  }

  String? _extractReasonFromBodyOrHeaders(String body, Map<String, String> headers) {
    for (final entry in headers.entries) {
      final k = entry.key.toLowerCase();
      if (k == 'x-plex-stop-reason' ||
          k == 'x-plex-terminate-reason' ||
          k == 'x-plex-reason' ||
          k == 'x-plex-message' ||
          k == 'reason' ||
          k == 'message') {
        final val = entry.value.trim();
        if (val.isNotEmpty) {
          try {
            return Uri.decodeComponent(val);
          } catch (_) {
            return val;
          }
        }
      }
    }

    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final mc = json['MediaContainer'] ?? json['Response'] ?? json;
        if (mc is Map<String, dynamic>) {
          final msg = mc['message'] ?? mc['reason'] ?? mc['stopReason'] ?? mc['terminateReason'] ?? mc['status'];
          if (msg != null && msg.toString().trim().isNotEmpty) {
            return msg.toString().trim();
          }
        }
      }
    } catch (_) {}

    final match = RegExp(
      r"""(?:message|reason|stopReason|terminateReason|status)=["']([^"']+)["']""",
      caseSensitive: false,
    ).firstMatch(body);
    if (match != null) {
      final val = match.group(1)?.trim();
      if (val != null && val.isNotEmpty) return val;
    }
    return null;
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _closeWebSocket();
    _serverStopController.close();
  }
}
