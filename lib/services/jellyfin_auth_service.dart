import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class JellyfinServerInfo {
  final String name;
  final String version;
  final String id;
  final String address;
  final String? localAddress;

  const JellyfinServerInfo({
    required this.name,
    required this.version,
    required this.id,
    required this.address,
    this.localAddress,
  });

  factory JellyfinServerInfo.fromJson(Map<String, dynamic> json, String fallbackAddress) {
    String addr = json['Address']?.toString() ?? json['LocalAddress']?.toString() ?? fallbackAddress;
    if (!addr.startsWith('http://') && !addr.startsWith('https://')) {
      addr = 'http://$addr';
    }
    return JellyfinServerInfo(
      name: json['Name']?.toString() ?? json['ServerName']?.toString() ?? 'Jellyfin Server',
      version: json['Version']?.toString() ?? '',
      id: json['Id']?.toString() ?? '',
      address: addr,
      localAddress: json['LocalAddress']?.toString() ?? json['Address']?.toString(),
    );
  }
}

class JellyfinQuickConnectResult {
  final String code;
  final String secret;

  const JellyfinQuickConnectResult({
    required this.code,
    required this.secret,
  });
}

class JellyfinAuthResult {
  final String accessToken;
  final String userId;
  final String userName;
  final String serverId;
  final String serverName;

  const JellyfinAuthResult({
    required this.accessToken,
    required this.userId,
    required this.userName,
    required this.serverId,
    required this.serverName,
  });
}

class JellyfinAuthService {
  static String normalizeUrl(String input) {
    String trimmed = input.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    return trimmed;
  }

  static String buildAuthHeader({
    required String clientId,
    required String clientName,
    required String version,
    String? token,
    String? deviceName,
  }) {
    final buffer = StringBuffer('MediaBrowser ');
    buffer.write('Client="$clientName", ');
    buffer.write('Device="${deviceName ?? clientName}", ');
    buffer.write('DeviceId="$clientId", ');
    buffer.write('Version="$version"');
    if (token != null && token.isNotEmpty) {
      buffer.write(', Token="$token"');
    }
    return buffer.toString();
  }

  Future<JellyfinServerInfo?> testServer(String serverUrl) async {
    final cleanUrl = normalizeUrl(serverUrl);
    final endpoint = Uri.parse('$cleanUrl/System/Info/Public');
    try {
      final response = await http.get(endpoint).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return JellyfinServerInfo.fromJson(data, cleanUrl);
      }
    } catch (_) {}
    return null;
  }

  Future<List<JellyfinServerInfo>> discoverServersLAN({Duration timeout = const Duration(seconds: 2)}) async {
    final List<JellyfinServerInfo> servers = [];
    final Set<String> seenIds = {};

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final message = utf8.encode('Who is JellyfinServer?');
      socket.send(message, InternetAddress('255.255.255.255'), 7359);

      final completer = Completer<List<JellyfinServerInfo>>();
      Timer(timeout, () {
        if (!completer.isCompleted) {
          socket.close();
          completer.complete(servers);
        }
      });

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              final json = jsonDecode(text) as Map<String, dynamic>;
              final info = JellyfinServerInfo.fromJson(json, 'http://${datagram.address.address}:8096');
              final key = info.id.isNotEmpty ? info.id : info.address;
              if (!seenIds.contains(key)) {
                seenIds.add(key);
                servers.add(info);
              }
            } catch (_) {}
          }
        }
      });

      final discoveredList = await completer.future;

      // Verify if any discovered server is reachable over HTTPS and upgrade address where applicable
      final List<JellyfinServerInfo> upgradedServers = [];
      for (final s in discoveredList) {
        final httpsUrl = await _detectHttpsUrl(s.address, s.localAddress);
        if (httpsUrl != null) {
          upgradedServers.add(
            JellyfinServerInfo(
              name: s.name,
              version: s.version,
              id: s.id,
              address: httpsUrl,
              localAddress: s.localAddress,
            ),
          );
        } else {
          upgradedServers.add(s);
        }
      }
      return upgradedServers;
    } catch (_) {
      return servers;
    }
  }

  Future<String?> _detectHttpsUrl(String reportedAddress, String? localAddressHint) async {
    final uri = Uri.tryParse(reportedAddress);
    if (uri == null) return null;

    final candidates = <String>{};

    // If localAddressHint is provided (e.g. "jellyfin.jman100.com")
    if (localAddressHint != null && localAddressHint.isNotEmpty) {
      String clean = localAddressHint.trim();
      if (clean.startsWith('http://')) clean = clean.substring(7);
      if (clean.startsWith('https://')) clean = clean.substring(8);
      candidates.add('https://$clean');
    }

    // Direct host over HTTPS (port 443)
    final host = uri.host;
    if (host.isNotEmpty) {
      candidates.add('https://$host');
      // Same port if custom
      if (uri.hasPort && uri.port != 80 && uri.port != 8096) {
        candidates.add('https://$host:${uri.port}');
      }
      // Standard Jellyfin SSL port 8920
      candidates.add('https://$host:8920');
    }

    // Replace http:// with https:// directly on reported address
    if (reportedAddress.startsWith('http://')) {
      candidates.add(reportedAddress.replaceFirst('http://', 'https://'));
    }

    for (final candidate in candidates) {
      try {
        final endpoint = Uri.parse('$candidate/System/Info/Public');
        final response = await http.get(endpoint).timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<JellyfinQuickConnectResult> initiateQuickConnect(
    String serverUrl, {
    required String clientId,
    required String clientName,
    required String version,
  }) async {
    final cleanUrl = normalizeUrl(serverUrl);
    final endpoint = Uri.parse('$cleanUrl/QuickConnect/Initiate');
    final authHeader = buildAuthHeader(
      clientId: clientId,
      clientName: clientName,
      version: version,
    );

    final response = await http.post(
      endpoint,
      headers: {
        'Authorization': authHeader,
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 6));

    if (response.statusCode != 200) {
      throw Exception('Failed to initiate Quick Connect (HTTP ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['Code']?.toString() ?? '';
    final secret = data['Secret']?.toString() ?? '';

    if (code.isEmpty || secret.isEmpty) {
      throw Exception('Invalid Quick Connect response from server');
    }

    return JellyfinQuickConnectResult(code: code, secret: secret);
  }

  Future<bool> checkQuickConnect(String serverUrl, String secret) async {
    final cleanUrl = normalizeUrl(serverUrl);
    final endpoint = Uri.parse('$cleanUrl/QuickConnect/Connect?secret=$secret');

    try {
      final response = await http.get(endpoint).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['Authenticated'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<JellyfinAuthResult> authenticateWithQuickConnect(
    String serverUrl,
    String secret, {
    required String clientId,
    required String clientName,
    required String version,
  }) async {
    final cleanUrl = normalizeUrl(serverUrl);
    final endpoint = Uri.parse('$cleanUrl/Users/AuthenticateWithQuickConnect');
    final authHeader = buildAuthHeader(
      clientId: clientId,
      clientName: clientName,
      version: version,
    );

    final response = await http.post(
      endpoint,
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'Secret': secret}),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Failed to authenticate with Quick Connect (HTTP ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['AccessToken']?.toString() ?? '';
    final user = data['User'] as Map<String, dynamic>? ?? {};
    final userId = user['Id']?.toString() ?? '';
    final userName = user['Name']?.toString() ?? 'User';
    final serverId = data['ServerId']?.toString() ?? '';

    if (token.isEmpty || userId.isEmpty) {
      throw Exception('Incomplete authentication response from server');
    }

    // Try fetching public server info to get nice server name
    String serverName = 'Jellyfin Server';
    try {
      final info = await testServer(cleanUrl);
      if (info != null && info.name.isNotEmpty) {
        serverName = info.name;
      }
    } catch (_) {}

    return JellyfinAuthResult(
      accessToken: token,
      userId: userId,
      userName: userName,
      serverId: serverId,
      serverName: serverName,
    );
  }
}
