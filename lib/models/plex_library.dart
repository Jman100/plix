class PlexLibrary {
  final String key;
  final String title;
  final String type; // 'movie', 'show', 'artist', 'photo'
  final String? thumb;

  PlexLibrary({
    required this.key,
    required this.title,
    required this.type,
    this.thumb,
  });

  bool get isMovie => type == 'movie';
  bool get isShow => type == 'show';

  factory PlexLibrary.fromJson(Map<String, dynamic> json) {
    return PlexLibrary(
      key: json['key']?.toString() ?? '',
      title: json['title'] as String? ?? 'Library',
      type: json['type'] as String? ?? 'movie',
      thumb: json['thumb'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'title': title,
      'type': type,
      'thumb': thumb,
    };
  }
}
