import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import 'jellyfin_media_service.dart';
import 'plix_device_helper.dart';
import 'update_service.dart';

class PlexMediaService {
  final PlexServer server;
  late final JellyfinMediaService _jfService = JellyfinMediaService(server: server);

  PlexMediaService({required this.server});

  String get baseUrl => server.activeConnectionUri ?? '';
  String get token => server.accessToken;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'X-Plex-Token': token,
        'X-Plex-Product': PlixDeviceHelper.clientName,
        'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
        'X-Plex-Device': PlixDeviceHelper.clientDevice,
        'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
        'X-Plex-Version': UpdateService.currentVersion,
      };

  String buildImageUrl(String? path, {int? width, int? height}) {
    if (server.isJellyfin) {
      return _jfService.buildImageUrl(path ?? '', width: width, height: height);
    }
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;

    if (width != null && height != null) {
      final encodedPath = Uri.encodeComponent(path);
      return '$baseUrl/photo/:/transcode?width=$width&height=$height&minSize=1&upscale=1&url=$encodedPath&X-Plex-Token=$token';
    }

    return '$baseUrl$path?X-Plex-Token=$token';
  }

  String buildDirectPlayUrl(String partKey, {int offsetSeconds = 0, String? clientId}) {
    if (server.isJellyfin) {
      return _jfService.buildDirectPlayUrl(partKey, offsetSeconds: offsetSeconds, clientId: clientId);
    }
    if (partKey.startsWith('http')) return partKey;
    return '$baseUrl$partKey?X-Plex-Token=$token';
  }

  String buildTranscodeUrl({
    required String ratingKey,
    required int maxBitrateKbps,
    required String resolution,
    required int offsetSeconds,
    required String clientId,
    bool directStreamVideo = false,
    bool burnSubtitles = false,
    String? subtitleStreamId,
  }) {
    if (server.isJellyfin) {
      return _jfService.buildTranscodeUrl(
        itemId: ratingKey,
        maxBitrateKbps: maxBitrateKbps,
        resolution: resolution,
        offsetSeconds: offsetSeconds,
        clientId: clientId,
        directStreamVideo: directStreamVideo,
      );
    }
    final resParts = resolution.split('x');
    final width = resParts.isNotEmpty && resParts[0].isNotEmpty ? resParts[0] : '1920';
    final height = resParts.length > 1 ? resParts[1] : '1080';
    final sessionId = '${clientId}_${DateTime.now().millisecondsSinceEpoch}';

    final params = {
      'hasMDE': '1',
      'path': '/library/metadata/$ratingKey',
      'mediaIndex': '0',
      'partIndex': '0',
      'protocol': 'hls',
      'fastSeek': '1',
      'directPlay': '0',
      'directStream': (directStreamVideo && !burnSubtitles) ? '1' : '0',
      'subtitleSize': '100',
      'audioBoost': '100',
      'location': 'lan',
      'addDebugOverlay': '0',
      'autoEmptyContainer': '1',
      'session': sessionId,
      'subtitles': burnSubtitles ? 'burn' : 'none',
      if (burnSubtitles && subtitleStreamId != null && subtitleStreamId.isNotEmpty)
        'subtitleStreamID': subtitleStreamId,
      'copyts': '0',
      if (maxBitrateKbps > 0) 'maxVideoBitrate': '$maxBitrateKbps',
      if (resolution.isNotEmpty) 'videoResolution': '${width}x$height',
      'videoQuality': '100',
      'offset': '$offsetSeconds',
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Product': PlixDeviceHelper.clientName,
      'X-Plex-Device': PlixDeviceHelper.clientDevice,
      'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
      'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
      'X-Plex-Version': UpdateService.currentVersion,
      'X-Plex-Token': token,
    };

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$baseUrl/video/:/transcode/universal/start.m3u8?$queryString';
  }

  Future<List<PlexLibrary>> getLibraries() async {
    if (server.isJellyfin) {
      return _jfService.getLibraries();
    }
    final url = Uri.parse('$baseUrl/library/sections');
    final response = await http.get(url, headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch libraries: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
    final dirList = container['Directory'] as List<dynamic>? ?? [];

    return dirList
        .map((d) => PlexLibrary.fromJson(d as Map<String, dynamic>))
        .where((lib) => lib.isMovie || lib.isShow)
        .toList();
  }

  List<PlexMediaItem> deduplicateContinueWatching(List<PlexMediaItem> items) {
    if (items.isEmpty) return items;

    // Stable sort by lastViewedAt descending if present, preserving original index on ties
    final indexed = List.generate(items.length, (i) => i);
    indexed.sort((a, b) {
      final itemA = items[a];
      final itemB = items[b];
      final timeA = itemA.lastViewedAt ?? 0;
      final timeB = itemB.lastViewedAt ?? 0;
      if (timeA != timeB) {
        return timeB.compareTo(timeA); // higher timestamp (watched last) first
      }
      return a.compareTo(b); // preserve original list order on ties
    });

    final sorted = indexed.map((i) => items[i]).toList();

    final List<PlexMediaItem> result = [];
    final Set<String> seenMovieKeys = {};

    for (final item in sorted) {
      if (!item.isMovie) {
        result.add(item);
        continue;
      }

      final keys = _getMovieIdentityKeys(item);
      final isDuplicate = keys.any((k) => seenMovieKeys.contains(k));
      if (!isDuplicate) {
        seenMovieKeys.addAll(keys);
        result.add(item);
      }
    }

    return result;
  }

  List<String> _getMovieIdentityKeys(PlexMediaItem item) {
    final keys = <String>[];

    // 1. Provider GUID (e.g. plex://movie/..., imdb://..., tmdb://...)
    final guid = item.guid?.trim().toLowerCase();
    if (guid != null && guid.isNotEmpty) {
      if (guid.contains('plex://') ||
          guid.contains('imdb://') ||
          guid.contains('tmdb://') ||
          guid.contains('tvdb://')) {
        final cleanGuid = guid.split('?').first;
        keys.add('guid:$cleanGuid');
      }
    }

    // 2. Title + Year (normalized)
    final title = item.title.trim().toLowerCase();
    if (title.isNotEmpty) {
      if (item.year != null && item.year! > 0) {
        keys.add('title_year:${title}_${item.year}');
      } else {
        keys.add('title:$title');
      }
    }

    return keys;
  }

  Future<List<PlexMediaItem>> getContinueWatching() async {
    if (server.isJellyfin) {
      return _jfService.getContinueWatching();
    }
    final List<PlexMediaItem> rawList = [];
    final url = Uri.parse('$baseUrl/hubs/continueWatching');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
        final hub = container['Hub'] as List<dynamic>?;
        if (hub != null && hub.isNotEmpty) {
          final metadata = hub.first['Metadata'] as List<dynamic>? ?? [];
          rawList.addAll(metadata.map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>)));
        } else {
          final metadata = container['Metadata'] as List<dynamic>? ?? [];
          if (metadata.isNotEmpty) {
            rawList.addAll(metadata.map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>)));
          }
        }
      }
    } catch (_) {}

    // Fallback to /library/onDeck if hubs/continueWatching returned nothing
    if (rawList.isEmpty) {
      try {
        final fallbackUrl = Uri.parse('$baseUrl/library/onDeck');
        final response = await http.get(fallbackUrl, headers: _headers);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
          final metadata = container['Metadata'] as List<dynamic>? ?? [];
          rawList.addAll(metadata.map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>)));
        }
      } catch (_) {}
    }

    return deduplicateContinueWatching(rawList);
  }

  Future<List<PlexMediaItem>> getRecentlyAdded(
    String sectionKey, {
    int limit = 30,
    String? libraryType,
  }) async {
    if (server.isJellyfin) {
      final items = await _jfService.getRecentlyAdded(sectionKey, limit: limit, libraryType: libraryType);
      return deduplicateShows(items);
    }
    // Fetch with progressive pagination until we have at least 'limit' unique items or end of section
    final List<PlexMediaItem> rawItems = [];
    int start = 0;
    const int pageSize = 100;
    const int maxFetch = 2000;

    while (rawItems.length < maxFetch) {
      final url = Uri.parse(
          '$baseUrl/library/sections/$sectionKey/recentlyAdded?X-Plex-Container-Start=$start&X-Plex-Container-Size=$pageSize');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode != 200) break;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final metadata = container['Metadata'] as List<dynamic>? ?? [];
      if (metadata.isEmpty) break;

      final page = metadata
          .map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>))
          .toList();
      rawItems.addAll(page);

      final deduped = deduplicateShows(rawItems);
      if (deduped.length >= limit) {
        return deduped.take(limit).toList();
      }

      start += metadata.length;
      final totalSize = container['totalSize'] as int?;
      if (metadata.length < pageSize || (totalSize != null && start >= totalSize)) {
        break;
      }
    }

    final deduped = deduplicateShows(rawItems);
    return deduped.take(limit).toList();
  }

  List<PlexMediaItem> deduplicateShows(List<PlexMediaItem> items) {
    final List<PlexMediaItem> result = [];
    final Set<String> seenShowKeys = {};
    final Map<String, List<PlexMediaItem>> itemsByShow = {};

    for (final item in items) {
      final showKey = item.isEpisode
          ? (item.grandparentRatingKey ?? (item.grandparentTitle?.isNotEmpty == true ? item.grandparentTitle! : item.ratingKey))
          : item.isSeason
              ? (item.parentRatingKey ?? (item.parentTitle?.isNotEmpty == true ? item.parentTitle! : item.ratingKey))
              : item.ratingKey;

      itemsByShow.putIfAbsent(showKey, () => []).add(item);
    }

    for (final item in items) {
      if (item.isEpisode || item.isSeason || item.isShow) {
        final showKey = item.isEpisode
            ? (item.grandparentRatingKey ?? (item.grandparentTitle?.isNotEmpty == true ? item.grandparentTitle! : item.ratingKey))
            : item.isSeason
                ? (item.parentRatingKey ?? (item.parentTitle?.isNotEmpty == true ? item.parentTitle! : item.ratingKey))
                : item.ratingKey;

        if (!seenShowKeys.contains(showKey)) {
          seenShowKeys.add(showKey);
          final addedItems = itemsByShow[showKey] ?? [item];

          String targetType = 'show';
          String? targetRatingKey = item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey;
          String? targetSeasonKey;
          String addedSubtitle = '';

          if (addedItems.length == 1 && addedItems.first.isEpisode) {
            // Exactly 1 episode was recently added -> go directly to that episode
            targetType = 'episode';
            targetRatingKey = addedItems.first.ratingKey;
            addedSubtitle = addedItems.first.title.isNotEmpty
                ? addedItems.first.title
                : 'Episode ${addedItems.first.index ?? 1}';
          } else {
            // Check distinct seasons
            final seasonSet = <String>{};
            final seasonNumbers = <int>{};
            for (final ai in addedItems) {
              final sKey = ai.parentRatingKey ?? (ai.isSeason ? ai.ratingKey : null);
              if (sKey != null && sKey.isNotEmpty) {
                seasonSet.add(sKey);
              }
              final sNum = ai.parentIndex ?? (ai.isSeason ? ai.index : null);
              if (sNum != null) {
                seasonNumbers.add(sNum);
              }
            }

            if (seasonSet.length == 1 || seasonNumbers.length == 1) {
              // Exactly one season added -> go to start of that season
              targetType = 'season';
              targetSeasonKey = seasonSet.isNotEmpty ? seasonSet.first : null;
              targetRatingKey = targetSeasonKey;
              final sNum = seasonNumbers.isNotEmpty
                  ? seasonNumbers.first
                  : (addedItems.first.parentIndex ?? addedItems.first.index ?? 1);
              addedSubtitle = 'Season $sNum';
            } else if (seasonSet.length > 1 || seasonNumbers.length > 1) {
              // More than one season added -> find earliest season
              int minSeason = 9999;
              String? earliestSeasonKey;
              for (final ai in addedItems) {
                final sNum = ai.parentIndex ?? ai.index ?? 9999;
                final sKey = ai.parentRatingKey ?? (ai.isSeason ? ai.ratingKey : null);
                if (sNum < minSeason && sKey != null) {
                  minSeason = sNum;
                  earliestSeasonKey = sKey;
                }
              }
              targetType = 'season';
              targetSeasonKey = earliestSeasonKey;
              targetRatingKey = earliestSeasonKey;
              addedSubtitle = '';
            } else {
              if (addedItems.length == 1) {
                addedSubtitle = addedItems.first.title;
              } else {
                addedSubtitle = '';
              }
            }
          }

          final showTitle = item.isEpisode
              ? (item.grandparentTitle?.isNotEmpty == true ? item.grandparentTitle! : item.title)
              : item.isSeason
                  ? (item.parentTitle?.isNotEmpty == true ? item.parentTitle! : item.title)
                  : item.title;

          final showPoster = item.grandparentThumb ?? item.parentThumb ?? item.thumb;

          final showItem = item.copyWith(
            title: showTitle,
            ratingKey: item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey,
            type: 'show',
            thumb: showPoster,
            grandparentThumb: showPoster,
            targetType: targetType,
            targetRatingKey: targetRatingKey,
            targetSeasonKey: targetSeasonKey,
            addedSubtitle: addedSubtitle,
          );
          result.add(showItem);
        }
      } else {
        // Movies
        if (!seenShowKeys.contains(item.ratingKey)) {
          seenShowKeys.add(item.ratingKey);
          result.add(item.copyWith(
            targetType: 'movie',
            targetRatingKey: item.ratingKey,
          ));
        }
      }
    }
    return result;
  }

  Future<List<PlexMediaItem>> getLibraryItems(String sectionKey) async {
    if (server.isJellyfin) {
      return _jfService.getLibraryItems(sectionKey);
    }
    final url = Uri.parse('$baseUrl/library/sections/$sectionKey/all');
    final response = await http.get(url, headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load library items: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
    final metadata = container['Metadata'] as List<dynamic>? ?? [];

    return metadata
        .map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<PlexMediaItem> getItemMetadata(String ratingKey) async {
    if (server.isJellyfin) {
      return _jfService.getItemMetadata(ratingKey);
    }
    final url = Uri.parse('$baseUrl/library/metadata/$ratingKey?includeStreams=1&includeMarkers=1');
    final response = await http.get(url, headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load item metadata: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
    final metadata = (container['Metadata'] as List<dynamic>?) ??
        (container['Directory'] as List<dynamic>?) ??
        [];
    if (metadata.isEmpty) {
      throw Exception('Metadata not found for $ratingKey');
    }

    return PlexMediaItem.fromJson(metadata.first as Map<String, dynamic>);
  }

  Future<List<PlexMediaItem>> getShowSeasons(String showRatingKey) async {
    if (server.isJellyfin) {
      return _jfService.getShowSeasons(showRatingKey);
    }
    final url = Uri.parse('$baseUrl/library/metadata/$showRatingKey/children');
    final response = await http.get(url, headers: _headers);

    if (response.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};

    // In Plex, seasons are typically inside container['Metadata'], but can also be in container['Directory']!
    final metadataList = container['Metadata'] as List<dynamic>? ?? [];
    final dirList = container['Directory'] as List<dynamic>? ?? [];

    final List<PlexMediaItem> seasons = [];

    // 1. Process Metadata (standard seasons list)
    for (final item in metadataList) {
      final m = PlexMediaItem.fromJson(item as Map<String, dynamic>);
      if (m.type == 'season' ||
          m.title.toLowerCase().contains('season') ||
          m.title.toLowerCase().contains('specials')) {
        seasons.add(m);
      }
    }

    // 2. Process Directory (ignoring the virtual "All episodes" folder if actual seasons exist)
    for (final item in dirList) {
      final m = PlexMediaItem.fromJson(item as Map<String, dynamic>);
      if (m.title.toLowerCase() != 'all episodes' &&
          (m.type == 'season' ||
              m.title.toLowerCase().contains('season') ||
              m.title.toLowerCase().contains('specials'))) {
        if (!seasons.any((s) => s.ratingKey == m.ratingKey && m.ratingKey.isNotEmpty)) {
          seasons.add(m);
        }
      }
    }

    // Fallback if empty (e.g. miniseries or flat structure)
    if (seasons.isEmpty && metadataList.isNotEmpty) {
      seasons.addAll(metadataList.map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>)));
    }
    if (seasons.isEmpty && dirList.isNotEmpty) {
      seasons.addAll(dirList.map((d) => PlexMediaItem.fromJson(d as Map<String, dynamic>)));
    }

    return seasons;
  }

  Future<List<PlexMediaItem>> getSeasonEpisodes(
    String seasonRatingKey, {
    String? seasonKey,
    String? showRatingKey,
  }) async {
    if (server.isJellyfin) {
      return _jfService.getSeasonEpisodes(seasonRatingKey, showId: showRatingKey);
    }
    Uri url;
    if (seasonRatingKey.isNotEmpty && seasonRatingKey != '0') {
      url = Uri.parse('$baseUrl/library/metadata/$seasonRatingKey/children?includeStreams=1');
    } else if (seasonKey != null && seasonKey.isNotEmpty) {
      final baseStr = seasonKey.startsWith('http') ? seasonKey : '$baseUrl$seasonKey';
      final sep = baseStr.contains('?') ? '&' : '?';
      url = Uri.parse('$baseStr${sep}includeStreams=1');
    } else if (showRatingKey != null && showRatingKey.isNotEmpty) {
      url = Uri.parse('$baseUrl/library/metadata/$showRatingKey/allLeaves?includeStreams=1');
    } else {
      return [];
    }

    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      // Fallback to allLeaves if specific season children failed
      if (showRatingKey != null && showRatingKey.isNotEmpty && url.path.contains(seasonRatingKey)) {
        return getSeasonEpisodes('', showRatingKey: showRatingKey);
      }
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
    final metadata = (container['Metadata'] as List<dynamic>?) ??
        (container['Video'] as List<dynamic>?) ??
        [];

    return metadata
        .map((m) => PlexMediaItem.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<PlexMediaItem?> getPreviousEpisode(PlexMediaItem current) async {
    if (server.isJellyfin) {
      return _jfService.getPreviousEpisode(current);
    }
    if (!current.isEpisode) return null;

    try {
      // 1. Try to get previous episode in the same season
      final seasonKey = current.parentRatingKey;
      if (seasonKey != null && seasonKey.isNotEmpty) {
        final seasonEpisodes = await getSeasonEpisodes(seasonKey);
        final currentIdx = seasonEpisodes.indexWhere(
          (ep) => ep.ratingKey == current.ratingKey || (current.index != null && ep.index == current.index),
        );
        if (currentIdx > 0) {
          return seasonEpisodes[currentIdx - 1];
        }
      }

      // 2. If at the beginning of the season, check for the preceding season
      final showKey = current.grandparentRatingKey;
      if (showKey != null && showKey.isNotEmpty) {
        final seasons = await getShowSeasons(showKey);
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
          final prevSeasonEpisodes = await getSeasonEpisodes(prevSeason.ratingKey);
          if (prevSeasonEpisodes.isNotEmpty) {
            return prevSeasonEpisodes.last;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<PlexMediaItem?> getNextEpisode(PlexMediaItem current) async {
    if (server.isJellyfin) {
      return _jfService.getNextEpisode(current);
    }
    if (!current.isEpisode) return null;

    try {
      // 1. Try to get subsequent episode in the same season
      final seasonKey = current.parentRatingKey;
      if (seasonKey != null && seasonKey.isNotEmpty) {
        final seasonEpisodes = await getSeasonEpisodes(seasonKey);
        final currentIdx = seasonEpisodes.indexWhere(
          (ep) => ep.ratingKey == current.ratingKey || (current.index != null && ep.index == current.index),
        );
        if (currentIdx != -1 && currentIdx < seasonEpisodes.length - 1) {
          return seasonEpisodes[currentIdx + 1];
        }
      }

      // 2. If at the end of the season, check for the next season
      final showKey = current.grandparentRatingKey;
      if (showKey != null && showKey.isNotEmpty) {
        final seasons = await getShowSeasons(showKey);
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
          final nextSeasonEpisodes = await getSeasonEpisodes(nextSeason.ratingKey);
          if (nextSeasonEpisodes.isNotEmpty) {
            return nextSeasonEpisodes.first;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool> markWatched(String ratingKey) async {
    if (server.isJellyfin) {
      return _jfService.markWatched(ratingKey);
    }
    final url = Uri.parse(
        '$baseUrl/:/scrobble?key=$ratingKey&identifier=com.plexapp.plugins.library&X-Plex-Token=$token');
    try {
      final res = await http.get(url);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markUnwatched(String ratingKey) async {
    if (server.isJellyfin) {
      return _jfService.markUnwatched(ratingKey);
    }
    final url = Uri.parse(
        '$baseUrl/:/unscrobble?key=$ratingKey&identifier=com.plexapp.plugins.library&X-Plex-Token=$token');
    try {
      final res = await http.get(url);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  bool _isSubtitleContent(String body) {
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();
    return body.contains('-->') ||
        lower.contains('dialogue:') ||
        lower.contains('webvtt') ||
        lower.contains('[events]');
  }

  Future<String?> fetchSubtitleContent({
    required String ratingKey,
    required String subtitleStreamId,
    String? streamKey,
  }) async {
    if (server.isJellyfin) {
      return _jfService.fetchSubtitleContent(
        itemId: ratingKey,
        subtitleIndex: subtitleStreamId,
        streamKey: streamKey,
      );
    }
    final subHeaders = {
      'X-Plex-Token': token,
      'Accept': '*/*',
      'X-Plex-Product': PlixDeviceHelper.clientName,
      'X-Plex-Version': '1.0.0',
      'X-Plex-Client-Identifier': 'plix-flutter-client',
    };

    // 1. If streamKey is provided, try direct fetch
    if (streamKey != null && streamKey.isNotEmpty) {
      try {
        final path = streamKey.startsWith('/') ? streamKey : '/$streamKey';
        final url = Uri.parse('$baseUrl$path?X-Plex-Token=$token');
        final response = await http.get(url, headers: subHeaders);
        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (_isSubtitleContent(body)) {
            return body;
          }
        }
      } catch (_) {}
    }

    // 2. Try direct /library/streams/$subtitleStreamId
    if (subtitleStreamId.isNotEmpty && subtitleStreamId != '0') {
      try {
        final url = Uri.parse('$baseUrl/library/streams/$subtitleStreamId?X-Plex-Token=$token');
        final response = await http.get(url, headers: subHeaders);
        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (_isSubtitleContent(body)) {
            return body;
          }
        }
      } catch (_) {}
    }

    // 3. Universal subtitle extraction endpoint (extracts embedded text subtitles as WebVTT)
    try {
      final url = Uri.parse(
        '$baseUrl/video/:/transcode/universal/subtitles?'
        'path=%2Flibrary%2Fmetadata%2F$ratingKey'
        '&mediaIndex=0&partIndex=0'
        '&subtitleStreamID=$subtitleStreamId'
        '&format=vtt'
        '&directStreamSubtitles=1'
        '&X-Plex-Token=$token',
      );
      final response = await http.get(url, headers: subHeaders);
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (_isSubtitleContent(body)) {
          return body;
        }
      }
    } catch (_) {}

    // 4. Fallback to /video/:/transcode/universal/subtitles with format=srt
    try {
      final url = Uri.parse(
        '$baseUrl/video/:/transcode/universal/subtitles?'
        'path=%2Flibrary%2Fmetadata%2F$ratingKey'
        '&mediaIndex=0&partIndex=0'
        '&subtitleStreamID=$subtitleStreamId'
        '&format=srt'
        '&X-Plex-Token=$token',
      );
      final response = await http.get(url, headers: subHeaders);
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (_isSubtitleContent(body)) {
          return body;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool> setSubtitleStream({required String partId, required String subtitleStreamId}) async {
    try {
      final url = Uri.parse('$baseUrl/library/parts/$partId?subtitleStreamID=$subtitleStreamId&X-Plex-Token=$token');
      final response = await http.put(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setAudioStream({required String partId, required String audioStreamId}) async {
    try {
      final url = Uri.parse('$baseUrl/library/parts/$partId?audioStreamID=$audioStreamId&X-Plex-Token=$token');
      final response = await http.put(url, headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<PlexMediaItem>> search(String query) async {
    if (server.isJellyfin) {
      return _jfService.search(query);
    }
    final q = query.trim();
    if (q.isEmpty) return [];

    final rawItems = <PlexMediaItem>[];

    try {
      final encoded = Uri.encodeComponent(q);
      // 1. Query /hubs/search
      final uri = Uri.parse('$baseUrl/hubs/search?query=$encoded&limit=50');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final mc = data['MediaContainer'] as Map<String, dynamic>?;
        if (mc != null) {
          final hubs = mc['Hub'] as List<dynamic>?;
          if (hubs != null) {
            for (final h in hubs) {
              final hubMeta = h['Metadata'] as List<dynamic>?;
              if (hubMeta != null) {
                for (final item in hubMeta) {
                  rawItems.add(PlexMediaItem.fromJson(item as Map<String, dynamic>));
                }
              }
            }
          }
          final meta = mc['Metadata'] as List<dynamic>?;
          if (meta != null) {
            for (final item in meta) {
              rawItems.add(PlexMediaItem.fromJson(item as Map<String, dynamic>));
            }
          }
        }
      }

      // 2. Fallback to /library/search if empty
      if (rawItems.isEmpty) {
        final libUri = Uri.parse('$baseUrl/library/search?query=$encoded&limit=50');
        final libRes = await http.get(libUri, headers: _headers);
        if (libRes.statusCode == 200) {
          final data = json.decode(libRes.body) as Map<String, dynamic>;
          final mc = data['MediaContainer'] as Map<String, dynamic>?;
          final meta = mc?['Metadata'] as List<dynamic>?;
          if (meta != null) {
            for (final item in meta) {
              rawItems.add(PlexMediaItem.fromJson(item as Map<String, dynamic>));
            }
          }
        }
      }
    } catch (_) {}

    if (rawItems.isEmpty) return [];

    final lowerQ = q.toLowerCase();
    final seen = <String>{};
    final filtered = <PlexMediaItem>[];

    for (final it in rawItems) {
      if (!seen.add(it.ratingKey)) continue;

      // Filter out raw season items from search results
      if (it.type == 'season') continue;

      // If item is an episode, only show if query directly matches episode title (not show title)
      if (it.isEpisode || it.type == 'episode') {
        if (!it.title.toLowerCase().contains(lowerQ)) {
          continue;
        }
      }

      filtered.add(it);
    }

    return filtered;
  }

  Future<PlexMediaItem?> getMovieTrailer(
    String ratingKey, {
    String? guid,
    String? userToken,
  }) async {
    // 1. Try local server extras endpoint: /library/metadata/$ratingKey/extras
    try {
      final url = Uri.parse('$baseUrl/library/metadata/$ratingKey/extras');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
        final metadata = (container['Metadata'] as List<dynamic>?) ??
            (container['Video'] as List<dynamic>?) ??
            (container['Extra'] as List<dynamic>?) ??
            [];
        for (final m in metadata) {
          final map = m as Map<String, dynamic>;
          final extraType = map['extraType']?.toString();
          final subtype = map['subtype']?.toString().toLowerCase();
          final title = (map['title']?.toString() ?? '').toLowerCase();
          if (extraType == '1' || subtype == 'trailer' || title.contains('trailer') || title.contains('teaser')) {
            final item = PlexMediaItem.fromJson(map);
            if (item.partKey == null || item.partKey!.isEmpty) {
              try {
                final full = await getItemMetadata(item.ratingKey);
                if (full.partKey != null && full.partKey!.isNotEmpty) {
                  return full;
                }
              } catch (_) {}
            }
            return item;
          }
        }
      }
    } catch (_) {}

    // 2. Try /library/metadata/$ratingKey?includeExtras=1
    try {
      final url = Uri.parse('$baseUrl/library/metadata/$ratingKey?includeExtras=1');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
        final metadataList = container['Metadata'] as List<dynamic>? ?? [];
        if (metadataList.isNotEmpty) {
          final itemMap = metadataList.first as Map<String, dynamic>;
          final extrasList = (itemMap['Extras'] as Map<String, dynamic>?)?['Metadata'] as List<dynamic>? ??
              (itemMap['Extras'] as List<dynamic>?) ??
              (itemMap['Extra'] as List<dynamic>?) ??
              [];
          for (final ex in extrasList) {
            final map = ex as Map<String, dynamic>;
            final extraType = map['extraType']?.toString();
            final subtype = map['subtype']?.toString().toLowerCase();
            final title = (map['title']?.toString() ?? '').toLowerCase();
            if (extraType == '1' || subtype == 'trailer' || title.contains('trailer') || title.contains('teaser')) {
              final item = PlexMediaItem.fromJson(map);
              if (item.partKey == null || item.partKey!.isEmpty) {
                try {
                  final full = await getItemMetadata(item.ratingKey);
                  if (full.partKey != null && full.partKey!.isNotEmpty) {
                    return full;
                  }
                } catch (_) {}
              }
              return item;
            }
          }
        }
      }
    } catch (_) {}

    // 3. Fallback: Plex Discover metadata extras
    final tokenToUse = (userToken != null && userToken.isNotEmpty) ? userToken : token;
    if (tokenToUse.isNotEmpty && guid != null && guid.startsWith('plex://')) {
      try {
        final discoverKey = guid.replaceFirst('plex://', '');
        final discUrl = Uri.parse('https://discover.provider.plex.tv/library/metadata/$discoverKey?includeExtras=1');
        final discRes = await http.get(discUrl, headers: {
          'Accept': 'application/json',
          'X-Plex-Token': tokenToUse,
        });
        if (discRes.statusCode == 200) {
          final data = jsonDecode(discRes.body) as Map<String, dynamic>;
          final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};
          final meta = container['Metadata'] as List<dynamic>? ?? [];
          if (meta.isNotEmpty) {
            final itemMap = meta.first as Map<String, dynamic>;
            final extras = (itemMap['Extras'] as Map<String, dynamic>?)?['Metadata'] as List<dynamic>? ??
                (itemMap['Extras'] as List<dynamic>?) ??
                [];
            for (final ex in extras) {
              final map = ex as Map<String, dynamic>;
              final extraType = map['extraType']?.toString();
              final subtype = map['subtype']?.toString().toLowerCase();
              final title = (map['title']?.toString() ?? '').toLowerCase();
              if (extraType == '1' || subtype == 'trailer' || title.contains('trailer') || title.contains('teaser')) {
                return PlexMediaItem.fromJson(map);
              }
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String?> resolveDiscoverRatingKey(PlexMediaItem item, String userToken) async {
    // 0. For episodes or seasons, try to get the parent show's Discover key directly
    if (item.isEpisode || item.isSeason || item.grandparentRatingKey != null || item.parentRatingKey != null) {
      if (item.grandparentGuid != null && item.grandparentGuid!.contains('plex://show/')) {
        final seg = item.grandparentGuid!.split('?').first.split('/').last;
        if (RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(seg)) {
          return seg;
        }
      }
      final showKey = item.grandparentRatingKey ?? item.parentRatingKey;
      if (showKey != null && showKey.isNotEmpty && !server.isJellyfin) {
        try {
          final showItem = await getItemMetadata(showKey);
          if (showItem.guid != null && showItem.guid!.contains('plex://')) {
            final seg = showItem.guid!.split('?').first.split('/').last;
            if (RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(seg)) {
              return seg;
            }
          }
        } catch (_) {}
      }
    }

    // 1. If ratingKey is already a 24-character hex string (Discover ID), return directly
    // ONLY if item is NOT an episode or season (since Discover episodes cannot be watchlisted)
    if (!item.isEpisode && !item.isSeason && RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(item.ratingKey)) {
      return item.ratingKey;
    }

    // 2. If guid is plex://movie/{key} or plex://show/{key} (ignore plex://episode/)
    if (item.guid != null && item.guid!.contains('plex://') && !item.guid!.contains('plex://episode/')) {
      final segment = item.guid!.split('?').first.split('/').last;
      if (RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(segment)) {
        return segment;
      }
    }

    // 3. For episodes or seasons, target the series name
    final searchTitle = (item.isEpisode && item.grandparentTitle != null && item.grandparentTitle!.isNotEmpty)
        ? item.grandparentTitle!
        : (item.isSeason && item.parentTitle != null && item.parentTitle!.isNotEmpty)
            ? item.parentTitle!
            : item.title;

    final targetType = (item.isEpisode || item.isSeason || item.isShow) ? 'show' : (item.isMovie ? 'movie' : null);

    // 4. Search Discover by title and match year
    final tokensToTry = [
      if (userToken.isNotEmpty) userToken,
      if (token.isNotEmpty && token != userToken) token,
    ];

    for (final t in tokensToTry) {
      try {
        final q = Uri.encodeComponent(searchTitle);
        final tokenParam = Uri.encodeComponent(t);
        final typeParam = targetType == 'movie' ? '&type=1' : (targetType == 'show' ? '&type=2' : '');
        final url = Uri.parse('https://discover.provider.plex.tv/library/search?query=$q&X-Plex-Token=$tokenParam$typeParam');
        final res = await http.get(url, headers: {
          'Accept': 'application/json',
          'X-Plex-Token': t,
        }).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
          final List<dynamic> meta = [];
          if (mc['Metadata'] is List) meta.addAll(mc['Metadata'] as List);
          if (mc['SearchResults'] is List) meta.addAll(mc['SearchResults'] as List);
          if (mc['Hub'] is List) {
            for (final h in mc['Hub'] as List) {
              if (h is Map && h['Metadata'] is List) {
                meta.addAll(h['Metadata'] as List);
              }
            }
          }

          for (final m in meta) {
            if (m is! Map<String, dynamic>) continue;
            final map = m;
            if (targetType != null && map['type'] != null && map['type'].toString().toLowerCase() != targetType) {
              continue;
            }
            final mTitle = map['title']?.toString().toLowerCase().trim();
            final mYear = (map['year'] is num) ? (map['year'] as num).toInt() : int.tryParse(map['year']?.toString() ?? '');
            if (mTitle == searchTitle.toLowerCase().trim()) {
              if (item.isEpisode || item.year == null || mYear == null || item.year == mYear) {
                final key = map['ratingKey']?.toString() ?? map['id']?.toString();
                if (key != null && key.isNotEmpty) return key;
              }
            }
          }
          for (final m in meta) {
            if (m is! Map<String, dynamic>) continue;
            final map = m;
            if (targetType != null && map['type'] != null && map['type'].toString().toLowerCase() != targetType) {
              continue;
            }
            final firstKey = map['ratingKey']?.toString() ?? map['id']?.toString();
            if (firstKey != null && firstKey.isNotEmpty) return firstKey;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<bool> isInWatchlist({
    required PlexMediaItem item,
    required String userToken,
  }) async {
    final targetItem = (item.isEpisode || item.isSeason)
        ? PlexMediaItem(
            ratingKey: item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey,
            key: '/library/metadata/${item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey}',
            title: item.grandparentTitle ?? item.parentTitle ?? item.title,
            type: 'show',
            year: item.year,
            thumb: item.grandparentThumb ?? item.parentThumb ?? item.thumb,
          )
        : item;

    if (server.isJellyfin) {
      try {
        final watchlist = await _jfService.getWatchlist();
        return watchlist.any((w) =>
            w.ratingKey == targetItem.ratingKey ||
            (targetItem.title.isNotEmpty && w.title.toLowerCase().trim() == targetItem.title.toLowerCase().trim()));
      } catch (_) {
        return false;
      }
    }
    try {
      final watchlist = await getWatchlist(userToken: userToken, clientId: '');
      final discoverKey = await resolveDiscoverRatingKey(targetItem, userToken);

      final checkTitle = targetItem.title.toLowerCase().trim();

      for (final w in watchlist) {
        if (discoverKey != null && w.ratingKey == discoverKey) return true;
        if (targetItem.guid != null && w.guid != null && targetItem.guid!.split('?').first == w.guid!.split('?').first) return true;
        if (w.title.toLowerCase().trim() == checkTitle) {
          if (targetItem.year == null || w.year == null || targetItem.year == w.year) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<List<PlexMediaItem>> getWatchlist({
    required String userToken,
    required String clientId,
  }) async {
    if (server.isJellyfin) {
      return _jfService.getWatchlist();
    }
    final tokensToTry = [
      if (userToken.isNotEmpty) userToken,
      if (token.isNotEmpty && token != userToken) token,
    ];

    for (final t in tokensToTry) {
      final tokenParam = Uri.encodeComponent(t);
      final headers = {
        'Accept': 'application/json',
        'X-Plex-Token': t,
        'X-Plex-Product': PlixDeviceHelper.clientName,
        'X-Plex-Platform': PlixDeviceHelper.clientPlatform,
        'X-Plex-Device': PlixDeviceHelper.clientDevice,
        'X-Plex-Device-Name': PlixDeviceHelper.deviceName,
        'X-Plex-Version': UpdateService.currentVersion,
        if (clientId.isNotEmpty) 'X-Plex-Client-Identifier': clientId,
      };

      final candidateUrls = [
        'https://discover.provider.plex.tv/library/sections/watchlist/all?includeCollections=1&includeExternalMedia=1&sort=watchlistedAt:desc&X-Plex-Token=$tokenParam',
        'https://discover.provider.plex.tv/library/sections/watchlist/all?includeCollections=1&includeExternalMedia=1&X-Plex-Token=$tokenParam',
        'https://discover.provider.plex.tv/library/sections/watchlist/all?X-Plex-Token=$tokenParam',
        'https://discover.provider.plex.tv/library/sections/watchlist/all?includeAdvanced=1&includeMeta=1&X-Plex-Token=$tokenParam',
        'https://metadata.provider.plex.tv/library/sections/watchlist/all?includeCollections=1&includeExternalMedia=1&X-Plex-Token=$tokenParam',
        'https://metadata.provider.plex.tv/library/sections/watchlist/all?X-Plex-Token=$tokenParam',
        '$baseUrl/library/sections/watchlist/all?X-Plex-Token=$tokenParam',
      ];

      for (final urlBase in candidateUrls) {
        try {
          const int pageSize = 100;
          int start = 0;
          int? totalSize;
          final List<PlexMediaItem> allParsed = [];

          while (true) {
            // Append pagination params; urlBase already has '?' so use '&'
            final separator = urlBase.contains('?') ? '&' : '?';
            final pagedUrl = Uri.parse(
              '$urlBase${separator}X-Plex-Container-Start=$start&X-Plex-Container-Size=$pageSize',
            );
            final response = await http.get(pagedUrl, headers: headers).timeout(const Duration(seconds: 10));
            if (response.statusCode != 200) break;

            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final container = data['MediaContainer'] as Map<String, dynamic>? ?? {};

            // Capture totalSize from first page
            totalSize ??= (container['totalSize'] as num?)?.toInt() ??
                (container['size'] as num?)?.toInt();

            final List<dynamic> rawList = [];
            if (container['Metadata'] is List) {
              rawList.addAll(container['Metadata'] as List);
            } else if (container['Metadata'] is Map) {
              rawList.add(container['Metadata']);
            }
            if (rawList.isEmpty && container['Video'] is List) {
              rawList.addAll(container['Video'] as List);
            } else if (rawList.isEmpty && container['Video'] is Map) {
              rawList.add(container['Video']);
            }
            if (rawList.isEmpty && container['Directory'] is List) {
              rawList.addAll(container['Directory'] as List);
            } else if (rawList.isEmpty && container['Directory'] is Map) {
              rawList.add(container['Directory']);
            }
            if (rawList.isEmpty && container['Hub'] is List) {
              for (final hub in container['Hub'] as List) {
                if (hub is Map && hub['Metadata'] is List) {
                  rawList.addAll(hub['Metadata'] as List);
                }
              }
            }

            for (final m in rawList) {
              try {
                if (m is Map<String, dynamic>) {
                  final map = Map<String, dynamic>.from(m);
                  final thumbStr = map['thumb']?.toString();
                  if (thumbStr != null && thumbStr.isNotEmpty && !thumbStr.startsWith('http')) {
                    map['thumb'] = 'https://discover.provider.plex.tv$thumbStr?X-Plex-Token=$tokenParam';
                  }
                  final artStr = map['art']?.toString();
                  if (artStr != null && artStr.isNotEmpty && !artStr.startsWith('http')) {
                    map['art'] = 'https://discover.provider.plex.tv$artStr?X-Plex-Token=$tokenParam';
                  }
                  final gpThumb = map['grandparentThumb']?.toString();
                  if (gpThumb != null && gpThumb.isNotEmpty && !gpThumb.startsWith('http')) {
                    map['grandparentThumb'] = 'https://discover.provider.plex.tv$gpThumb?X-Plex-Token=$tokenParam';
                  }
                  allParsed.add(PlexMediaItem.fromJson(map));
                }
              } catch (_) {}
            }

            // Stop if this page returned fewer items than requested (last page)
            // or if we've reached/exceeded the known total
            if (rawList.length < pageSize) break;
            if (totalSize != null && allParsed.length >= totalSize) break;

            start += pageSize;
          }

          if (allParsed.isNotEmpty) {
            return allParsed;
          }
        } catch (_) {}
      }
    }

    return [];
  }

  Future<bool> addToWatchlist({
    required PlexMediaItem item,
    required String userToken,
  }) async {
    final targetItem = (item.isEpisode || item.isSeason)
        ? PlexMediaItem(
            ratingKey: item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey,
            key: '/library/metadata/${item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey}',
            title: item.grandparentTitle ?? item.parentTitle ?? item.title,
            type: 'show',
            year: item.year,
            thumb: item.grandparentThumb ?? item.parentThumb ?? item.thumb,
          )
        : item;

    if (server.isJellyfin) {
      return _jfService.addToWatchlist(targetItem.ratingKey);
    }
    final discoverKey = await resolveDiscoverRatingKey(targetItem, userToken);
    if (discoverKey == null || discoverKey.isEmpty) return false;

    final tokensToTry = [
      if (userToken.isNotEmpty) userToken,
      if (token.isNotEmpty && token != userToken) token,
    ];

    for (final t in tokensToTry) {
      try {
        final tokenParam = Uri.encodeComponent(t);
        final url = Uri.parse('https://discover.provider.plex.tv/actions/addToWatchlist?ratingKey=$discoverKey&X-Plex-Token=$tokenParam');
        final res = await http.put(url, headers: {
          'Accept': 'application/json',
          'X-Plex-Token': t,
        }).timeout(const Duration(seconds: 6));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<bool> removeFromWatchlist({
    required PlexMediaItem item,
    required String userToken,
  }) async {
    final targetItem = (item.isEpisode || item.isSeason)
        ? PlexMediaItem(
            ratingKey: item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey,
            key: '/library/metadata/${item.grandparentRatingKey ?? item.parentRatingKey ?? item.ratingKey}',
            title: item.grandparentTitle ?? item.parentTitle ?? item.title,
            type: 'show',
            year: item.year,
            thumb: item.grandparentThumb ?? item.parentThumb ?? item.thumb,
          )
        : item;

    if (server.isJellyfin) {
      return _jfService.removeFromWatchlist(targetItem.ratingKey);
    }
    final discoverKey = await resolveDiscoverRatingKey(targetItem, userToken);
    if (discoverKey == null || discoverKey.isEmpty) return false;

    final tokensToTry = [
      if (userToken.isNotEmpty) userToken,
      if (token.isNotEmpty && token != userToken) token,
    ];

    for (final t in tokensToTry) {
      try {
        final tokenParam = Uri.encodeComponent(t);
        final url = Uri.parse('https://discover.provider.plex.tv/actions/removeFromWatchlist?ratingKey=$discoverKey&X-Plex-Token=$tokenParam');
        final res = await http.put(url, headers: {
          'Accept': 'application/json',
          'X-Plex-Token': t,
        }).timeout(const Duration(seconds: 6));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<String?> fetchThemeMusicUrl(String itemId) async {
    if (server.isJellyfin) {
      return _jfService.fetchThemeMusicUrl(itemId);
    }
    return null;
  }
}
