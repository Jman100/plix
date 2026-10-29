import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import 'jellyfin_auth_service.dart';
import 'plix_device_helper.dart';
import 'update_service.dart';

class JellyfinMediaService {
  final PlexServer server;

  JellyfinMediaService({required this.server});

  String get baseUrl => server.activeConnectionUri ?? (server.connections.isNotEmpty ? server.connections.first.uri : '');
  String get token => server.accessToken;
  String get userId => server.userId ?? '';

  Map<String, String> get _headers => {
    'Authorization': JellyfinAuthService.buildAuthHeader(
      clientId: server.clientIdentifier,
      clientName: PlixDeviceHelper.clientName,
      version: UpdateService.currentVersion,
      token: token,
      deviceName: PlixDeviceHelper.deviceName,
    ),
    'X-Emby-Token': token,
    'X-MediaBrowser-Token': token,
    'Accept': 'application/json',
  };

  static const String _itemFields =
      'Overview,PrimaryImageAspectRatio,MediaStreams,MediaSources,Chapters,OfficialRating,ProductionYear,Studios,ParentId,SeriesId,SeriesName,SeasonName,SeasonId,IndexNumber,ParentIndexNumber,People,Path';

  PlexLibrary _parseLibrary(Map<String, dynamic> json) {
    final id = json['Id']?.toString() ?? '';
    final name = json['Name']?.toString() ?? 'Library';
    final collectionType = json['CollectionType']?.toString().toLowerCase() ?? '';

    String type = 'movie';
    if (collectionType == 'tvshows' || collectionType == 'series') {
      type = 'show';
    } else if (collectionType == 'music') {
      type = 'artist';
    }

    return PlexLibrary(
      key: id,
      title: name,
      type: type,
    );
  }

  PlexMediaItem _parseItem(Map<String, dynamic> json) {
    final id = json['Id']?.toString() ?? '';
    final name = json['Name']?.toString() ?? '';
    final rawType = json['Type']?.toString().toLowerCase() ?? '';

    String type = 'movie';
    if (rawType == 'series') {
      type = 'show';
    } else if (rawType == 'season') {
      type = 'season';
    } else if (rawType == 'episode') {
      type = 'episode';
    }

    final userData = json['UserData'] as Map<String, dynamic>? ?? {};
    final runTimeTicks = json['RunTimeTicks'] as num?;
    final durationMs = runTimeTicks != null ? (runTimeTicks.toInt() ~/ 10000) : null;
    final positionTicks = userData['PlaybackPositionTicks'] as num?;
    final viewOffsetMs = positionTicks != null ? (positionTicks.toInt() ~/ 10000) : null;
    final isPlayed = userData['Played'] == true;

    // Subtitle & Audio streams
    List<dynamic> rawStreams = json['MediaStreams'] as List<dynamic>? ?? [];
    String? filePath = json['Path']?.toString();
    int? fileSize = (json['Size'] as num?)?.toInt();
    String? container = json['Container']?.toString();
    int? totalBitrate = (json['Bitrate'] as num?)?.toInt();
    if (json['MediaSources'] is List && (json['MediaSources'] as List).isNotEmpty) {
      final firstMs = (json['MediaSources'] as List).first;
      if (firstMs is Map<String, dynamic>) {
        filePath ??= firstMs['Path']?.toString();
        fileSize ??= (firstMs['Size'] as num?)?.toInt();
        container ??= firstMs['Container']?.toString();
        totalBitrate ??= (firstMs['Bitrate'] as num?)?.toInt();
      }
      if (rawStreams.isEmpty) {
        for (final ms in json['MediaSources'] as List) {
          if (ms is Map && ms['MediaStreams'] is List && (ms['MediaStreams'] as List).isNotEmpty) {
            rawStreams = ms['MediaStreams'] as List;
            break;
          }
        }
      }
    }
    final List<PlexSubtitleStream> subStreams = [];
    final List<PlexAudioStream> audStreams = [];

    String? videoCodec;
    String? audioCodec;
    String? resolutionStr;
    String? videoFrameRate;
    int? audioChannels;
    String? audioTitle;
    String? hdrType;
    String? videoProfile;
    String? colorTrc;
    String? colorPrimaries;
    String? doviTitle;

    int subIndex = 0;
    int audioIndex = 0;
    for (final s in rawStreams) {
      final streamMap = s as Map<String, dynamic>;
      final sType = streamMap['Type']?.toString().toLowerCase() ?? '';
      final sIndex = (streamMap['Index'] as num?)?.toInt() ?? 0;
      final codec = streamMap['Codec']?.toString().toLowerCase() ?? '';
      final lang = streamMap['Language']?.toString() ?? 'Unknown';
      final title = streamMap['DisplayTitle']?.toString() ?? streamMap['Title']?.toString() ?? codec.toUpperCase();
      final isDefault = streamMap['IsDefault'] == true;
      final isForced = streamMap['IsForced'] == true;

      if (sType == 'subtitle') {
        final deliveryUrl = streamMap['DeliveryUrl']?.toString() ?? '';
        subStreams.add(
          PlexSubtitleStream(
            id: sIndex.toString(),
            key: deliveryUrl.isNotEmpty ? deliveryUrl : '/Videos/$id/$id/Subtitles/$sIndex/Stream.$codec',
            codec: codec,
            language: lang,
            languageCode: lang,
            displayTitle: title,
            isSelected: isDefault,
            isForced: isForced,
            streamIndex: subIndex++,
          ),
        );
      } else if (sType == 'audio') {
        final channels = (streamMap['Channels'] as num?)?.toInt();
        audStreams.add(
          PlexAudioStream(
            id: sIndex.toString(),
            codec: codec,
            channels: channels,
            language: lang,
            languageCode: lang,
            displayTitle: title,
            isSelected: isDefault,
            streamIndex: audioIndex++,
          ),
        );
        audioCodec ??= codec;
        audioChannels ??= channels;
        audioTitle ??= title;
      } else if (sType == 'video') {
        videoCodec ??= codec;
        final w = (streamMap['Width'] as num?)?.toInt();
        final h = (streamMap['Height'] as num?)?.toInt();
        if (w != null || h != null) {
          final width = w ?? 0;
          final height = h ?? 0;
          if (width >= 3000 || height >= 1600) {
            resolutionStr = '4K';
          } else if (width >= 1800 || height >= 800) {
            resolutionStr = '1080p';
          } else if (width >= 1200 || height >= 540) {
            resolutionStr = '720p';
          } else if (width >= 640 || height >= 400) {
            resolutionStr = '480p';
          } else if (height > 0) {
            resolutionStr = '${height}p';
          }
        }
        final vProfile = streamMap['Profile']?.toString();
        videoFrameRate ??= streamMap['RealFrameRate']?.toString() ?? streamMap['AverageFrameRate']?.toString();
        final vRange = streamMap['VideoRange']?.toString() ?? '';
        final vRangeType = streamMap['VideoRangeType']?.toString() ?? '';
        final vDoVi = streamMap['VideoDoViTitle']?.toString() ?? '';
        final cTransfer = streamMap['ColorTransfer']?.toString();
        final cPrimaries = streamMap['ColorPrimaries']?.toString();

        videoProfile ??= vProfile;
        colorTrc ??= cTransfer;
        colorPrimaries ??= cPrimaries;
        if (vDoVi.isNotEmpty) {
          doviTitle ??= vDoVi;
        }

        final titleCheck = (streamMap['Title'] ?? streamMap['DisplayTitle'] ?? '').toString();
        final allVideoInfo = '$vRange $vRangeType $vDoVi ${cTransfer ?? ''} ${cPrimaries ?? ''} ${vProfile ?? ''} $titleCheck'.toLowerCase();
        if (allVideoInfo.contains('dovi') || allVideoInfo.contains('dolby') || vDoVi.isNotEmpty || allVideoInfo.contains('dvhe')) {
          hdrType = 'DOVI';
        } else if (allVideoInfo.contains('hdr10+') ||
            allVideoInfo.contains('hdr10plus') ||
            allVideoInfo.contains('hdr10 plus') ||
            allVideoInfo.contains('hdr 10+') ||
            allVideoInfo.contains('hdr 10 plus') ||
            allVideoInfo.contains('hdr10-plus') ||
            allVideoInfo.contains('hdr-10+') ||
            allVideoInfo.contains('hdr10.plus') ||
            allVideoInfo.contains('2094')) {
          if (hdrType != 'DOVI') hdrType = 'HDR10+';
        } else if (allVideoInfo.contains('hlg') || (cTransfer?.toLowerCase().contains('arib') ?? false)) {
          if (hdrType != 'DOVI' && hdrType != 'HDR10+') hdrType = 'HLG';
        } else if (allVideoInfo.contains('hdr10') || allVideoInfo.contains('hdr 10')) {
          if (hdrType != 'DOVI' && hdrType != 'HDR10+' && hdrType != 'HLG') hdrType = 'HDR10';
        } else if (allVideoInfo.contains('hdr') ||
            (cTransfer?.toLowerCase().contains('2084') ?? false) ||
            (cTransfer?.toLowerCase().contains('smpte2084') ?? false) ||
            (cPrimaries?.toLowerCase().contains('2020') ?? false)) {
          if (hdrType != 'DOVI' && hdrType != 'HDR10+' && hdrType != 'HLG') hdrType = 'HDR10';
        }
      }
    }

    final premiereDate = json['PremiereDate']?.toString();
    String? airDate;
    if (premiereDate != null && premiereDate.length >= 10) {
      airDate = premiereDate.substring(0, 10);
    }

    final seriesId = json['SeriesId']?.toString() ?? (type == 'season' ? json['ParentId']?.toString() : null);
    final seasonId = json['SeasonId']?.toString() ?? (type == 'episode' ? json['ParentId']?.toString() : null);
    final showPoster = seriesId != null ? '/Items/$seriesId/Images/Primary' : null;
    final seasonPoster = seasonId != null ? '/Items/$seasonId/Images/Primary' : null;
    final itemThumb = '/Items/$id/Images/Primary';

    final people = <MediaPerson>[];
    final rawPeople = json['People'] as List<dynamic>? ?? [];
    for (final rawPerson in rawPeople) {
      if (rawPerson is! Map<String, dynamic>) continue;
      final person = MediaPerson.fromJellyfin(rawPerson);
      if (person.name.isNotEmpty &&
          !people.any((p) => p.id == person.id && p.role == person.role)) {
        people.add(person);
      }
    }

    return PlexMediaItem(
      ratingKey: id,
      key: '/Items/$id',
      title: name,
      type: type,
      summary: json['Overview']?.toString() ?? '',
      year: json['ProductionYear'] as int?,
      duration: durationMs,
      viewOffset: viewOffsetMs,
      thumb: itemThumb,
      art: '/Items/${seriesId ?? id}/Images/Backdrop',
      grandparentTitle: json['SeriesName']?.toString(),
      parentTitle: json['SeasonName']?.toString(),
      grandparentRatingKey: seriesId,
      parentRatingKey: seasonId,
      grandparentThumb: showPoster,
      parentThumb: seasonPoster,
      parentIndex: json['ParentIndexNumber'] as int?,
      index: json['IndexNumber'] as int?,
      rating: (json['CommunityRating'] is num) ? (json['CommunityRating'] as num).toDouble() : null,
      contentRating: json['OfficialRating']?.toString(),
      studio: (json['Studios'] is List && (json['Studios'] as List).isNotEmpty) ? (json['Studios'] as List)[0]['Name']?.toString() : null,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      videoResolution: resolutionStr,
      audioChannels: audioChannels,
      audioTitle: audioTitle,
      partKey: '/Videos/$id/stream?static=true',
      viewCount: isPlayed ? 1 : 0,
      originallyAvailableAt: airDate,
      subtitleStreams: subStreams,
      audioStreams: audStreams,
      videoProfile: videoProfile,
      colorTrc: colorTrc,
      colorPrimaries: colorPrimaries,
      doviTitle: doviTitle,
      hasDynamicMetadata: hdrType == "HDR10+" || hdrType == "DOVI",
      hdrType: hdrType,
      people: people,
      container: container,
      bitrate: totalBitrate != null && totalBitrate > 0 ? totalBitrate ~/ 1000 : null,
      videoFrameRate: videoFrameRate,
      filePath: filePath,
      fileSize: fileSize,
    );
  }

  Future<List<PlexLibrary>> getLibraries() async {
    final url = Uri.parse('$baseUrl/Users/$userId/Views');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseLibrary(m as Map<String, dynamic>)).toList();
  }

  Future<PlexMediaItem?> getNextUpForShow(String showRatingKey) async {
    try {
      final cw = await getContinueWatching();
      for (final item in cw) {
        if (item.grandparentRatingKey == showRatingKey) {
          return item;
        }
      }
    } catch (_) {}

    try {
      final url = Uri.parse(
        '$baseUrl/Shows/NextUp?UserId=$userId&SeriesId=$showRatingKey&Fields=$_itemFields',
      );
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['Items'] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          return _parseItem(items.first as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<PlexMediaItem>> getContinueWatching({int limit = 30}) async {
    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items/Resume?MediaTypes=Video&Limit=$limit&Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  Future<bool> addToWatchlist(String itemId) async {
    final url = Uri.parse('$baseUrl/Users/$userId/FavoriteItems/$itemId');
    try {
      final response = await http.post(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFromWatchlist(String itemId) async {
    final url = Uri.parse('$baseUrl/Users/$userId/FavoriteItems/$itemId');
    try {
      final response = await http.delete(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<PlexMediaItem>> getRecentlyAdded(
    String sectionKey, {
    int limit = 30,
    String? libraryType,
  }) async {
    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items/Latest?ParentId=$sectionKey&Limit=$limit&Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final dynamic data = jsonDecode(response.body);
    final List<dynamic> items = data is List ? data : (data['Items'] as List<dynamic>? ?? []);
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  Future<List<PlexMediaItem>> getLibraryItems(
    String sectionKey, {
    String? filter,
    String? sort,
  }) async {
    String itemTypes = 'Movie,Series';
    if (filter != null) {
      if (filter.contains('movie')) itemTypes = 'Movie';
      if (filter.contains('show') || filter.contains('series')) itemTypes = 'Series';
    }

    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items?ParentId=$sectionKey&Recursive=true&IncludeItemTypes=$itemTypes&SortBy=SortName&SortOrder=Ascending&Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  Future<PlexMediaItem> getItemMetadata(String itemId) async {
    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items/$itemId?Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load item details from Jellyfin');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseItem(data);
  }

  Future<List<PlexMediaItem>> getShowSeasons(String showId) async {
    final url = Uri.parse(
      '$baseUrl/Shows/$showId/Seasons?userId=$userId&Fields=Overview,PrimaryImageAspectRatio',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  Future<List<PlexMediaItem>> getSeasonEpisodes(
    String seasonId, {
    String? showId,
  }) async {
    final sId = showId != null && showId.isNotEmpty ? showId : '';
    final url = Uri.parse(
      '$baseUrl/Shows/$sId/Episodes?seasonId=$seasonId&userId=$userId&Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  Future<PlexMediaItem?> getNextEpisode(PlexMediaItem current) async {
    if (!current.isEpisode) return null;
    try {
      final seasonId = current.parentRatingKey;
      final showId = current.grandparentRatingKey;
      if (seasonId != null && seasonId.isNotEmpty) {
        final seasonEpisodes = await getSeasonEpisodes(seasonId, showId: showId);
        final currentIdx = seasonEpisodes.indexWhere((ep) => ep.ratingKey == current.ratingKey);
        if (currentIdx != -1 && currentIdx < seasonEpisodes.length - 1) {
          return seasonEpisodes[currentIdx + 1];
        }
      }

      if (showId != null && showId.isNotEmpty) {
        final seasons = await getShowSeasons(showId);
        final currentSeasonIndex = current.parentIndex ?? 1;
        PlexMediaItem? nextSeason;
        for (final s in seasons) {
          final sIndex = s.index ?? -1;
          if (sIndex > currentSeasonIndex) {
            if (nextSeason == null || sIndex < (nextSeason.index ?? 9999)) {
              nextSeason = s;
            }
          }
        }
        if (nextSeason != null) {
          final nextSeasonEpisodes = await getSeasonEpisodes(nextSeason.ratingKey, showId: showId);
          if (nextSeasonEpisodes.isNotEmpty) {
            return nextSeasonEpisodes.first;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<PlexMediaItem?> getPreviousEpisode(PlexMediaItem current) async {
    if (!current.isEpisode) return null;
    try {
      final seasonId = current.parentRatingKey;
      final showId = current.grandparentRatingKey;
      if (seasonId != null && seasonId.isNotEmpty) {
        final seasonEpisodes = await getSeasonEpisodes(seasonId, showId: showId);
        final currentIdx = seasonEpisodes.indexWhere((ep) => ep.ratingKey == current.ratingKey);
        if (currentIdx > 0) {
          return seasonEpisodes[currentIdx - 1];
        }
      }

      if (showId != null && showId.isNotEmpty) {
        final seasons = await getShowSeasons(showId);
        final currentSeasonIndex = current.parentIndex ?? 1;
        PlexMediaItem? prevSeason;
        for (final s in seasons) {
          final sIndex = s.index ?? -1;
          if (sIndex < currentSeasonIndex && sIndex >= 1) {
            if (prevSeason == null || sIndex > (prevSeason.index ?? -1)) {
              prevSeason = s;
            }
          }
        }
        if (prevSeason != null) {
          final prevSeasonEpisodes = await getSeasonEpisodes(prevSeason.ratingKey, showId: showId);
          if (prevSeasonEpisodes.isNotEmpty) {
            return prevSeasonEpisodes.last;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<PlexMediaItem>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final normalizedQuery = cleanQuery.toLowerCase();

    final rawItems = <Map<String, dynamic>>[];
    final seenRawIds = <String>{};

    Future<void> fetch(Uri url) async {
      try {
        final response = await http.get(url, headers: _headers);
        if (response.statusCode != 200) return;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['Items'] as List<dynamic>? ?? [];
        for (final raw in items) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['Id']?.toString() ?? '';
          if (id.isNotEmpty && !seenRawIds.add(id)) continue;
          rawItems.add(raw);
        }
      } catch (_) {}
    }

    // SearchTerm is the most flexible Jellyfin search. Include all supported
    // media types and ask for a larger page so episodes don't crowd out shows.
    await fetch(Uri.parse(
      '$baseUrl/Users/$userId/Items?searchTerm=${Uri.encodeComponent(cleanQuery)}'
      '&IncludeItemTypes=Movie,Series,Episode&Recursive=true&Limit=100'
      '&Fields=$_itemFields&SortBy=SortName&SortOrder=Ascending&EnableTotalRecordCount=false',
    ));

    // Jellyfin's full-text search can miss exact title prefixes. Merge in a
    // NameStartsWith pass, which is more reliable for short/partial queries.
    await fetch(Uri.parse(
      '$baseUrl/Users/$userId/Items?NameStartsWith=${Uri.encodeComponent(cleanQuery)}'
      '&IncludeItemTypes=Movie,Series&Recursive=true&Limit=60'
      '&Fields=$_itemFields&SortBy=SortName&SortOrder=Ascending&EnableTotalRecordCount=false',
    ));

    final parsed = <PlexMediaItem>[];
    final seenIds = <String>{};
    for (final raw in rawItems) {
      final rawType = raw['Type']?.toString().toLowerCase() ?? '';
      if (rawType != 'movie' && rawType != 'series' && rawType != 'episode') continue;
      final item = _parseItem(raw);
      if (item.ratingKey.isEmpty || !seenIds.add(item.ratingKey)) continue;
      parsed.add(item);
    }

    int score(PlexMediaItem item) {
      final title = item.title.toLowerCase();
      final series = (item.grandparentTitle ?? '').toLowerCase();
      if (title == normalizedQuery) return 0;
      if (title.startsWith(normalizedQuery)) return 1;
      if (title.contains(normalizedQuery)) return 2;
      if (series == normalizedQuery) return 3;
      if (series.startsWith(normalizedQuery)) return 4;
      if (series.contains(normalizedQuery)) return 5;
      return 10;
    }

    final showsAndMovies = parsed
        .where((item) => item.isMovie || item.isShow)
        .toList()
      ..sort((a, b) {
        final byScore = score(a).compareTo(score(b));
        if (byScore != 0) return byScore;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    final result = <PlexMediaItem>[...showsAndMovies];
    final seriesIdsInResult = showsAndMovies
        .where((item) => item.isShow)
        .map((item) => item.ratingKey)
        .toSet();

    final episodes = parsed
        .where((item) => item.isEpisode)
        .where((item) {
          final parentShowId = item.grandparentRatingKey;
          if (parentShowId != null && seriesIdsInResult.contains(parentShowId)) {
            return false;
          }
          return score(item) < 10;
        })
        .toList()
      ..sort((a, b) {
        final byScore = score(a).compareTo(score(b));
        if (byScore != 0) return byScore;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    result.addAll(episodes);
    return result;
  }

  Future<MediaPerson> getPersonDetails(MediaPerson person) async {
    if (person.id.isEmpty) return person;
    try {
      final url = Uri.parse('$baseUrl/Users/$userId/Items/${person.id}?Fields=Overview,ImageTags');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final updated = MediaPerson.fromJellyfin(data);
        final updatedThumb = updated.thumb;
        return MediaPerson(
          id: person.id,
          name: updated.name.isNotEmpty ? updated.name : person.name,
          role: person.role,
          type: person.type,
          thumb: updatedThumb != null && updatedThumb.isNotEmpty ? updatedThumb : person.thumb,
          summary: updated.summary,
        );
      }
    } catch (_) {}
    return person;
  }

  Future<List<PlexMediaItem>> getPersonMedia(MediaPerson person) async {
    if (person.id.isEmpty) return [];
    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items?PersonIds=${Uri.encodeComponent(person.id)}'
      '&Recursive=true&IncludeItemTypes=Movie,Series&Limit=100'
      '&Fields=$_itemFields&SortBy=SortName&SortOrder=Ascending',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_parseItem)
        .where((item) => item.isMovie || item.isShow || item.isEpisode)
        .toList();
  }

  Future<bool> markWatched(String itemId) async {
    final url = Uri.parse('$baseUrl/Users/$userId/PlayedItems/$itemId');
    try {
      final response = await http.post(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markUnwatched(String itemId) async {
    final url = Uri.parse('$baseUrl/Users/$userId/PlayedItems/$itemId');
    try {
      final response = await http.delete(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<PlexMediaItem>> getWatchlist() async {
    final url = Uri.parse(
      '$baseUrl/Users/$userId/Items?Filters=IsFavorite&Recursive=true&IncludeItemTypes=Movie,Series&Fields=$_itemFields',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((m) => _parseItem(m as Map<String, dynamic>)).toList();
  }

  static const int _maxImageRequestWidth = 1920;
  static const int _maxImageRequestHeight = 1080;

  String buildImageUrl(String pathOrId, {int? width, int? height}) {
    if (pathOrId.isEmpty) return '';
    width = width?.clamp(1, _maxImageRequestWidth).toInt();
    height = height?.clamp(1, _maxImageRequestHeight).toInt();
    // External artwork bypasses Jellyfin's resizer; callers must set
    // memCacheWidth/Height to keep the decoded bitmap bounded.
    if (pathOrId.startsWith('http://') || pathOrId.startsWith('https://')) {
      return pathOrId;
    }

    String path = pathOrId;
    if (!path.startsWith('/')) {
      path = '/Items/$path/Images/Primary';
    }

    final sep = path.contains('?') ? '&' : '?';
    final query = <String>[];
    // maxWidth/maxHeight preserve the source aspect ratio. fillWidth/fillHeight
    // stretch Jellyfin images to the requested box, which squashes square
    // cast portraits into the 2:3 tile used by the cast row.
    if (width != null) query.add('maxWidth=$width');
    if (height != null) query.add('maxHeight=$height');
    query.add('quality=90');
    query.add('api_key=$token');

    return '$baseUrl$path$sep${query.join('&')}';
  }

  String _extractCleanItemId(String raw) {
    String itemId = raw;
    if (itemId.contains('/Videos/')) {
      final parts = itemId.split('/Videos/');
      if (parts.length > 1) {
        itemId = parts[1].split('/')[0].split('?')[0];
      }
    } else if (itemId.contains('/Items/')) {
      final parts = itemId.split('/Items/');
      if (parts.length > 1) {
        itemId = parts[1].split('/')[0].split('?')[0];
      }
    }
    return itemId;
  }

  String buildDirectPlayUrl(String partKeyOrId, {int offsetSeconds = 0, String? clientId}) {
    final cleanId = _extractCleanItemId(partKeyOrId);
    if (offsetSeconds > 0) {
      final ticks = offsetSeconds * 10000000;
      final devParam = clientId != null ? '&DeviceId=$clientId' : '';
      return '$baseUrl/Videos/$cleanId/stream?api_key=$token$devParam&StartTimeTicks=$ticks&VideoCodec=copy&AudioCodec=copy';
    }
    return '$baseUrl/Videos/$cleanId/stream?static=true&api_key=$token';
  }

  String buildTranscodeUrl({
    required String itemId,
    int? maxBitrateKbps,
    String? resolution,
    int offsetSeconds = 0,
    required String clientId,
    bool directStreamVideo = false,
    bool forceAudioTranscode = false,
  }) {
    final cleanId = _extractCleanItemId(itemId);
    final params = <String>[
      'api_key=$token',
      'DeviceId=$clientId',
      'MediaSourceId=$cleanId',
      'Static=false',
      'TranscodingContainer=ts',
      'TranscodingProtocol=hls',
    ];
    if (offsetSeconds > 0) {
      params.add('StartTimeTicks=${offsetSeconds * 10000000}');
    }
    if (maxBitrateKbps != null && maxBitrateKbps > 0) {
      params.add('VideoBitRate=${maxBitrateKbps * 1000}');
    }
    if (resolution != null && resolution.contains('x')) {
      final parts = resolution.split('x');
      final width = int.tryParse(parts[0]);
      final height = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (width != null && width > 0) params.add('MaxWidth=$width');
      if (height != null && height > 0) params.add('MaxHeight=$height');
    }

    params.add('VideoCodec=${directStreamVideo ? 'copy' : 'h264'}');
    params.add('AudioCodec=${forceAudioTranscode ? 'aac' : (directStreamVideo ? 'copy' : 'aac')}');
    if (forceAudioTranscode) {
      params.add('AllowAudioStreamCopy=false');
      params.add('EnableAutoStreamCopy=false');
    }
    if (!directStreamVideo) {
      params.add('AllowVideoStreamCopy=false');
    }

    return '$baseUrl/Videos/$cleanId/master.m3u8?${params.join('&')}';
  }

  Future<String?> fetchSubtitleContent({
    required String itemId,
    required String subtitleIndex,
    String? streamKey,
  }) async {
    final cleanId = _extractCleanItemId(itemId);
    if (streamKey != null && streamKey.isNotEmpty) {
      try {
        final path = streamKey.startsWith('/') ? streamKey : '/$streamKey';
        final delim = path.contains('?') ? '&' : '?';
        final url = Uri.parse('$baseUrl$path${delim}api_key=$token');
        final response = await http.get(url, headers: _headers);
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          return response.body;
        }
      } catch (_) {}
    }

    try {
      final url = Uri.parse('$baseUrl/Videos/$cleanId/$cleanId/Subtitles/$subtitleIndex/Stream.vtt?api_key=$token');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return response.body;
      }
    } catch (_) {}

    try {
      final url = Uri.parse('$baseUrl/Videos/$cleanId/Subtitles/$subtitleIndex/Stream.vtt?api_key=$token');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return response.body;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> fetchThemeMusicUrl(String itemId) async {
    final candidates = [
      '$baseUrl/Items/$itemId/ThemeSongs?inheritFromParent=true&userId=$userId&api_key=$token',
      '$baseUrl/Items/$itemId/ThemeSongs?api_key=$token',
      '$baseUrl/Items/$itemId/ThemeMedia?inheritFromParent=true&userId=$userId&api_key=$token',
      '$baseUrl/Items/$itemId/ThemeMedia?api_key=$token',
    ];

    for (final urlStr in candidates) {
      try {
        final url = Uri.parse(urlStr);
        final response = await http.get(url, headers: _headers);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          List<dynamic> items = data['Items'] as List<dynamic>? ?? [];
          if (items.isEmpty && data['ThemeSongsResult'] is Map) {
            items = (data['ThemeSongsResult']['Items'] as List<dynamic>?) ?? [];
          }
          if (items.isEmpty && data['SoundtrackSongsResult'] is Map) {
            items = (data['SoundtrackSongsResult']['Items'] as List<dynamic>?) ?? [];
          }

          if (items.isNotEmpty) {
            final first = items.first as Map<String, dynamic>;
            final songId = first['Id']?.toString() ?? '';
            if (songId.isNotEmpty) {
              final container = first['Container']?.toString().toLowerCase();
              final ext = (container != null && container.isNotEmpty) ? '.$container' : '.mp3';
              return '$baseUrl/Audio/$songId/stream$ext?static=true&api_key=$token';
            }
          }
        }
      } catch (_) {}
    }

    // If not found in native Jellyfin theme media, lookup TVDB Provider ID to fetch theme
    try {
      final metaUrl = Uri.parse('$baseUrl/Items/$itemId?Fields=ProviderIds,SeriesId,ParentId&api_key=$token');
      final metaResp = await http.get(metaUrl, headers: _headers);
      if (metaResp.statusCode == 200) {
        final meta = jsonDecode(metaResp.body) as Map<String, dynamic>;
        var prov = meta['ProviderIds'] as Map<String, dynamic>?;
        var tvdbId = prov?['Tvdb']?.toString() ?? prov?['TheTVDB']?.toString() ?? prov?['tvdb']?.toString();

        if ((tvdbId == null || tvdbId.isEmpty) && (meta['SeriesId'] != null || meta['ParentId'] != null)) {
          final parentId = (meta['SeriesId'] ?? meta['ParentId'])?.toString();
          if (parentId != null && parentId.isNotEmpty) {
            final parentUrl = Uri.parse('$baseUrl/Items/$parentId?Fields=ProviderIds&api_key=$token');
            final pResp = await http.get(parentUrl, headers: _headers);
            if (pResp.statusCode == 200) {
              final pMeta = jsonDecode(pResp.body) as Map<String, dynamic>;
              prov = pMeta['ProviderIds'] as Map<String, dynamic>?;
              tvdbId = prov?['Tvdb']?.toString() ?? prov?['TheTVDB']?.toString() ?? prov?['tvdb']?.toString();
            }
          }
        }

        if (tvdbId != null && tvdbId.isNotEmpty) {
          final tvThemeUrl = 'https://tvthemes.plexapp.com/$tvdbId.mp3';
          try {
            final headCheck = await http.head(Uri.parse(tvThemeUrl)).timeout(const Duration(milliseconds: 1500));
            if (headCheck.statusCode == 200) {
              return tvThemeUrl;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return null;
  }
}
