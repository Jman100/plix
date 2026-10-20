class PlexUser {
  final int id;
  final String uuid;
  final String username;
  final String email;
  final String? thumb;

  PlexUser({
    required this.id,
    required this.uuid,
    required this.username,
    required this.email,
    this.thumb,
  });

  factory PlexUser.fromJson(Map<String, dynamic> json) {
    return PlexUser(
      id: json['id'] as int? ?? 0,
      uuid: json['uuid'] as String? ?? '',
      username: json['username'] as String? ?? json['title'] as String? ?? 'Plex User',
      email: json['email'] as String? ?? '',
      thumb: json['thumb'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'email': email,
      'thumb': thumb,
    };
  }
}
