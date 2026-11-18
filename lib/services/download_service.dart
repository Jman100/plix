import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import 'plix_device_helper.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String ratingKey;
  final String title;
  final String type; // 'movie' or 'episode'
  final String? seriesTitle;
  final String? seasonTitle;
  final int? seasonIndex;
  final int? episodeIndex;
  final String? seriesRatingKey;
  final String? seasonRatingKey;
  final int? duration;
  final int? year;
  final String summary;
  final String? thumbUrl;
  String? localThumbPath;
  final String? showThumbUrl;
  String? localShowThumbPath;
  final String? showSummary;
  final String? artUrl;
  String? localArtPath;
  String downloadUrl;
  final String localFilePath;
  final String serverId;
  final String serverName;
  final String serverType;
  final Map<String, String>? headers;

  DownloadStatus status;
  int receivedBytes;
  int totalBytes;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;
  http.Client? _httpClient;

  DownloadTask({
    required this.ratingKey,
    required this.title,
    required this.type,
    this.seriesTitle,
    this.seasonTitle,
    this.seasonIndex,
    this.episodeIndex,
    this.seriesRatingKey,
    this.seasonRatingKey,
    this.duration,
    this.year,
    this.summary = '',
    this.thumbUrl,
    this.localThumbPath,
    this.showThumbUrl,
    this.localShowThumbPath,
    this.showSummary,
    this.artUrl,
    this.localArtPath,
    required this.downloadUrl,
    required this.localFilePath,
    required this.serverId,
    required this.serverName,
    required this.serverType,
    this.headers,
    this.status = DownloadStatus.queued,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isRunning => status == DownloadStatus.queued || status == DownloadStatus.downloading;
  bool get isCompleted => status == DownloadStatus.completed;

  Map<String, dynamic> toJson() {
    return {
      'ratingKey': ratingKey,
      'title': title,
      'type': type,
      'seriesTitle': seriesTitle,
      'seasonTitle': seasonTitle,
      'seasonIndex': seasonIndex,
      'episodeIndex': episodeIndex,
      'seriesRatingKey': seriesRatingKey,
      'seasonRatingKey': seasonRatingKey,
      'duration': duration,
      'year': year,
      'summary': summary,
      'thumbUrl': thumbUrl,
      'localThumbPath': localThumbPath,
      'showThumbUrl': showThumbUrl,
      'localShowThumbPath': localShowThumbPath,
      'showSummary': showSummary,
      'artUrl': artUrl,
      'localArtPath': localArtPath,
      'downloadUrl': downloadUrl,
      'localFilePath': localFilePath,
      'serverId': serverId,
      'serverName': serverName,
      'serverType': serverType,
      'headers': headers,
      'status': status.name,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      ratingKey: json['ratingKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'movie',
      seriesTitle: json['seriesTitle'] as String?,
      seasonTitle: json['seasonTitle'] as String?,
      seasonIndex: json['seasonIndex'] as int?,
      episodeIndex: json['episodeIndex'] as int?,
      seriesRatingKey: json['seriesRatingKey'] as String?,
      seasonRatingKey: json['seasonRatingKey'] as String?,
      duration: json['duration'] as int?,
      year: json['year'] as int?,
      summary: json['summary'] as String? ?? '',
      thumbUrl: json['thumbUrl'] as String?,
      localThumbPath: json['localThumbPath'] as String?,
      showThumbUrl: json['showThumbUrl'] as String?,
      localShowThumbPath: json['localShowThumbPath'] as String?,
      showSummary: json['showSummary'] as String?,
      artUrl: json['artUrl'] as String?,
      localArtPath: json['localArtPath'] as String?,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      localFilePath: json['localFilePath'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
      serverType: json['serverType'] as String? ?? 'plex',
      headers: (json['headers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.failed,
      ),
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      error: json['error'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
    );
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();

  DownloadService._internal();

  bool _initialized = false;
  String? _downloadDirPath;
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, bool> _serverPermissionCache = {};
  Timer? _notifyThrottle;

  bool get isInitialized => _initialized;
  List<DownloadTask> get tasks => _tasks.values.toList();
  List<DownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isRunning).toList();

  Future<void> init() async {
    if (_initialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(docDir.path, 'plix_downloads'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      _downloadDirPath = targetDir.path;

      // Load index
      final indexFile = File(p.join(_downloadDirPath!, 'downloads_index.json'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final task = DownloadTask.fromJson(item);
            // Verify file exists on disk
            final file = File(task.localFilePath);
            if (task.status == DownloadStatus.completed && !file.existsSync()) {
              task.status = DownloadStatus.failed;
              task.error = 'File removed from disk';
            } else if (task.isRunning) {
              // Interrupted during prior app session
              task.status = DownloadStatus.cancelled;
            }
            _tasks[task.ratingKey] = task;
          }
        }
      }
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[DownloadService] Error initializing: $e');
    }
  }

  Future<String> getDownloadDir() async {
    if (_downloadDirPath != null) return _downloadDirPath!;
    final docDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(docDir.path, 'plix_downloads'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    _downloadDirPath = targetDir.path;
    return _downloadDirPath!;
  }

  Future<void> _saveIndex() async {
    try {
      final dir = await getDownloadDir();
      final indexFile = File(p.join(dir, 'downloads_index.json'));
      final list = _tasks.values.map((t) => t.toJson()).toList();
      await indexFile.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('[DownloadService] Error saving index: $e');
    }
  }

  DownloadTask? getTask(String ratingKey) {
    if (_tasks.containsKey(ratingKey)) return _tasks[ratingKey];
    final cleanKey = ratingKey.replaceAll('/library/metadata/', '').replaceAll('jellyfin_', '');
    if (_tasks.containsKey(cleanKey)) return _tasks[cleanKey];
    for (final t in _tasks.values) {
      final tClean = t.ratingKey.replaceAll('/library/metadata/', '').replaceAll('jellyfin_', '');
      if (tClean == cleanKey) return t;
    }
    return null;
  }

  bool isDownloaded(String ratingKey) {
    final task = getTask(ratingKey);
    if (task == null || task.status != DownloadStatus.completed) return false;
    final file = File(task.localFilePath);
    return file.existsSync();
  }

  bool isDownloading(String ratingKey) {
    final task = getTask(ratingKey);
    return task != null && task.isRunning;
  }

  String? getDownloadedFilePath(String ratingKey) {
    final task = getTask(ratingKey);
    if (task != null && task.status == DownloadStatus.completed) {
      final file = File(task.localFilePath);
      if (file.existsSync()) {
        return task.localFilePath;
      }
    }
    return null;
  }

  Future<bool> canUserDownload(PlexServer server) async {
    // Downloads feature is completely disabled on TV interfaces
    if (PlixDeviceHelper.isTelevision) return false;

    if (server.isPlex) {
      return server.canDownload;
    }

    if (server.isJellyfin) {
      if (_serverPermissionCache.containsKey(server.clientIdentifier)) {
        return _serverPermissionCache[server.clientIdentifier]!;
      }

      final baseUrl = server.activeConnectionUri ??
          (server.connections.isNotEmpty ? server.connections.first.uri : '');
      final userId = server.userId;
      if (baseUrl.isEmpty) {
        return false;
      }
      if (userId == null || userId.isEmpty) {
        _serverPermissionCache[server.clientIdentifier] = true;
        return true;
      }

      try {
        final uri = Uri.parse('$baseUrl/Users/$userId?api_key=${server.accessToken}');
        final res = await http.get(uri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final policy = data['Policy'] as Map<String, dynamic>?;
          if (policy != null) {
            final isAdmin = policy['IsAdministrator'] == true;
            final canDl = policy['EnableContentDownloading'] == true;
            final allowed = isAdmin || canDl;
            _serverPermissionCache[server.clientIdentifier] = allowed;
            return allowed;
          }
        }
      } catch (e) {
        debugPrint('[DownloadService] Error checking Jellyfin download permission: $e');
      }

      // Default to true if not explicitly restricted
      _serverPermissionCache[server.clientIdentifier] = true;
      return true;
    }

    return false;
  }

  Future<void> startDownload({
    required PlexMediaItem item,
    required PlexServer server,
    required String downloadUrl,
    String? thumbUrl,
    String? showThumbUrl,
    String? artUrl,
    String? showSummary,
    Map<String, String>? headers,
  }) async {
    if (isDownloading(item.ratingKey) || isDownloaded(item.ratingKey)) {
      return;
    }

    final dir = await getDownloadDir();
    final ext = item.container != null && item.container!.isNotEmpty ? '.${item.container}' : '.mp4';
    final cleanKey = item.ratingKey.replaceAll('/', '_');
    final localFilePath = p.join(dir, '$cleanKey$ext');
    final localThumbPath = p.join(dir, '${cleanKey}_thumb.jpg');
    final localShowThumbPath = showThumbUrl != null && showThumbUrl.isNotEmpty
        ? p.join(dir, '${cleanKey}_show_thumb.jpg')
        : null;
    final localArtPath = artUrl != null && artUrl.isNotEmpty
        ? p.join(dir, '${cleanKey}_art.jpg')
        : null;

    final task = DownloadTask(
      ratingKey: item.ratingKey,
      title: item.title,
      type: item.type,
      seriesTitle: item.grandparentTitle,
      seasonTitle: item.parentTitle,
      seasonIndex: item.parentIndex,
      episodeIndex: item.index,
      seriesRatingKey: item.grandparentRatingKey,
      seasonRatingKey: item.parentRatingKey,
      duration: item.duration,
      year: item.year,
      summary: item.summary,
      thumbUrl: thumbUrl ?? item.thumb,
      localThumbPath: localThumbPath,
      showThumbUrl: showThumbUrl,
      localShowThumbPath: localShowThumbPath,
      showSummary: showSummary,
      artUrl: artUrl,
      localArtPath: localArtPath,
      downloadUrl: downloadUrl,
      localFilePath: localFilePath,
      serverId: server.clientIdentifier,
      serverName: server.name,
      serverType: server.serverType,
      headers: headers,
      status: DownloadStatus.downloading,
    );

    _tasks[item.ratingKey] = task;
    await _saveIndex();
    notifyListeners();

    // Download thumbnail in background
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      _downloadThumbnail(thumbUrl, localThumbPath, headers);
    }
    if (showThumbUrl != null && showThumbUrl.isNotEmpty && localShowThumbPath != null) {
      _downloadThumbnail(showThumbUrl, localShowThumbPath, headers);
    }
    if (artUrl != null && artUrl.isNotEmpty && localArtPath != null) {
      _downloadThumbnail(artUrl, localArtPath, headers);
    }

    // Start video file download asynchronously
    _executeDownload(task);
  }

  Future<void> _downloadThumbnail(String url, String savePath, Map<String, String>? headers) async {
    try {
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final f = File(savePath);
        await f.writeAsBytes(res.bodyBytes);
      }
    } catch (_) {}
  }

  static const MethodChannel _nativeChannel = MethodChannel('com.plix.plix/downloads');

  Future<void> _updateForegroundService({DownloadTask? completedTask}) async {
    if (!Platform.isAndroid || PlixDeviceHelper.isTelevision) return;
    try {
      final active = activeTasks;
      if (active.isNotEmpty) {
        final current = active.first;
        final pct = (current.progress * 100).toInt().clamp(0, 100);
        final title = current.seriesTitle != null && current.seriesTitle!.isNotEmpty
            ? '${current.seriesTitle} - ${current.title}'
            : current.title;
        final text = active.length > 1
            ? 'Downloading $pct% • +${active.length - 1} more in queue'
            : 'Downloading $pct%...';
        await _nativeChannel.invokeMethod('startForeground', {
          'title': title,
          'text': text,
          'progress': pct,
          'indeterminate': current.totalBytes <= 0,
        });
      } else if (completedTask != null) {
        final title = completedTask.seriesTitle != null && completedTask.seriesTitle!.isNotEmpty
            ? '${completedTask.seriesTitle} - ${completedTask.title}'
            : completedTask.title;
        await _nativeChannel.invokeMethod('notifyComplete', {
          'title': 'Download Complete',
          'text': '$title is ready to watch. Tap to dismiss.',
        });
      } else {
        await _nativeChannel.invokeMethod('stopForeground');
      }
    } catch (_) {}
  }

  Future<void> _executeDownload(DownloadTask task) async {
    _updateForegroundService();

    final partFile = File('${task.localFilePath}.part');
    int retryCount = 0;
    const maxRetries = 5;

    while (retryCount <= maxRetries) {
      if (task.status == DownloadStatus.cancelled) {
        _updateForegroundService();
        break;
      }

      final client = http.Client();
      task._httpClient = client;
      IOSink? sink;

      try {
        int existingBytes = 0;
        if (await partFile.exists()) {
          existingBytes = await partFile.length();
        }

        String currentUrl = task.downloadUrl;
        // If Jellyfin fallback needed on retry
        if (task.serverType == 'jellyfin' && retryCount > 0 && currentUrl.contains('/Items/') && currentUrl.contains('/Download')) {
          final cleanId = task.ratingKey.replaceFirst('jellyfin_', '');
          final base = currentUrl.split('/Items/').first;
          final token = task.headers?['X-Emby-Token'] ?? '';
          currentUrl = '$base/Videos/$cleanId/stream?static=true&api_key=$token';
          task.downloadUrl = currentUrl;
        }

        final uri = Uri.parse(currentUrl);
        final request = http.Request('GET', uri);
        if (task.headers != null) {
          request.headers.addAll(task.headers!);
        }

        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        final response = await client.send(request);

        // Check for Jellyfin fallback on 400/404/403/500
        if ((response.statusCode == 400 || response.statusCode == 404 || response.statusCode == 403 || response.statusCode == 500) &&
            task.serverType == 'jellyfin' &&
            currentUrl.contains('/Items/') && currentUrl.contains('/Download')) {
          client.close();
          final cleanId = task.ratingKey.replaceFirst('jellyfin_', '');
          final base = currentUrl.split('/Items/').first;
          final token = task.headers?['X-Emby-Token'] ?? '';
          task.downloadUrl = '$base/Videos/$cleanId/stream?static=true&api_key=$token';
          retryCount++;
          continue;
        }

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Download failed with HTTP ${response.statusCode}');
        }

        final isPartial = response.statusCode == 206;
        if (isPartial && existingBytes > 0) {
          task.receivedBytes = existingBytes;
          final contentLen = response.contentLength ?? 0;
          if (task.totalBytes <= 0 || task.totalBytes < existingBytes + contentLen) {
            task.totalBytes = existingBytes + contentLen;
          }
          sink = partFile.openWrite(mode: FileMode.append);
        } else {
          task.receivedBytes = 0;
          task.totalBytes = response.contentLength ?? 0;
          if (await partFile.exists()) await partFile.delete();
          sink = partFile.openWrite(mode: FileMode.write);
        }

        task.status = DownloadStatus.downloading;
        _saveIndex();
        notifyListeners();

        await for (final chunk in response.stream) {
          if (task.status == DownloadStatus.cancelled) break;
          sink.add(chunk);
          task.receivedBytes += chunk.length;
          _throttledNotify();
        }

        await sink.flush();
        await sink.close();
        sink = null;

        if (task.status == DownloadStatus.cancelled) {
          if (await partFile.exists()) await partFile.delete();
          await _saveIndex();
          notifyListeners();
          _updateForegroundService();
          return;
        }

        // Verify file length if totalBytes is known
        if (task.totalBytes > 0 && task.receivedBytes < task.totalBytes) {
          throw Exception('Incomplete download: received ${task.receivedBytes} of ${task.totalBytes} bytes');
        }

        // Rename .part to final
        final finalFile = File(task.localFilePath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await partFile.rename(task.localFilePath);

        task.status = DownloadStatus.completed;
        task.completedAt = DateTime.now();
        await _saveIndex();
        notifyListeners();
        _updateForegroundService(completedTask: task);
        return; // Download succeeded
      } catch (e) {
        debugPrint('[DownloadService] Download attempt ${retryCount + 1} for ${task.title} error: $e');
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
        }
        client.close();
        task._httpClient = null;

        if (task.status == DownloadStatus.cancelled) {
          if (await partFile.exists()) await partFile.delete();
          await _saveIndex();
          notifyListeners();
          _updateForegroundService();
          return;
        }

        retryCount++;
        if (retryCount <= maxRetries) {
          debugPrint('[DownloadService] Background download interrupted, retrying attempt $retryCount in ${retryCount * 2}s...');
          await Future.delayed(Duration(seconds: retryCount * 2));
        } else {
          // Exceeded retries, mark as failed but keep .part file so it can be resumed
          task.status = DownloadStatus.failed;
          task.error = e.toString();
          await _saveIndex();
          notifyListeners();
          _updateForegroundService();
          return;
        }
      } finally {
        client.close();
        task._httpClient = null;
      }
    }
  }

  void _throttledNotify() {
    if (_notifyThrottle?.isActive ?? false) return;
    _notifyThrottle = Timer(const Duration(milliseconds: 300), () {
      notifyListeners();
      _updateForegroundService();
    });
  }

  Future<void> cancelDownload(String ratingKey) async {
    final task = _tasks[ratingKey];
    if (task == null) return;
    task.status = DownloadStatus.cancelled;
    task._httpClient?.close();
    task._httpClient = null;

    final partFile = File('${task.localFilePath}.part');
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }

    _tasks.remove(ratingKey);
    await _saveIndex();
    notifyListeners();
    _updateForegroundService();
  }

  Future<void> deleteDownload(String ratingKey) async {
    final task = _tasks[ratingKey];
    if (task != null) {
      if (task.isRunning) {
        await cancelDownload(ratingKey);
        return;
      }
      final file = File(task.localFilePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (task.localThumbPath != null) {
        final tFile = File(task.localThumbPath!);
        if (await tFile.exists()) {
          try {
            await tFile.delete();
          } catch (_) {}
        }
      }
      _tasks.remove(ratingKey);
      await _saveIndex();
      notifyListeners();
    }
  }

  List<PlexMediaItem> getAllDownloadedItems() {
    final List<PlexMediaItem> items = [];
    for (final task in _tasks.values) {
      if (task.status == DownloadStatus.completed) {
        items.add(_taskToMediaItem(task));
      }
    }
    return items;
  }

  List<PlexMediaItem> getDownloadedMovies() {
    return _tasks.values
        .where((t) => t.status == DownloadStatus.completed && t.type == 'movie')
        .map(_taskToMediaItem)
        .toList();
  }

  List<PlexMediaItem> getDownloadedShows() {
    final Map<String, List<DownloadTask>> showTasks = {};
    for (final task in _tasks.values) {
      if (task.status == DownloadStatus.completed && task.type == 'episode') {
        final showKey = task.seriesRatingKey ?? task.seriesTitle ?? task.title;
        showTasks.putIfAbsent(showKey, () => []).add(task);
      }
    }

    final List<PlexMediaItem> shows = [];
    for (final entry in showTasks.entries) {
      final showKey = entry.key;
      final tasks = entry.value;
      final firstTask = tasks.first;

      String? showThumb;
      for (final t in tasks) {
        if (t.localShowThumbPath != null && File(t.localShowThumbPath!).existsSync()) {
          showThumb = t.localShowThumbPath;
          break;
        }
      }
      showThumb ??= tasks.map((t) => t.showThumbUrl).firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
      if (showThumb == null) {
        for (final t in tasks) {
          if (t.localThumbPath != null && File(t.localThumbPath!).existsSync()) {
            showThumb = t.localThumbPath;
            break;
          }
        }
      }
      showThumb ??= tasks.map((t) => t.thumbUrl).firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);

      String? showArt;
      for (final t in tasks) {
        if (t.localArtPath != null && File(t.localArtPath!).existsSync()) {
          showArt = t.localArtPath;
          break;
        }
      }
      showArt ??= tasks.map((t) => t.artUrl).firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
      showArt ??= showThumb;

      String? showSummary;
      for (final t in tasks) {
        if (t.showSummary != null && t.showSummary!.isNotEmpty) {
          showSummary = t.showSummary;
          break;
        }
      }

      final subtitle = tasks.length == 1
          ? firstTask.title
          : '${tasks.length} Episodes';

      final item = PlexMediaItem(
        ratingKey: showKey,
        key: showKey,
        title: firstTask.seriesTitle ?? firstTask.title,
        type: 'show',
        summary: showSummary ?? '',
        year: firstTask.year,
        thumb: showThumb,
        art: showArt,
        addedSubtitle: subtitle,
        grandparentTitle: null,
        grandparentRatingKey: showKey,
        serverId: firstTask.serverId,
        server: PlexServer(
          name: firstTask.serverName,
          clientIdentifier: firstTask.serverId,
          accessToken: '',
          owned: true,
          connections: [],
          serverType: firstTask.serverType,
        ),
      );
      shows.add(item);
    }
    return shows;
  }

  List<PlexMediaItem> getDownloadedEpisodesForShow(String showRatingKey) {
    return _tasks.values
        .where((t) =>
            t.status == DownloadStatus.completed &&
            t.type == 'episode' &&
            (t.seriesRatingKey == showRatingKey || (t.seriesRatingKey == null && t.seriesTitle == showRatingKey)))
        .map(_taskToMediaItem)
        .toList();
  }

  PlexMediaItem _taskToMediaItem(DownloadTask task) {
    return PlexMediaItem(
      ratingKey: task.ratingKey,
      key: task.ratingKey,
      title: task.title,
      type: task.type,
      summary: task.summary,
      year: task.year,
      duration: task.duration,
      thumb: (task.localThumbPath != null && File(task.localThumbPath!).existsSync())
          ? task.localThumbPath
          : task.thumbUrl,
      art: (task.localArtPath != null && File(task.localArtPath!).existsSync())
          ? task.localArtPath
          : task.artUrl,
      grandparentTitle: task.seriesTitle,
      parentTitle: task.seasonTitle,
      parentIndex: task.seasonIndex,
      index: task.episodeIndex,
      grandparentRatingKey: task.seriesRatingKey,
      parentRatingKey: task.seasonRatingKey,
      filePath: task.localFilePath,
      serverId: task.serverId,
      server: PlexServer(
        name: task.serverName,
        clientIdentifier: task.serverId,
        accessToken: '',
        owned: true,
        connections: [],
        serverType: task.serverType,
      ),
    );
  }
}
