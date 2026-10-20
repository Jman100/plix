class PlexConnection {
  final String protocol;
  final String address;
  final int port;
  final String uri;
  final bool local;
  final bool relay;

  PlexConnection({
    required this.protocol,
    required this.address,
    required this.port,
    required this.uri,
    required this.local,
    required this.relay,
  });

  factory PlexConnection.fromJson(Map<String, dynamic> json) {
    final proto = json['protocol'] as String? ?? 'http';
    final addr = json['address'] as String? ?? '';
    final portNum = (json['port'] is int)
        ? json['port'] as int
        : int.tryParse(json['port']?.toString() ?? '32400') ?? 32400;
    String rawUri = json['uri'] as String? ?? '';
    if (rawUri.isEmpty && addr.isNotEmpty) {
      rawUri = '$proto://$addr:$portNum';
    }

    return PlexConnection(
      protocol: proto,
      address: addr,
      port: portNum,
      uri: rawUri,
      local: json['local'] == true || json['local'] == 1 || json['local'] == '1',
      relay: json['relay'] == true || json['relay'] == 1 || json['relay'] == '1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'address': address,
      'port': port,
      'uri': uri,
      'local': local,
      'relay': relay,
    };
  }
}

class PlexServer {
  final String name;
  final String clientIdentifier;
  String accessToken;
  final bool owned;
  final List<PlexConnection> connections;
  String? activeConnectionUri;
  bool isPinned;
  final String serverType; // 'plex' or 'jellyfin'
  final String? userId; // Jellyfin User ID

  bool get isJellyfin => serverType == 'jellyfin';
  bool get isPlex => serverType == 'plex';

  PlexServer({
    required this.name,
    required this.clientIdentifier,
    required this.accessToken,
    required this.owned,
    required this.connections,
    this.activeConnectionUri,
    this.isPinned = false,
    this.serverType = 'plex',
    this.userId,
  });

  factory PlexServer.fromJson(Map<String, dynamic> json) {
    final rawConnections = json['connections'] as List<dynamic>? ?? [];
    final parsedConnections = rawConnections
        .map((c) => PlexConnection.fromJson(c as Map<String, dynamic>))
        .toList();

    return PlexServer(
      name: json['name'] as String? ?? 'Plex Server',
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      owned: json['owned'] == true || json['owned'] == 1 || json['owned'] == '1',
      connections: parsedConnections,
      activeConnectionUri: json['activeConnectionUri'] as String?,
      isPinned: json['isPinned'] == true,
      serverType: json['serverType'] as String? ?? 'plex',
      userId: json['userId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'clientIdentifier': clientIdentifier,
      'accessToken': accessToken,
      'owned': owned,
      'connections': connections.map((c) => c.toJson()).toList(),
      'activeConnectionUri': activeConnectionUri,
      'isPinned': isPinned,
      'serverType': serverType,
      'userId': userId,
    };
  }
}
