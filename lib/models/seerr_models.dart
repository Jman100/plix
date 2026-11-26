class SeerrMediaItem {
  final int id; // tmdbId
  final String mediaType; // 'movie' or 'tv'
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final int? mediaStatus; // 1: Unknown, 2: Pending, 3: Processing, 4: Partial, 5: Available
  final int? mediaStatus4k;
  final int? requestId;
  final int? requestStatus; // 1: Pending, 2: Approved, 3: Declined
  final List<int>? requestedSeasons;
  final bool is4kRequest;

  SeerrMediaItem({
    required this.id,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.mediaStatus,
    this.mediaStatus4k,
    this.requestId,
    this.requestStatus,
    this.requestedSeasons,
    this.is4kRequest = false,
  });

  bool get isMovie => mediaType.toLowerCase() == 'movie';
  bool get isTv => mediaType.toLowerCase() == 'tv';

  String get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) return '';
    if (posterPath!.startsWith('http')) return posterPath!;
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  String get backdropUrl {
    if (backdropPath == null || backdropPath!.isEmpty) return '';
    if (backdropPath!.startsWith('http')) return backdropPath!;
    return 'https://image.tmdb.org/t/p/w780$backdropPath';
  }

  String get year {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    if (releaseDate!.length >= 4) return releaseDate!.substring(0, 4);
    return releaseDate!;
  }

  bool get isAvailable => mediaStatus == 5;
  bool get isStandardAvailable => mediaStatus == 5;
  bool get is4kAvailable => mediaStatus4k == 5;
  bool get isAnyAvailable => isAvailable || is4kAvailable;
  bool get isPartiallyAvailable => mediaStatus == 4 || mediaStatus4k == 4;
  bool get isProcessing => mediaStatus == 3 || mediaStatus4k == 3;
  bool get isPending => mediaStatus == 2 || mediaStatus4k == 2;
  bool get hasRequestOrAvailable =>
      (mediaStatus != null && mediaStatus! >= 2) ||
      (mediaStatus4k != null && mediaStatus4k! >= 2) ||
      requestId != null;

  SeerrMediaItem copyWith({
    int? id,
    String? mediaType,
    String? title,
    String? overview,
    String? posterPath,
    String? backdropPath,
    String? releaseDate,
    double? voteAverage,
    int? mediaStatus,
    int? mediaStatus4k,
    int? requestId,
    int? requestStatus,
    List<int>? requestedSeasons,
    bool? is4kRequest,
  }) {
    return SeerrMediaItem(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      releaseDate: releaseDate ?? this.releaseDate,
      voteAverage: voteAverage ?? this.voteAverage,
      mediaStatus: mediaStatus ?? this.mediaStatus,
      mediaStatus4k: mediaStatus4k ?? this.mediaStatus4k,
      requestId: requestId ?? this.requestId,
      requestStatus: requestStatus ?? this.requestStatus,
      requestedSeasons: requestedSeasons ?? this.requestedSeasons,
      is4kRequest: is4kRequest ?? this.is4kRequest,
    );
  }

  factory SeerrMediaItem.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('media') && (json.containsKey('type') || (json['media'] is Map && (json['media'] as Map).containsKey('mediaType')))) {
      final media = json['media'] as Map<String, dynamic>? ?? {};
      final type = json['type']?.toString() ?? media['mediaType']?.toString() ?? 'movie';
      final seasonsList = <int>[];
      if (json['seasons'] is List) {
        for (final s in json['seasons']) {
          if (s is Map && s['seasonNumber'] != null) {
            seasonsList.add(s['seasonNumber'] as int);
          }
        }
      }
      return SeerrMediaItem(
        id: media['tmdbId'] as int? ?? json['id'] as int? ?? 0,
        mediaType: type,
        title: media['title']?.toString() ?? media['name']?.toString() ?? json['title']?.toString() ?? '',
        overview: media['overview']?.toString(),
        posterPath: media['poster']?.toString() ?? media['posterPath']?.toString(),
        backdropPath: media['background']?.toString() ?? media['backdropPath']?.toString(),
        releaseDate: media['releaseDate']?.toString() ?? media['firstAirDate']?.toString(),
        mediaStatus: media['status'] as int?,
        mediaStatus4k: media['status4k'] as int?,
        requestId: json['id'] as int?,
        requestStatus: json['status'] as int?,
        requestedSeasons: seasonsList.isNotEmpty ? seasonsList : null,
        is4kRequest: json['is4k'] == true,
      );
    }

    final mediaType = json['mediaType']?.toString() ??
        (json.containsKey('name') ? 'tv' : 'movie');
    final title = json['title']?.toString() ?? json['name']?.toString() ?? '';
    final mediaInfo = json['mediaInfo'] as Map<String, dynamic>?;

    return SeerrMediaItem(
      id: json['id'] as int? ?? 0,
      mediaType: mediaType,
      title: title,
      overview: json['overview']?.toString(),
      posterPath: json['posterPath']?.toString(),
      backdropPath: json['backdropPath']?.toString(),
      releaseDate: json['releaseDate']?.toString() ?? json['firstAirDate']?.toString(),
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      mediaStatus: mediaInfo?['status'] as int?,
      mediaStatus4k: mediaInfo?['status4k'] as int?,
    );
  }
}

class SeerrSeason {
  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;
  final String? overview;
  final int? status; // from mediaInfo.seasons

  SeerrSeason({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath,
    this.overview,
    this.status,
  });

  bool get isAvailableOrRequested => status != null && status! >= 2;
  bool get isAvailable => status == 5;
  bool get isProcessing => status == 3;
  bool get isPending => status == 2;
  bool get isPartial => status == 4;

  factory SeerrSeason.fromJson(Map<String, dynamic> json, {int? mediaInfoStatus}) {
    return SeerrSeason(
      id: json['id'] as int? ?? 0,
      seasonNumber: json['seasonNumber'] as int? ?? 0,
      name: json['name']?.toString() ?? 'Season ${json['seasonNumber']}',
      episodeCount: json['episodeCount'] as int? ?? 0,
      posterPath: json['posterPath']?.toString(),
      overview: json['overview']?.toString(),
      status: mediaInfoStatus,
    );
  }
}

class SeerrMediaDetails {
  final int id;
  final String mediaType;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final List<String> genres;
  final int? runtime;
  final int? mediaStatus;
  final int? mediaStatus4k;
  final String? ratingKey;
  final String? jellyfinMediaId;
  final bool has4kRequest;
  final bool hasStandardRequest;
  final List<SeerrSeason> seasons;
  final List<SeerrVideo> relatedVideos;
  final String? firstAirDate;
  final String? theatricalReleaseDate;
  final String? digitalReleaseDate;

  SeerrMediaDetails({
    required this.id,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    required this.genres,
    this.runtime,
    this.mediaStatus,
    this.mediaStatus4k,
    this.ratingKey,
    this.jellyfinMediaId,
    this.has4kRequest = false,
    this.hasStandardRequest = false,
    required this.seasons,
    this.relatedVideos = const [],
    this.firstAirDate,
    this.theatricalReleaseDate,
    this.digitalReleaseDate,
  });

  static String formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final datePart = raw.trim().split('T').first;
    final parts = datePart.split('-');
    if (parts.length != 3) return datePart;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null || month < 1 || month > 12) {
      return datePart;
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }

  bool get isMovie => mediaType.toLowerCase() == 'movie';
  bool get isTv => mediaType.toLowerCase() == 'tv';

  String get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) return '';
    if (posterPath!.startsWith('http')) return posterPath!;
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  String get backdropUrl {
    if (backdropPath == null || backdropPath!.isEmpty) return '';
    if (backdropPath!.startsWith('http')) return backdropPath!;
    return 'https://image.tmdb.org/t/p/w780$backdropPath';
  }

  String get year {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    if (releaseDate!.length >= 4) return releaseDate!.substring(0, 4);
    return releaseDate!;
  }

  bool get isAvailable => mediaStatus == 5;
  bool get isStandardAvailable => mediaStatus == 5;
  bool get is4kAvailable => mediaStatus4k == 5;
  bool get isAnyAvailable => isAvailable || is4kAvailable;
  bool get isPartiallyAvailable => mediaStatus == 4 || mediaStatus4k == 4;
  bool get isProcessing => mediaStatus == 3 || mediaStatus4k == 3;
  bool get isPending => mediaStatus == 2 || mediaStatus4k == 2;
  bool get hasRequestOrAvailable =>
      (mediaStatus != null && mediaStatus! >= 2) ||
      (mediaStatus4k != null && mediaStatus4k! >= 2) ||
      hasStandardRequest ||
      has4kRequest;

  bool get isStandardRequestedOrAvailable =>
      (mediaStatus != null && mediaStatus! >= 2) || hasStandardRequest;

  bool get is4kRequestedOrAvailable =>
      (mediaStatus4k != null && mediaStatus4k! >= 2) || has4kRequest;

  factory SeerrMediaDetails.fromJson(Map<String, dynamic> json, String mediaType) {
    final title = json['title']?.toString() ?? json['name']?.toString() ?? '';
    final mediaInfo = json['mediaInfo'] as Map<String, dynamic>?;
    final mediaInfoStatus = mediaInfo?['status'] as int?;
    final mediaInfoStatus4k = mediaInfo?['status4k'] as int?;
    final ratingKey = mediaInfo?['ratingKey']?.toString();
    final jellyfinMediaId = mediaInfo?['jellyfinMediaId']?.toString();

    final seasonStatusMap = <int, int>{};
    if (mediaInfo != null && mediaInfo['seasons'] is List) {
      for (final s in mediaInfo['seasons']) {
        if (s is Map && s['seasonNumber'] != null) {
          seasonStatusMap[s['seasonNumber'] as int] = s['status'] as int? ?? 1;
        }
      }
    }

    bool has4k = false;
    bool hasStd = false;
    if (mediaInfo != null && mediaInfo['requests'] is List) {
      for (final req in mediaInfo['requests']) {
        if (req is Map) {
          final reqStatus = req['status'] as int?;
          if (reqStatus != 3) { // 3 is declined
            if (req['is4k'] == true) {
              has4k = true;
            } else {
              hasStd = true;
            }
            if (req['seasons'] is List) {
              for (final s in req['seasons']) {
                if (s is Map && s['seasonNumber'] != null) {
                  final sNum = s['seasonNumber'] as int;
                  final cur = seasonStatusMap[sNum] ?? 1;
                  if (cur < 2) {
                    seasonStatusMap[sNum] = s['status'] as int? ?? 2;
                  }
                }
              }
            }
          }
        }
      }
    }

    final genreList = <String>[];
    if (json['genres'] is List) {
      for (final g in json['genres']) {
        if (g is Map && g['name'] != null) {
          genreList.add(g['name'].toString());
        }
      }
    }

    final isShowProcessingOrRequested = (mediaInfoStatus != null && mediaInfoStatus >= 2) || hasStd;
    final seasonList = <SeerrSeason>[];
    if (json['seasons'] is List) {
      for (final s in json['seasons']) {
        if (s is Map<String, dynamic>) {
          final sNum = s['seasonNumber'] as int? ?? 0;
          if (sNum > 0) {
            int? sStatus = seasonStatusMap[sNum];
            if (sStatus == null && isShowProcessingOrRequested) {
              sStatus = mediaInfoStatus ?? 3;
            }
            seasonList.add(SeerrSeason.fromJson(s, mediaInfoStatus: sStatus));
          }
        }
      }
    }

    final videoList = <SeerrVideo>[];
    if (json['relatedVideos'] is List) {
      for (final v in json['relatedVideos']) {
        if (v is Map<String, dynamic>) {
          videoList.add(SeerrVideo.fromJson(v));
        }
      }
    }

    String? extractReleaseDate(dynamic releasesJson, int targetType) {
      if (releasesJson is! Map || releasesJson['results'] is! List) return null;
      final results = releasesJson['results'] as List;

      String? findInRegion(String? regionCode) {
        String? earliest;
        for (final entry in results) {
          if (entry is! Map) continue;
          if (regionCode != null && entry['iso_3166_1']?.toString() != regionCode) continue;
          final dates = entry['release_dates'];
          if (dates is! List) continue;
          for (final d in dates) {
            if (d is! Map) continue;
            if (d['type'] == targetType) {
              final raw = d['release_date']?.toString() ?? '';
              if (raw.isNotEmpty) {
                final normalized = raw.split('T').first;
                if (earliest == null || normalized.compareTo(earliest) < 0) {
                  earliest = normalized;
                }
              }
            }
          }
        }
        return earliest;
      }

      return findInRegion('US') ?? findInRegion(null);
    }

    final isTvType = mediaType.toLowerCase() == 'tv';
    final firstAirDate = isTvType ? json['firstAirDate']?.toString() : null;
    final theatricalReleaseDate = !isTvType
        ? (extractReleaseDate(json['releases'], 3) ?? json['releaseDate']?.toString())
        : null;
    final digitalReleaseDate = !isTvType ? extractReleaseDate(json['releases'], 4) : null;

    return SeerrMediaDetails(
      id: json['id'] as int? ?? 0,
      mediaType: mediaType,
      title: title,
      overview: json['overview']?.toString(),
      posterPath: json['posterPath']?.toString(),
      backdropPath: json['backdropPath']?.toString(),
      releaseDate: json['releaseDate']?.toString() ?? json['firstAirDate']?.toString(),
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      genres: genreList,
      runtime: json['runtime'] as int?,
      mediaStatus: mediaInfoStatus,
      mediaStatus4k: mediaInfoStatus4k,
      ratingKey: ratingKey,
      jellyfinMediaId: jellyfinMediaId,
      has4kRequest: has4k,
      hasStandardRequest: hasStd,
      seasons: seasonList,
      relatedVideos: videoList,
      firstAirDate: firstAirDate,
      theatricalReleaseDate: theatricalReleaseDate,
      digitalReleaseDate: digitalReleaseDate,
    );
  }
}

class SeerrVideo {
  final String? url;
  final String? key;
  final String? name;
  final String? site;
  final String? type;
  final bool official;

  SeerrVideo({
    this.url,
    this.key,
    this.name,
    this.site,
    this.type,
    this.official = false,
  });

  factory SeerrVideo.fromJson(Map<String, dynamic> json) {
    return SeerrVideo(
      url: json['url']?.toString(),
      key: json['key']?.toString(),
      name: json['name']?.toString(),
      site: json['site']?.toString(),
      type: json['type']?.toString(),
      official: json['official'] == true,
    );
  }

  bool get isTrailer {
    final t = type?.toLowerCase() ?? '';
    return t == 'trailer' || t == 'teaser';
  }

  bool get isYouTube =>
      site?.toLowerCase() == 'youtube' ||
      (url != null && (url!.contains('youtube.com') || url!.contains('youtu.be')));

  String? get youtubeKey {
    if (key != null && key!.isNotEmpty && (site == null || site!.toLowerCase() == 'youtube')) {
      return key;
    }
    if (url != null && url!.isNotEmpty) {
      final uri = Uri.tryParse(url!);
      if (uri != null) {
        if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
          return uri.pathSegments.first;
        }
        final v = uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  String? get videoUrl {
    if (url != null && url!.isNotEmpty) return url;
    if (site?.toLowerCase() == 'youtube' && key != null && key!.isNotEmpty) {
      return 'https://www.youtube.com/watch?v=$key';
    }
    return null;
  }

  String? get youtubeUrl => videoUrl;
}
