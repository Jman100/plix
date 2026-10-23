import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../widgets/plix_button.dart';

class UpdateInfo {
  final String version;
  final int versionCode;
  final String apkUrl;
  final String windowsUrl;
  final String releaseNotes;
  final String releaseDate;
  final bool hasUpdate;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.windowsUrl = '',
    this.releaseNotes = '',
    this.releaseDate = '',
    required this.hasUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {required String currentVersion, required int currentVersionCode}) {
    final v = json['version']?.toString() ?? '1.0.0';
    final vc = (json['versionCode'] is num)
        ? (json['versionCode'] as num).toInt()
        : int.tryParse(json['versionCode']?.toString() ?? '') ?? 1;
    final apk = json['apkUrl']?.toString() ?? 'https://plix.jman100.com/plix_android_tv.apk';
    final winUrl = json['windowsUrl']?.toString() ?? 'https://plix.jman100.com/plix_windows.exe';
    final notes = json['releaseNotes']?.toString() ?? '';
    final date = json['releaseDate']?.toString() ?? '';

    final hasUpdate = UpdateService.isVersionNewer(v, currentVersion) || (vc > currentVersionCode);

    return UpdateInfo(
      version: v,
      versionCode: vc,
      apkUrl: apk,
      windowsUrl: winUrl,
      releaseNotes: notes,
      releaseDate: date,
      hasUpdate: hasUpdate,
    );
  }
}

class UpdateService {
  static const String manifestUrl = 'https://plix.jman100.com/plix.json';
  // Keep in sync with the version in pubspec.yaml.
  static const String currentVersion = '1.2.7';
  static const int currentVersionCode = 26;

  static const String _prefAutoCheckKey = 'auto_check_updates';
  static const MethodChannel _channel = MethodChannel('com.plix.plix/updater');

  static bool isVersionNewer(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final currentParts = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      final maxLen = remoteParts.length > currentParts.length ? remoteParts.length : currentParts.length;
      for (int i = 0; i < maxLen; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoCheckKey) ?? false;
  }

  static Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCheckKey, enabled);
  }

  static HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (host.contains('plix.jman100.com') || host.contains('local.jman100.com') || host.contains('192.168.0.')) {
        return true;
      }
      return false;
    };
    return client;
  }

  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final client = _createHttpClient();
      final manifestUri = Uri.parse('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final request = await client.getUrl(manifestUri);
      request.headers.set('Accept', 'application/json');
      request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.headers.set('Pragma', 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        var body = await response.transform(utf8.decoder).join();
        if (body.startsWith('\uFEFF')) {
          body = body.substring(1);
        }
        final json = jsonDecode(body) as Map<String, dynamic>;
        return UpdateInfo.fromJson(
          json,
          currentVersion: currentVersion,
          currentVersionCode: currentVersionCode,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<void> downloadAndInstall({
    required String apkUrl,
    String? windowsUrl,
    required void Function(double progress) onProgress,
  }) async {
    if (Platform.isWindows) {
      final downloadUrl = (windowsUrl != null && windowsUrl.isNotEmpty)
          ? windowsUrl
          : 'https://plix.jman100.com/plix_windows.exe';
      final tempDir = Directory.systemTemp.createTempSync('plix_update_');
      final targetFile = File('${tempDir.path}\\plix_setup.exe');

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      final uri = Uri.parse(downloadUrl);
      final downloadUri = uri.queryParameters.containsKey('v') || uri.queryParameters.containsKey('t')
          ? uri
          : uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'});

      final client = _createHttpClient();
      final request = await client.getUrl(downloadUri);
      request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.headers.set('Pragma', 'no-cache');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Failed to download update: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress(receivedBytes / totalBytes);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      onProgress(1.0);

      // Launch the silent Inno Setup installer which will replace the files in
      // %LOCALAPPDATA%\Programs\Plix and restart Plix
      await Process.start(
        targetFile.path,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }

    final String cacheDirPath = await _channel.invokeMethod('getCacheDir');
    final filePath = '$cacheDirPath/plix_update.apk';
    final targetFile = File(filePath);

    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    final uri = Uri.parse(apkUrl);
    final downloadUri = uri.queryParameters.containsKey('v') || uri.queryParameters.containsKey('t')
        ? uri
        : uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'});

    final client = _createHttpClient();
    final request = await client.getUrl(downloadUri);
    request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    request.headers.set('Pragma', 'no-cache');
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('Failed to download update: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength;
    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    onProgress(1.0);
    await _channel.invokeMethod('installApk', {'filePath': targetFile.path});
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (ctx) => _UpdateDialog(updateInfo: updateInfo),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const _UpdateDialog({required this.updateInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _errorMessage;

  final FocusNode _updateBtnFocusNode = FocusNode();
  final FocusNode _laterBtnFocusNode = FocusNode();
  final FocusNode _retryBtnFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();
  final ScrollController _notesScrollController = ScrollController();
  bool _hasMoreNotes = false;
  bool _isNotesFocused = false;

  @override
  void initState() {
    super.initState();
    _notesFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isNotesFocused = _notesFocusNode.hasFocus);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notesScrollController.hasClients &&
          _notesScrollController.position.maxScrollExtent > 8) {
        if (mounted) setState(() => _hasMoreNotes = true);
      }
    });
    _notesScrollController.addListener(() {
      if (_notesScrollController.hasClients) {
        final atBottom = _notesScrollController.position.pixels >=
            _notesScrollController.position.maxScrollExtent - 8;
        if (_hasMoreNotes == atBottom && mounted) {
          setState(() => _hasMoreNotes = !atBottom);
        }
      }
    });
  }

  @override
  void dispose() {
    _notesFocusNode.dispose();
    _updateBtnFocusNode.dispose();
    _laterBtnFocusNode.dispose();
    _retryBtnFocusNode.dispose();
    _notesScrollController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      await UpdateService.downloadAndInstall(
        apkUrl: widget.updateInfo.apkUrl,
        windowsUrl: widget.updateInfo.windowsUrl,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
            });
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: $e';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _retryBtnFocusNode.canRequestFocus) {
            _retryBtnFocusNode.requestFocus();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PlixTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.5), width: 1.5),
      ),
      child: FocusScope(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.arrowDown ||
                key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight) {
              if (!_notesFocusNode.hasFocus &&
                  !_updateBtnFocusNode.hasFocus &&
                  !_laterBtnFocusNode.hasFocus &&
                  !_retryBtnFocusNode.hasFocus) {
                if (_updateBtnFocusNode.canRequestFocus) {
                  _updateBtnFocusNode.requestFocus();
                } else if (_retryBtnFocusNode.canRequestFocus) {
                  _retryBtnFocusNode.requestFocus();
                }
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: Platform.isWindows ? 640 : 520,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PlixTheme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4)),
                  ),
                  child: Icon(Icons.system_update_rounded, color: PlixTheme.plexGold, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update Available',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version ${widget.updateInfo.version} is now available (Current: v${UpdateService.currentVersion})',
                        style: const TextStyle(
                          color: PlixTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'What\'s New:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (_isNotesFocused)
                    Row(
                      children: [
                        Text(
                          'Use \u2191 / \u2193 on remote to scroll',
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 14,
                          color: PlixTheme.plexGold,
                        ),
                      ],
                    )
                  else if (_hasMoreNotes)
                    Row(
                      children: [
                        Text(
                          Platform.isWindows ? 'Scroll for more' : 'Press \u2191 to scroll notes',
                          style: TextStyle(
                            color: PlixTheme.plexGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: PlixTheme.plexGold,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Focus(
                focusNode: _notesFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.arrowUp) {
                      if (_notesScrollController.hasClients) {
                        _notesScrollController.animateTo(
                          (_notesScrollController.offset - 60).clamp(
                            0.0,
                            _notesScrollController.position.maxScrollExtent,
                          ),
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeOut,
                        );
                      }
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowDown) {
                      if (_notesScrollController.hasClients) {
                        final maxExt = _notesScrollController.position.maxScrollExtent;
                        if (_notesScrollController.offset >= maxExt - 8) {
                          _updateBtnFocusNode.requestFocus();
                        } else {
                          _notesScrollController.animateTo(
                            (_notesScrollController.offset + 60).clamp(0.0, maxExt),
                            duration: const Duration(milliseconds: 100),
                            curve: Curves.easeOut,
                          );
                        }
                      } else {
                        _updateBtnFocusNode.requestFocus();
                      }
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.space ||
                        key == LogicalKeyboardKey.gameButtonA ||
                        key == LogicalKeyboardKey.numpadEnter) {
                      _updateBtnFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    } else if (key == LogicalKeyboardKey.arrowLeft ||
                        key == LogicalKeyboardKey.arrowRight) {
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(maxHeight: Platform.isWindows ? 220 : 130),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PlixTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isNotesFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: _isNotesFocused ? 2.0 : 1.0,
                    ),
                  ),
                  child: Scrollbar(
                    controller: _notesScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 6,
                    radius: const Radius.circular(3),
                    child: SingleChildScrollView(
                      controller: _notesScrollController,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          widget.updateInfo.releaseNotes,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Downloading update...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: TextStyle(
                          color: PlixTheme.plexGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: PlixTheme.card,
                      valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The system installer will open automatically once download finishes.',
                    style: TextStyle(color: PlixTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ] else if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PlixButton(
                    focusNode: _laterBtnFocusNode,
                    isPrimary: false,
                    label: 'Cancel',
                    blockUp: widget.updateInfo.releaseNotes.isEmpty,
                    onUp: widget.updateInfo.releaseNotes.isNotEmpty
                        ? () => _notesFocusNode.requestFocus()
                        : null,
                    blockDown: true,
                    blockLeft: true,
                    onRight: () => _retryBtnFocusNode.requestFocus(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  PlixButton(
                    autofocus: true,
                    focusNode: _retryBtnFocusNode,
                    isPrimary: true,
                    label: 'Retry',
                    blockUp: widget.updateInfo.releaseNotes.isEmpty,
                    onUp: widget.updateInfo.releaseNotes.isNotEmpty
                        ? () => _notesFocusNode.requestFocus()
                        : null,
                    blockDown: true,
                    blockRight: true,
                    onLeft: () => _laterBtnFocusNode.requestFocus(),
                    onPressed: _startDownload,
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PlixButton(
                    focusNode: _laterBtnFocusNode,
                    isPrimary: false,
                    label: 'Later',
                    blockUp: widget.updateInfo.releaseNotes.isEmpty,
                    onUp: widget.updateInfo.releaseNotes.isNotEmpty
                        ? () => _notesFocusNode.requestFocus()
                        : null,
                    blockDown: true,
                    blockLeft: true,
                    onRight: () => _updateBtnFocusNode.requestFocus(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  PlixButton(
                    autofocus: true,
                    focusNode: _updateBtnFocusNode,
                    isPrimary: true,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: 'Update Now',
                    blockUp: widget.updateInfo.releaseNotes.isEmpty,
                    onUp: widget.updateInfo.releaseNotes.isNotEmpty
                        ? () => _notesFocusNode.requestFocus()
                        : null,
                    blockDown: true,
                    blockRight: true,
                    onLeft: () => _laterBtnFocusNode.requestFocus(),
                    onPressed: _startDownload,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }
}
