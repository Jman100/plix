import 'package:intl/intl.dart';

class PlexSubtitleStream {
  final String id;
  final String key;
  final String codec; // srt, vtt, pgs, ass, subrip
  final String language;
  final String languageCode;
  final String displayTitle;
  final bool isSelected;
  final bool isForced;
  final int streamIndex; // 0-based index among subtitle streams in the media file

  const PlexSubtitleStream({
    required this.id,
    required this.key,
    required this.codec,
    required this.language,
    required this.languageCode,
    required this.displayTitle,
    this.isSelected = false,
    this.isForced = false,
    this.streamIndex = 0,
  });

  factory PlexSubtitleStream.fromJson(Map<String, dynamic> json, {int streamIndex = 0}) {
    return PlexSubtitleStream(
      id: json['id']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      codec: json['codec']?.toString().toLowerCase() ?? 'srt',
      language: json['language']?.toString() ?? 'Unknown',
      languageCode: json['languageCode']?.toString() ?? '',
      displayTitle: json['displayTitle']?.toString() ??
          json['extendedDisplayTitle']?.toString() ??
          'Subtitle (${json['codec'] ?? 'srt'})',
      isSelected: json['selected'] == 1 || json['selected'] == true,
      isForced: json['forced'] == 1 || json['forced'] == true,
      streamIndex: streamIndex,
    );
  }

  bool get isBitmapSubtitle {
    final c = codec.toLowerCase();
    return c == 'vobsub' ||
        c == 'dvd_subtitle' ||
        c == 'dvdsub' ||
        c == 'pgs' ||
        c == 'hdmv_pgs_subtitle' ||
        c == 'sub';
  }
}

class PlexAudioStream {
  final String id;
  final String codec;
  final int? channels;
  final String language;
  final String languageCode;
  final String displayTitle;
  final bool isSelected;
  final int streamIndex;

  const PlexAudioStream({
    required this.id,
    required this.codec,
    this.channels,
    required this.language,
    required this.languageCode,
    required this.displayTitle,
    this.isSelected = false,
    this.streamIndex = 0,
  });

  factory PlexAudioStream.fromJson(Map<String, dynamic> json, {int streamIndex = 0}) {
    final codec = json['codec']?.toString().toLowerCase() ?? '';
    final channels = json['channels'] as int?;
    final title = json['displayTitle']?.toString() ??
        json['extendedDisplayTitle']?.toString() ??
        json['title']?.toString() ??
        'Audio Track ${streamIndex + 1}';

    return PlexAudioStream(
      id: json['id']?.toString() ?? '',
      codec: codec,
      channels: channels,
      language: json['language']?.toString() ?? 'Unknown',
      languageCode: json['languageCode']?.toString() ?? '',
      displayTitle: title,
      isSelected: json['selected'] == 1 || json['selected'] == true,
      streamIndex: streamIndex,
    );
  }
}

class PlexMarker {
  final int id;
  final String type; // e.g. "intro", "credits"
  final int startTimeOffset;
  final int endTimeOffset;

  const PlexMarker({
    required this.id,
    required this.type,
    required this.startTimeOffset,
    required this.endTimeOffset,
  });

  bool get isIntro => type.toLowerCase() == 'intro';

  factory PlexMarker.fromJson(Map<String, dynamic> json) {
    return PlexMarker(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      type: json['type']?.toString() ?? '',
      startTimeOffset: (json['startTimeOffset'] is num)
          ? (json['startTimeOffset'] as num).toInt()
          : int.tryParse(json['startTimeOffset']?.toString() ?? '0') ?? 0,
      endTimeOffset: (json['endTimeOffset'] is num)
          ? (json['endTimeOffset'] as num).toInt()
          : int.tryParse(json['endTimeOffset']?.toString() ?? '0') ?? 0,
    );
  }
}

class MediaPerson {
  final String id;
  final String name;
  final String role;
  final String type; // 'cast' or 'crew'
  final String? thumb;
  final String? summary;

  const MediaPerson({
    required this.id,
    required this.name,
    this.role = '',
    this.type = 'cast',
    this.thumb,
    this.summary,
  });

  bool get isCast => type == 'cast';

  factory MediaPerson.fromPlex(Map<String, dynamic> json, {String type = 'cast', String defaultRole = ''}) {
    final name = json['tag']?.toString() ?? json['title']?.toString() ?? '';
    final id = json['id']?.toString() ??
        json['tagKey']?.toString() ??
        json['ratingKey']?.toString() ??
        name;
    return MediaPerson(
      id: id,
      name: name,
      role: json['role']?.toString() ?? defaultRole,
      type: type,
      thumb: json['thumb']?.toString(),
      summary: json['summary']?.toString(),
    );
  }

  factory MediaPerson.fromJellyfin(Map<String, dynamic> json) {
    final id = json['Id']?.toString() ?? '';
    final imageTags = json['ImageTags'];
    final imageTag = json['PrimaryImageTag']?.toString() ??
        (imageTags is Map ? imageTags['Primary']?.toString() : null);
    final typeName = json['Type']?.toString().toLowerCase() ?? '';
    return MediaPerson(
      id: id,
      name: json['Name']?.toString() ?? '',
      role: json['Role']?.toString() ?? '',
      type: typeName == 'actor' ? 'cast' : 'crew',
      thumb: id.isNotEmpty
          ? '/Items/$id/Images/Primary${imageTag != null && imageTag.isNotEmpty ? '?tag=$imageTag' : ''}'
          : null,
      summary: json['Overview']?.toString(),
    );
  }
}

class PlexMediaItem {
  final String ratingKey;
  final String key;
  final String title;
  final String type; // 'movie', 'show', 'season', 'episode'
  final String summary;
  final int? year;
  final int? duration; // milliseconds
  final int? viewOffset; // milliseconds
  final String? thumb;
  final String? art;
  final String? theme; // TV Show theme audio path, e.g. /library/metadata/123/theme/456
  final String? grandparentTitle; // TV Show name
  final String? parentTitle; // Season name
  final String? grandparentThumb; // TV Show vertical poster
  final String? parentThumb; // Season vertical poster
  final String? grandparentRatingKey; // TV Show ID
  final String? parentRatingKey; // Season ID
  final int? parentIndex; // Season number
  final int? index; // Episode number
  final double? rating;
  final String? contentRating;
  final String? studio;
  final String? videoCodec;
  final String? audioCodec;
  final String? videoResolution;
  final int? audioChannels;
  final String? audioProfile;
  final String? audioTitle;
  final String? container;
  final String? partKey; // e.g. /library/parts/1234/file.mkv
  final String? partId;
  final int? viewCount;
  final int? bitrate; // kbps
  final String? videoProfile;
  final String? colorTrc;
  final String? colorPrimaries;
  final int? doviProfile;
  final String? doviTitle;
  final bool hasDynamicMetadata;
  final String? videoScanType;
  final String? videoFrameRate;
  final String? videoDisplayTitle;
  final String? videoExtendedDisplayTitle;
  final String? originallyAvailableAt; // e.g. "2021-10-12"
  final List<PlexSubtitleStream> subtitleStreams;
  final List<PlexAudioStream> audioStreams;
  final String? targetRatingKey;
  final String? targetType;
  final String? targetSeasonKey;
  final String? hdrType;
  final List<PlexMarker> markers;
  final String? guid;
  final String? grandparentGuid;
  final int? lastViewedAt;
  final String? subtype;
  final String? extraType;
  final String? addedSubtitle;
  final List<MediaPerson> people;

  const PlexMediaItem({
    required this.ratingKey,
    required this.key,
    required this.title,
    required this.type,
    this.summary = '',
    this.year,
    this.duration,
    this.viewOffset,
    this.thumb,
    this.art,
    this.theme,
    this.grandparentTitle,
    this.parentTitle,
    this.grandparentThumb,
    this.parentThumb,
    this.grandparentRatingKey,
    this.parentRatingKey,
    this.parentIndex,
    this.index,
    this.rating,
    this.contentRating,
    this.studio,
    this.videoCodec,
    this.audioCodec,
    this.videoResolution,
    this.videoScanType,
    this.videoFrameRate,
    this.videoDisplayTitle,
    this.videoExtendedDisplayTitle,
    this.audioChannels,
    this.audioProfile,
    this.audioTitle,
    this.container,
    this.partKey,
    this.partId,
    this.viewCount,
    this.bitrate,
    this.videoProfile,
    this.colorTrc,
    this.colorPrimaries,
    this.doviProfile,
    this.doviTitle,
    this.hasDynamicMetadata = false,
    this.originallyAvailableAt,
    this.subtitleStreams = const [],
    this.audioStreams = const [],
    this.targetRatingKey,
    this.targetType,
    this.targetSeasonKey,
    this.hdrType,
    this.markers = const [],
    this.guid,
    this.grandparentGuid,
    this.lastViewedAt,
    this.subtype,
    this.extraType,
    this.addedSubtitle,
    this.people = const [],
  });

  bool get isMovie => type == 'movie';
  bool get isShow => type == 'show' || type == 'series';
  bool get isEpisode => type == 'episode';
  bool get isSeason => type == 'season';
  bool get isTrailer =>
      subtype?.toLowerCase() == 'trailer' ||
      extraType == '1' ||
      (type == 'clip' && title.toLowerCase().contains('trailer'));
  PlexMarker? get introMarker => markers.where((m) => m.isIntro).firstOrNull;

  bool get isWatched => (viewCount ?? 0) > 0;
  bool get isInProgress => (viewOffset ?? 0) > 0;

  /// Returns the vertical poster image path:
  /// For TV episodes and seasons, prioritizes the show's vertical poster
  /// (grandparentThumb) so TV shows display their show poster instead of 16:9 episode screenshots!
  String? get posterThumb {
    if (isEpisode) {
      return grandparentThumb ?? parentThumb ?? thumb ?? art;
    }
    if (isSeason) {
      return parentThumb ?? grandparentThumb ?? thumb ?? art;
    }
    return thumb ?? art;
  }

  bool get isHdr {
    final hType = hdrType?.toLowerCase() ?? '';
    if (hType.isNotEmpty && hType != 'sdr') return true;
    final trc = colorTrc?.toLowerCase() ?? '';
    final prof = videoProfile?.toLowerCase() ?? '';
    final prim = colorPrimaries?.toLowerCase() ?? '';
    final dov = doviTitle?.toLowerCase() ?? '';
    final disp = videoDisplayTitle?.toLowerCase() ?? '';
    final extDisp = videoExtendedDisplayTitle?.toLowerCase() ?? '';
    final res = videoResolution?.toLowerCase() ?? '';
    return trc.contains('smpte2084') ||
        trc.contains('arib') ||
        trc.contains('2084') ||
        trc.contains('2094') ||
        trc.contains('hlg') ||
        prof.contains('hdr') ||
        prof.contains('dovi') ||
        dov.contains('dolby') ||
        dov.contains('hdr10') ||
        disp.contains('hdr') ||
        disp.contains('dovi') ||
        extDisp.contains('hdr') ||
        hasDynamicMetadata ||
        prim.contains('2020') ||
        doviProfile != null ||
        ((prof.contains('main 10') || prof.contains('high 10')) && (res == '4k' || res == '2160' || res == 'uhd'));
  }

  String get hdrBadge {
    final hType = hdrType?.toLowerCase() ?? '';
    final trc = colorTrc?.toLowerCase() ?? '';
    final prof = videoProfile?.toLowerCase() ?? '';
    final dov = doviTitle?.toLowerCase() ?? '';
    final disp = videoDisplayTitle?.toLowerCase() ?? '';
    final extDisp = videoExtendedDisplayTitle?.toLowerCase() ?? '';
    final pKey = partKey?.toLowerCase() ?? '';

    final allText = '$hType $trc $prof $dov $disp $extDisp $pKey';

    // 1. Dolby Vision (Highest HDR format)
    if (doviProfile != null ||
        allText.contains('dovi') ||
        allText.contains('dolby vision') ||
        allText.contains('dolbyvision') ||
        allText.contains('dolby') ||
        allText.contains('dvhe') ||
        allText.contains('dvh1')) {
      return 'Dolby Vision';
    }

    // 2. HDR10+ (Second highest format: Dynamic metadata, SMPTE 2094, HDR10+ profiles/titles)
    if (hasDynamicMetadata ||
        allText.contains('hdr10+') ||
        allText.contains('hdr10plus') ||
        allText.contains('hdr10 plus') ||
        allText.contains('hdr 10+') ||
        allText.contains('hdr 10 plus') ||
        allText.contains('hdr10-plus') ||
        allText.contains('hdr-10+') ||
        allText.contains('hdr10.plus') ||
        allText.contains('hdr10_plus') ||
        allText.contains('2094') ||
        allText.contains('smpte2094') ||
        allText.contains('smpte 2094')) {
      return 'HDR10+';
    }

    // 3. HLG
    if (allText.contains('hlg') ||
        allText.contains('arib') ||
        allText.contains('b67')) {
      return 'HLG';
    }

    // 4. HDR10
    if (allText.contains('hdr10') ||
        allText.contains('hdr 10') ||
        allText.contains('hdr-10') ||
        allText.contains('smpte2084') ||
        allText.contains('smpte 2084') ||
        allText.contains('2084')) {
      return 'HDR10';
    }

    // 5. Generic HDR defaults to HDR10
    if (isHdr) {
      return 'HDR10';
    }

    return '';
  }

  bool get isInterlaced {
    final scan = videoScanType?.toLowerCase().trim() ?? '';
    if (scan == 'interlaced' || scan == 'i') return true;
    if (scan == 'progressive' || scan == 'p') return false;

    final rate = videoFrameRate?.toLowerCase().trim() ?? '';
    if (rate.contains('i') && !rate.contains('fps')) return true;
    if (RegExp(r'\d+i').hasMatch(rate)) return true;

    final res = videoResolution?.toLowerCase().trim() ?? '';
    if (res.endsWith('i')) return true;

    final disp = '${videoDisplayTitle ?? ''} ${videoExtendedDisplayTitle ?? ''}'.toLowerCase();
    if (disp.contains('interlaced') ||
        disp.contains('1080i') ||
        disp.contains('720i') ||
        disp.contains('480i') ||
        disp.contains('576i')) {
      return true;
    }
    return false;
  }

  String get formattedResolution {
    final r = videoResolution?.toLowerCase().trim() ?? '';
    if (r.isEmpty) return '';

    // Determine scan type: progressive ('p') or interlaced ('i')
    final scan = isInterlaced ? 'i' : 'p';

    if (r == '4k' || r == '2160' || r == '2160p') return '4K';
    if (r == '1080' || r == '1080p' || r == '1080i') return '1080$scan';
    if (r == '720' || r == '720p' || r == '720i') return '720$scan';
    if (r == '480' || r == '480p' || r == '480i' || r == 'sd') return '480$scan';
    if (r == '576' || r == '576p' || r == '576i') return '576$scan';

    if (RegExp(r'^\d+$').hasMatch(r)) {
      return '$r$scan';
    }
    if (RegExp(r'^\d+[pi]$').hasMatch(r)) {
      final numPart = r.substring(0, r.length - 1);
      return '$numPart$scan';
    }
    return r.toUpperCase();
  }

  String get formattedBitrate {
    if (bitrate == null || bitrate == 0) return '';
    if (bitrate! >= 1000) {
      return '${(bitrate! / 1000).toStringAsFixed(1)} Mbps';
    }
    return '$bitrate kbps';
  }

  String get formattedAirDate {
    if (originallyAvailableAt != null && originallyAvailableAt!.isNotEmpty) {
      try {
        final date = DateTime.parse(originallyAvailableAt!);
        return DateFormat('MMM d, yyyy').format(date);
      } catch (_) {
        return originallyAvailableAt!;
      }
    }
    if (year != null && year! > 0) {
      return '$year';
    }
    return '';
  }

  double get progressPercentage {
    if (duration == null || duration == 0 || viewOffset == null) return 0.0;
    return (viewOffset! / duration!).clamp(0.0, 1.0);
  }

  String get displayTitle {
    if (isEpisode) {
      final s = parentIndex != null ? 'S$parentIndex' : '';
      final e = index != null ? 'E$index' : '';
      final prefix = [s, e].where((element) => element.isNotEmpty).join('·');
      if (prefix.isNotEmpty) {
        return '$prefix - $title';
      }
    }
    return title;
  }

  String get cardTitle {
    if (addedSubtitle != null) {
      return title;
    }
    return displayTitle;
  }

  String get cardSubtitle {
    if (addedSubtitle != null) {
      return addedSubtitle!;
    }
    if (grandparentTitle != null && grandparentTitle!.isNotEmpty) {
      return grandparentTitle!;
    }
    if (year != null && year! > 0) {
      return '$year';
    }
    return '';
  }

  String get formattedDuration {
    if (duration == null || duration! <= 0) return '';
    final totalMinutes = (duration! / (1000 * 60)).round();
    if (totalMinutes <= 0) return '';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${hours}h';
    }
    return '${minutes}m';
  }

  String get formattedAudio {
    if ((audioCodec == null || audioCodec!.isEmpty) &&
        (audioTitle == null || audioTitle!.isEmpty)) {
      return '';
    }
    final codecUpper = audioCodec?.toUpperCase() ?? '';
    String displayCodec = codecUpper;
    if (codecUpper == 'EAC3') {
      displayCodec = 'E-AC3';
    } else if (codecUpper == 'AC3') {
      displayCodec = 'AC3';
    } else if (codecUpper == 'TRUEHD') {
      displayCodec = 'TrueHD';
    } else if (codecUpper == 'DCA' || codecUpper == 'DTS') {
      displayCodec = 'DTS';
    } else if (codecUpper.contains('DTS-HD') || codecUpper.contains('DTSHD')) {
      displayCodec = 'DTS-HD';
    } else if (codecUpper == 'AAC') {
      displayCodec = 'AAC';
    } else if (codecUpper == 'OPUS') {
      displayCodec = 'Opus';
    } else if (codecUpper == 'FLAC') {
      displayCodec = 'FLAC';
    }

    String channels = '';
    if (audioChannels != null) {
      if (audioChannels == 8) {
        channels = ' 7.1';
      } else if (audioChannels == 6) {
        channels = ' 5.1';
      } else if (audioChannels == 2) {
        channels = ' Stereo';
      } else if (audioChannels == 1) {
        channels = ' Mono';
      } else {
        channels = ' ${audioChannels}ch';
      }
    }
    return '$displayCodec$channels'.trim();
  }

  factory PlexMediaItem.fromJson(Map<String, dynamic> json) {
    String? vCodec;
    String? aCodec;
    String? vRes;
    String? vScan = json['videoScanType']?.toString() ?? json['scanType']?.toString();
    String? vFrameRate = json['videoFrameRate']?.toString();
    String? vDispTitle;
    String? vExtDispTitle;
    int? aChannels;
    String? aProf;
    String? aTitle;
    String? cont;
    String? pKey;
    String? pId;
    int? bRate;
    String? vProf;
    String? colTrc;
    String? colPrim;
    int? dovProf;
    String? dovTitle;
    bool hasDynamic = false;
    String? hType = json['hdrType']?.toString();
    final List<PlexMarker> markers = [];
    final rawMarkers = json['Marker'];
    final markerList = rawMarkers is List ? rawMarkers : (rawMarkers is Map ? [rawMarkers] : null);
    if (markerList != null) {
      for (final m in markerList) {
        if (m is Map<String, dynamic>) {
          markers.add(PlexMarker.fromJson(m));
        }
      }
    }
    if (json['hasDynamicMetadata'] == '1' || json['hasDynamicMetadata'] == 1 || json['hasDynamicMetadata'] == true) {
      hasDynamic = true;
    }
    final jsonTitleCheck = '${json['displayTitle'] ?? ''} ${json['extendedDisplayTitle'] ?? ''} ${json['title'] ?? ''}'.toLowerCase();
    if (jsonTitleCheck.contains('hdr10+') || jsonTitleCheck.contains('hdr10plus') || jsonTitleCheck.contains('2094')) {
      hasDynamic = true;
    }
    final List<PlexSubtitleStream> subs = [];
    final List<PlexAudioStream> audios = [];

    final rawMedia = json['Media'];
    final mediaList = rawMedia is List ? rawMedia : (rawMedia is Map ? [rawMedia] : null);
    if (mediaList != null && mediaList.isNotEmpty) {
      final firstMedia = mediaList.first is Map<String, dynamic>
          ? mediaList.first as Map<String, dynamic>
          : <String, dynamic>{};
      vCodec = firstMedia['videoCodec'] as String?;
      aCodec = firstMedia['audioCodec'] as String?;
      vRes = firstMedia['videoResolution']?.toString();
      vScan ??= firstMedia['videoScanType']?.toString() ?? firstMedia['scanType']?.toString();
      vFrameRate ??= firstMedia['videoFrameRate']?.toString();
      vDispTitle ??= firstMedia['displayTitle'] as String? ?? json['displayTitle'] as String?;
      vExtDispTitle ??= firstMedia['extendedDisplayTitle'] as String? ?? json['extendedDisplayTitle'] as String?;
      colTrc ??= firstMedia['colorTrc'] as String? ?? json['colorTrc'] as String?;
      colPrim ??= firstMedia['colorPrimaries'] as String? ?? json['colorPrimaries'] as String?;
      final colSpace = firstMedia['colorSpace'] as String? ?? json['colorSpace'] as String?;
      if (colSpace != null && colSpace.toLowerCase().contains('2020')) {
        colPrim ??= colSpace;
      }
      dovProf ??= (firstMedia['DOVIProfile'] is num)
          ? (firstMedia['DOVIProfile'] as num).toInt()
          : (firstMedia['doviProfile'] is num)
              ? (firstMedia['doviProfile'] as num).toInt()
              : int.tryParse(firstMedia['DOVIProfile']?.toString() ?? firstMedia['doviProfile']?.toString() ?? '');
      if (firstMedia['DOVIPresent'] == true ||
          firstMedia['DOVIPresent'] == 'true' ||
          firstMedia['DOVIPresent'] == 1 ||
          firstMedia['DOVIPresent'] == '1' ||
          firstMedia['doviPresent'] == true ||
          firstMedia['doviPresent'] == 'true' ||
          firstMedia['doviPresent'] == 1 ||
          firstMedia['doviPresent'] == '1') {
        dovProf ??= 0;
      }
      hType ??= firstMedia['hdrType']?.toString() ?? firstMedia['hdr']?.toString();
      dovTitle ??= firstMedia['DOVITitle'] as String? ?? firstMedia['doviTitle'] as String?;
      aChannels = (firstMedia['audioChannels'] is num)
          ? (firstMedia['audioChannels'] as num).toInt()
          : int.tryParse(firstMedia['audioChannels']?.toString() ?? '');
      cont = firstMedia['container'] as String?;
      bRate = (firstMedia['bitrate'] is num)
          ? (firstMedia['bitrate'] as num).toInt()
          : int.tryParse(firstMedia['bitrate']?.toString() ?? '');
      vProf = firstMedia['videoProfile'] as String? ?? firstMedia['profile'] as String? ?? json['videoProfile'] as String?;

      // Scan all Media, Part, and Stream entries for highest HDR format detection
      bool checkIsHdr10Plus(String text) {
        final t = text.toLowerCase();
        return t.contains('hdr10+') ||
            t.contains('hdr10plus') ||
            t.contains('hdr10 plus') ||
            t.contains('hdr 10+') ||
            t.contains('hdr 10 plus') ||
            t.contains('hdr10-plus') ||
            t.contains('hdr-10+') ||
            t.contains('hdr10.plus') ||
            t.contains('hdr10_plus') ||
            t.contains('2094') ||
            t.contains('smpte2094') ||
            t.contains('smpte 2094');
      }

      bool checkIsDovi(String text) {
        final t = text.toLowerCase();
        return t.contains('dovi') ||
            t.contains('dolby vision') ||
            t.contains('dolbyvision') ||
            t.contains('dolby') ||
            t.contains('dvhe') ||
            t.contains('dvh1');
      }

      for (final m in mediaList) {
        if (m is! Map<String, dynamic>) continue;
        final mDynamic = m['hasDynamicMetadata'] == '1' ||
            m['hasDynamicMetadata'] == 1 ||
            m['hasDynamicMetadata'] == true ||
            m['hasDynamicMetadata'] == 'true' ||
            m['dynamicMetadata'] == '1' ||
            m['dynamicMetadata'] == 1 ||
            m['dynamicMetadata'] == true ||
            m['dynamicMetadata'] == 'true';
        if (mDynamic) hasDynamic = true;

        final mText = '${m['displayTitle'] ?? ''} ${m['extendedDisplayTitle'] ?? ''} ${m['hdrType'] ?? ''} ${m['hdr'] ?? ''} ${m['dynamicRange'] ?? ''} ${m['videoProfile'] ?? ''} ${m['profile'] ?? ''}'.toLowerCase();
        if (checkIsHdr10Plus(mText)) hasDynamic = true;
        if (checkIsDovi(mText) || m['DOVIProfile'] != null || m['doviProfile'] != null || m['DOVIPresent'] == true || m['DOVIPresent'] == 'true' || m['DOVIPresent'] == 1 || m['DOVIPresent'] == '1') {
          dovProf ??= 0;
        }

        final rawParts = m['Part'];
        final parts = rawParts is List ? rawParts : (rawParts is Map ? [rawParts] : null);
        if (parts != null) {
          for (final p in parts) {
            if (p is! Map<String, dynamic>) continue;
            pKey ??= p['key'] as String?;
            pId ??= p['id']?.toString();
            final fStr = (p['file'] ?? '').toString().toLowerCase();
            if (checkIsHdr10Plus(fStr)) hasDynamic = true;
            if (checkIsDovi(fStr)) dovProf ??= 0;

            final rawStreams = p['Stream'];
            final streams = rawStreams is List ? rawStreams : (rawStreams is Map ? [rawStreams] : null);
            if (streams != null) {
              int subIdx = subs.length;
              int audioIdx = audios.length;
              for (final s in streams) {
                if (s is! Map<String, dynamic>) continue;
                final stMap = s;
                final streamType = (stMap['streamType'] is num)
                    ? (stMap['streamType'] as num).toInt()
                    : int.tryParse(stMap['streamType']?.toString() ?? '');
                if (streamType == 1) {
                  colTrc ??= stMap['colorTrc'] as String?;
                  colPrim ??= stMap['colorPrimaries'] as String?;
                  final stDovProf = (stMap['DOVIProfile'] is num)
                      ? (stMap['DOVIProfile'] as num).toInt()
                      : (stMap['doviProfile'] is num)
                          ? (stMap['doviProfile'] as num).toInt()
                          : int.tryParse(stMap['DOVIProfile']?.toString() ?? stMap['doviProfile']?.toString() ?? '');
                  if (stDovProf != null) dovProf = stDovProf;
                  if (stMap['DOVIPresent'] == true ||
                      stMap['DOVIPresent'] == 'true' ||
                      stMap['DOVIPresent'] == 1 ||
                      stMap['DOVIPresent'] == '1' ||
                      stMap['doviPresent'] == true ||
                      stMap['doviPresent'] == 'true' ||
                      stMap['doviPresent'] == 1 ||
                      stMap['doviPresent'] == '1') {
                    dovProf ??= 0;
                  }
                  dovTitle ??= stMap['DOVITitle'] as String? ?? stMap['doviTitle'] as String?;
                  vScan ??= stMap['scanType']?.toString() ?? stMap['videoScanType']?.toString();
                  vFrameRate ??= stMap['videoFrameRate']?.toString();
                  vDispTitle ??= stMap['displayTitle'] as String?;
                  vExtDispTitle ??= stMap['extendedDisplayTitle'] as String?;
                  hType ??= stMap['hdrType']?.toString();

                  final sDynamic = stMap['hasDynamicMetadata'] == '1' ||
                      stMap['hasDynamicMetadata'] == 1 ||
                      stMap['hasDynamicMetadata'] == true ||
                      stMap['hasDynamicMetadata'] == 'true' ||
                      stMap['dynamicMetadata'] == '1' ||
                      stMap['dynamicMetadata'] == 1 ||
                      stMap['dynamicMetadata'] == true ||
                      stMap['dynamicMetadata'] == 'true';
                  if (sDynamic) hasDynamic = true;

                  final sText = '${stMap['displayTitle'] ?? ''} ${stMap['extendedDisplayTitle'] ?? ''} ${stMap['hdrType'] ?? ''} ${stMap['profile'] ?? ''} ${stMap['colorTrc'] ?? ''}'.toLowerCase();
                  if (checkIsHdr10Plus(sText)) hasDynamic = true;
                  if (checkIsDovi(sText)) dovProf ??= 0;

                  if (bRate == null && stMap['bitrate'] != null) {
                    bRate = (stMap['bitrate'] is num)
                        ? (stMap['bitrate'] as num).toInt()
                        : int.tryParse(stMap['bitrate']?.toString() ?? '');
                  }
                } else if (streamType == 2 && audios.isEmpty) {
                  audios.add(PlexAudioStream.fromJson(stMap, streamIndex: audioIdx));
                  audioIdx++;
                  if (aCodec == null || stMap['selected'] == 1 || stMap['selected'] == true) {
                    aCodec = stMap['codec'] as String?;
                    aChannels = (stMap['channels'] is num)
                        ? (stMap['channels'] as num).toInt()
                        : int.tryParse(stMap['channels']?.toString() ?? '');
                    aProf = stMap['profile'] as String? ?? stMap['audioChannelLayout'] as String?;
                    aTitle = stMap['displayTitle'] as String? ?? stMap['extendedDisplayTitle'] as String?;
                  }
                } else if (streamType == 3 && subs.isEmpty) {
                  subs.add(PlexSubtitleStream.fromJson(stMap, streamIndex: subIdx));
                  subIdx++;
                }
              }
            }
          }
        }
      }
    }

    String? parsedGuid = json['guid']?.toString();
    if (parsedGuid == null || !parsedGuid.contains('plex://')) {
      final rawGuid = json['Guid'];
      final guidList = rawGuid is List ? rawGuid : (rawGuid is Map ? [rawGuid] : null);
      if (guidList != null) {
        for (final g in guidList) {
          if (g is Map<String, dynamic>) {
            final id = g['id']?.toString() ?? '';
            if (id.contains('plex://')) {
              parsedGuid = id;
              break;
            }
          }
        }
      }
    }

    final people = <MediaPerson>[];
    void addPeople(dynamic raw, String type, String defaultRole) {
      final list = raw is List ? raw : (raw is Map ? [raw] : null);
      if (list == null) return;
      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final person = MediaPerson.fromPlex(entry, type: type, defaultRole: defaultRole);
          if (person.name.isNotEmpty &&
              !people.any((p) => p.name == person.name && p.role == person.role)) {
            people.add(person);
          }
        }
      }
    }
    addPeople(json['Role'], 'cast', '');
    addPeople(json['Director'], 'crew', 'Director');
    addPeople(json['Writer'], 'crew', 'Writer');

    final parsedRatingKey = json['ratingKey']?.toString() ?? json['id']?.toString() ?? '';
    final parsedKey = json['key']?.toString() ?? (parsedRatingKey.isNotEmpty ? '/library/metadata/$parsedRatingKey' : '');

    return PlexMediaItem(
      ratingKey: parsedRatingKey,
      key: parsedKey,
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'movie',
      summary: json['summary'] as String? ?? '',
      year: (json['year'] is num)
          ? (json['year'] as num).toInt()
          : int.tryParse(json['year']?.toString() ?? ''),
      duration: (json['duration'] is num)
          ? (json['duration'] as num).toInt()
          : int.tryParse(json['duration']?.toString() ?? ''),
      viewOffset: (json['viewOffset'] is num)
          ? (json['viewOffset'] as num).toInt()
          : int.tryParse(json['viewOffset']?.toString() ?? ''),
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      theme: (json['theme'] as String?) ?? (json['grandparentTheme'] as String?),
      grandparentTitle: json['grandparentTitle'] as String?,
      parentTitle: json['parentTitle'] as String?,
      grandparentThumb: json['grandparentThumb'] as String?,
      parentThumb: json['parentThumb'] as String?,
      grandparentRatingKey: json['grandparentRatingKey']?.toString(),
      parentRatingKey: json['parentRatingKey']?.toString(),
      parentIndex: (json['parentIndex'] is num)
          ? (json['parentIndex'] as num).toInt()
          : int.tryParse(json['parentIndex']?.toString() ?? ''),
      index: (json['index'] is num)
          ? (json['index'] as num).toInt()
          : int.tryParse(json['index']?.toString() ?? ''),
      rating: (json['rating'] is num)
          ? (json['rating'] as num).toDouble()
          : double.tryParse(json['rating']?.toString() ?? ''),
      contentRating: json['contentRating']?.toString(),
      studio: json['studio'] as String?,
      videoCodec: vCodec,
      audioCodec: aCodec,
      videoResolution: vRes,
      videoScanType: vScan,
      videoFrameRate: vFrameRate,
      videoDisplayTitle: vDispTitle,
      videoExtendedDisplayTitle: vExtDispTitle,
      audioChannels: aChannels,
      audioProfile: aProf,
      audioTitle: aTitle,
      container: cont,
      partKey: pKey,
      partId: pId,
      viewCount: (json['viewCount'] is num)
          ? (json['viewCount'] as num).toInt()
          : int.tryParse(json['viewCount']?.toString() ?? ''),
      bitrate: bRate ??
          ((json['bitrate'] is num)
              ? (json['bitrate'] as num).toInt()
              : int.tryParse(json['bitrate']?.toString() ?? '')),
      videoProfile: vProf,
      colorTrc: colTrc,
      colorPrimaries: colPrim,
      doviProfile: dovProf,
      doviTitle: dovTitle,
      hasDynamicMetadata: hasDynamic,
      originallyAvailableAt: json['originallyAvailableAt'] as String?,
      subtitleStreams: subs,
      audioStreams: audios,
      hdrType: hType,
      markers: markers,
      guid: parsedGuid,
      grandparentGuid: json['grandparentGuid']?.toString(),
      subtype: json['subtype']?.toString(),
      extraType: json['extraType']?.toString(),
      lastViewedAt: (json['lastViewedAt'] is num)
          ? (json['lastViewedAt'] as num).toInt()
          : (json['viewedAt'] is num)
              ? (json['viewedAt'] as num).toInt()
              : int.tryParse(json['lastViewedAt']?.toString() ?? json['viewedAt']?.toString() ?? ''),
      people: people,
    );
  }

  PlexMediaItem copyWith({
    String? ratingKey,
    String? title,
    String? type,
    int? viewOffset,
    int? viewCount,
    String? thumb,
    String? art,
    String? theme,
    String? grandparentThumb,
    String? parentThumb,
    String? grandparentTitle,
    String? grandparentRatingKey,
    String? audioCodec,
    int? audioChannels,
    String? audioProfile,
    String? audioTitle,
    String? partKey,
    List<PlexSubtitleStream>? subtitleStreams,
    List<PlexAudioStream>? audioStreams,
    String? targetRatingKey,
    String? targetType,
    String? targetSeasonKey,
    String? videoScanType,
    String? videoFrameRate,
    String? videoDisplayTitle,
    String? videoExtendedDisplayTitle,
    String? hdrType,
    List<PlexMarker>? markers,
    String? guid,
    String? grandparentGuid,
    int? lastViewedAt,
    String? subtype,
    String? extraType,
    String? addedSubtitle,
    List<MediaPerson>? people,
  }) {
    return PlexMediaItem(
      ratingKey: ratingKey ?? this.ratingKey,
      key: key,
      title: title ?? this.title,
      type: type ?? this.type,
      summary: summary,
      year: year,
      duration: duration,
      viewOffset: viewOffset ?? this.viewOffset,
      thumb: thumb ?? this.thumb,
      art: art ?? this.art,
      theme: theme ?? this.theme,
      grandparentTitle: grandparentTitle ?? this.grandparentTitle,
      parentTitle: parentTitle,
      grandparentThumb: grandparentThumb ?? this.grandparentThumb,
      parentThumb: parentThumb ?? this.parentThumb,
      grandparentRatingKey: grandparentRatingKey ?? this.grandparentRatingKey,
      parentRatingKey: parentRatingKey,
      parentIndex: parentIndex,
      index: index,
      rating: rating,
      contentRating: contentRating,
      studio: studio,
      videoCodec: videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      videoResolution: videoResolution,
      videoScanType: videoScanType ?? this.videoScanType,
      videoFrameRate: videoFrameRate ?? this.videoFrameRate,
      videoDisplayTitle: videoDisplayTitle ?? this.videoDisplayTitle,
      videoExtendedDisplayTitle: videoExtendedDisplayTitle ?? this.videoExtendedDisplayTitle,
      audioChannels: audioChannels ?? this.audioChannels,
      audioProfile: audioProfile ?? this.audioProfile,
      audioTitle: audioTitle ?? this.audioTitle,
      container: container,
      partKey: partKey ?? this.partKey,
      partId: partId,
      viewCount: viewCount ?? this.viewCount,
      bitrate: bitrate,
      videoProfile: videoProfile,
      colorTrc: colorTrc,
      colorPrimaries: colorPrimaries,
      doviProfile: doviProfile,
      doviTitle: doviTitle,
      hasDynamicMetadata: hasDynamicMetadata,
      originallyAvailableAt: originallyAvailableAt,
      hdrType: hdrType ?? this.hdrType,
      markers: markers ?? this.markers,
      subtitleStreams: subtitleStreams ?? this.subtitleStreams,
      audioStreams: audioStreams ?? this.audioStreams,
      targetRatingKey: targetRatingKey ?? this.targetRatingKey,
      targetType: targetType ?? this.targetType,
      targetSeasonKey: targetSeasonKey ?? this.targetSeasonKey,
      guid: guid ?? this.guid,
      grandparentGuid: grandparentGuid ?? this.grandparentGuid,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      subtype: subtype ?? this.subtype,
      extraType: extraType ?? this.extraType,
      addedSubtitle: addedSubtitle ?? this.addedSubtitle,
      people: people ?? this.people,
    );
  }
}
