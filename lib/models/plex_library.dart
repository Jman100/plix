import 'plex_server.dart';

class PlexLibrary {
  final String key;
  final String title;
  final String type; // 'movie', 'show', 'artist', 'photo'
  final String? thumb;
  final String? serverId;
  final String? serverName;
  final bool isJellyfin;
  bool isServerOnline;
  final PlexServer? server;

  PlexLibrary({
    required this.key,
    required this.title,
    required this.type,
    this.thumb,
    this.serverId,
    this.serverName,
    this.isJellyfin = false,
    this.isServerOnline = true,
    this.server,
  });

  bool get isMovie => type == 'movie';
  bool get isShow => type == 'show';

  String get compositeId =>
      (serverId != null && serverId!.isNotEmpty) ? '$serverId:$key' : key;

  PlexLibrary copyWith({
    String? key,
    String? title,
    String? type,
    String? thumb,
    String? serverId,
    String? serverName,
    bool? isJellyfin,
    bool? isServerOnline,
    PlexServer? server,
  }) {
    return PlexLibrary(
      key: key ?? this.key,
      title: title ?? this.title,
      type: type ?? this.type,
      thumb: thumb ?? this.thumb,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      isJellyfin: isJellyfin ?? this.isJellyfin,
      isServerOnline: isServerOnline ?? this.isServerOnline,
      server: server ?? this.server,
    );
  }

  factory PlexLibrary.fromJson(Map<String, dynamic> json) {
    return PlexLibrary(
      key: json['key']?.toString() ?? '',
      title: json['title'] as String? ?? 'Library',
      type: json['type'] as String? ?? 'movie',
      thumb: json['thumb'] as String?,
      serverId: json['serverId'] as String?,
      serverName: json['serverName'] as String?,
      isJellyfin: json['isJellyfin'] == true,
      isServerOnline: json['isServerOnline'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'title': title,
      'type': type,
      'thumb': thumb,
      'serverId': serverId,
      'serverName': serverName,
      'isJellyfin': isJellyfin,
      'isServerOnline': isServerOnline,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlexLibrary &&
          runtimeType == other.runtimeType &&
          compositeId == other.compositeId;

  @override
  int get hashCode => compositeId.hashCode;
}
