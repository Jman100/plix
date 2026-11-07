class SubtitleSearchResult {
  final String id;
  final String key;
  final String title;
  final String language;
  final String languageCode;
  final String format;
  final String provider;
  final bool isHearingImpaired;
  final int? score;

  const SubtitleSearchResult({
    required this.id,
    required this.key,
    required this.title,
    required this.language,
    required this.languageCode,
    required this.format,
    required this.provider,
    this.isHearingImpaired = false,
    this.score,
  });

  factory SubtitleSearchResult.fromPlexJson(Map<String, dynamic> json) {
    return SubtitleSearchResult(
      id: json['ratingKey']?.toString() ?? json['id']?.toString() ?? json['key']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? json['summary']?.toString() ?? 'Subtitle',
      language: json['language']?.toString() ?? 'Unknown',
      languageCode: json['languageCode']?.toString() ?? 'en',
      format: json['format']?.toString() ?? 'srt',
      provider: json['provider']?.toString() ?? json['source']?.toString() ?? 'Plex',
      isHearingImpaired: json['hearingImpaired'] == 1 || json['hearingImpaired'] == true || json['hearingImpaired'] == '1',
      score: (json['score'] is num) ? (json['score'] as num).toInt() : int.tryParse(json['score']?.toString() ?? ''),
    );
  }

  factory SubtitleSearchResult.fromJellyfinJson(Map<String, dynamic> json) {
    return SubtitleSearchResult(
      id: json['Id']?.toString() ?? '',
      key: json['Id']?.toString() ?? '',
      title: json['Name']?.toString() ?? 'Subtitle',
      language: json['ThreeLetterISOLanguageName']?.toString() ?? 'eng',
      languageCode: json['ThreeLetterISOLanguageName']?.toString() ?? 'en',
      format: json['Format']?.toString() ?? 'srt',
      provider: json['ProviderName']?.toString() ?? 'Jellyfin',
      isHearingImpaired: json['IsForHearingImpaired'] == true,
      score: (json['CommunityRating'] is num) ? ((json['CommunityRating'] as num) * 10).toInt() : null,
    );
  }
}
