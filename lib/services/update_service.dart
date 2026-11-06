import 'plix_device_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../widgets/plix_button.dart';

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => message;
}

class UpdateInfo {
  final String version;
  final int versionCode;
  final String apkUrl;
  final String windowsUrl;
  final String linuxUrl;
  final String linuxArchUrl;
  final String releaseNotes;
  final String releaseDate;
  final bool hasUpdate;
  final String sha256;
  final String apkSha256;
  final String windowsSha256;
  final String linuxSha256;
  final String linuxArchSha256;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.windowsUrl = '',
    this.linuxUrl = '',
    this.linuxArchUrl = '',
    this.releaseNotes = '',
    this.releaseDate = '',
    required this.hasUpdate,
    this.sha256 = '',
    this.apkSha256 = '',
    this.windowsSha256 = '',
    this.linuxSha256 = '',
    this.linuxArchSha256 = '',
  });

  String getExpectedSha256ForTarget(String targetFileName) {
    final lower = targetFileName.toLowerCase();
    if (lower.endsWith('.apk')) {
      return apkSha256.isNotEmpty ? apkSha256 : sha256;
    }
    if (lower.endsWith('.exe')) {
      return windowsSha256.isNotEmpty ? windowsSha256 : sha256;
    }
    if (lower.contains('.pkg.tar')) {
      return linuxArchSha256.isNotEmpty ? linuxArchSha256 : sha256;
    }
    if (lower.endsWith('.deb')) {
      return linuxSha256.isNotEmpty ? linuxSha256 : sha256;
    }
    return sha256;
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {required String currentVersion, required int currentVersionCode}) {
    final v = json['version']?.toString() ?? '1.0.0';
    final vc = (json['versionCode'] is num)
        ? (json['versionCode'] as num).toInt()
        : int.tryParse(json['versionCode']?.toString() ?? '') ?? 1;
    final apk = json['apkUrl']?.toString() ?? 'https://github.com/Jman100/plix/releases/latest/download/plix_android.apk';
    final winArm64Url = json['windowsArm64Url']?.toString();
    final isArm64 = Platform.isWindows &&
        ((Platform.environment['PROCESSOR_ARCHITECTURE']?.toUpperCase() == 'ARM64') ||
         (Platform.environment['PROCESSOR_ARCHITEW6432']?.toUpperCase() == 'ARM64'));
    final winUrl = (isArm64 && winArm64Url != null && winArm64Url.isNotEmpty)
        ? winArm64Url
        : (json['windowsUrl']?.toString() ?? 'https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe');

    final linuxDeb = json['linuxUrl']?.toString() ?? 'https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb';
    final linuxArch = json['linuxArchUrl']?.toString() ?? 'https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst';
    final isArch = UpdateService.isArchLinux();
    final effectiveLinux = isArch ? linuxArch : linuxDeb;

    final notes = json['releaseNotes']?.toString() ?? '';
    final date = json['releaseDate']?.toString() ?? '';

    final sha = json['sha256']?.toString() ?? '';
    final apkSha = json['apkSha256']?.toString() ?? '';
    final winSha = json['windowsSha256']?.toString() ?? '';
    final linuxSha = json['linuxSha256']?.toString() ?? '';
    final linuxArchSha = json['linuxArchSha256']?.toString() ?? '';

    final cmp = UpdateService.compareSemVer(v, currentVersion);
    final hasUpdate = cmp > 0 || (cmp == 0 && vc > currentVersionCode);

    return UpdateInfo(
      version: v,
      versionCode: vc,
      apkUrl: apk,
      windowsUrl: winUrl,
      linuxUrl: effectiveLinux,
      linuxArchUrl: linuxArch,
      releaseNotes: notes,
      releaseDate: date,
      hasUpdate: hasUpdate,
      sha256: sha,
      apkSha256: apkSha,
      windowsSha256: winSha,
      linuxSha256: linuxSha,
      linuxArchSha256: linuxArchSha,
    );
  }
}

class UpdateService {
  static const String manifestUrl = 'https://raw.githubusercontent.com/Jman100/plix/main/web_site/plix.json';
  static const String githubReleaseManifestUrl = 'https://github.com/Jman100/plix/releases/latest/download/plix.json';
  static const String customDomainManifestUrl = 'https://plix.jman100.com/plix.json';
  static const String githubApiReleaseUrl = 'https://api.github.com/repos/Jman100/plix/releases/latest';
  static String _currentVersion = '1.7.1';
  static int _currentVersionCode = 41;

  static String get currentVersion => _currentVersion;
  static int get currentVersionCode => _currentVersionCode;

  static Future<void> initVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _currentVersion = info.version;
      }
      final parsedCode = int.tryParse(info.buildNumber);
      if (parsedCode != null && parsedCode > 0) {
        _currentVersionCode = parsedCode;
      }
    } catch (_) {}
  }

  static const String _prefAutoCheckKey = 'auto_check_updates';
  static const MethodChannel _channel = MethodChannel('com.plix.plix/updater');
  static bool _isDownloadCancelled = false;
  static HttpClient? _activeDownloadClient;

  static void cancelDownload() {
    _isDownloadCancelled = true;
    try {
      _activeDownloadClient?.close(force: true);
    } catch (_) {}
  }

  static bool isArchLinux() {
    if (!Platform.isLinux) return false;
    try {
      if (File('/etc/arch-release').existsSync()) return true;
      for (final p in ['/etc/os-release', '/usr/lib/os-release']) {
        final f = File(p);
        if (f.existsSync()) {
          final content = f.readAsStringSync().toLowerCase();
          if (content.contains('id=arch') ||
              content.contains('id="arch"') ||
              content.contains('id_like=arch') ||
              content.contains('id_like="arch"') ||
              content.contains('id=manjaro') ||
              content.contains('id="manjaro"') ||
              content.contains('id=endeavouros') ||
              content.contains('id="endeavouros"') ||
              content.contains('id=garuda') ||
              content.contains('id="garuda"') ||
              content.contains('id=artix') ||
              content.contains('id="artix"') ||
              content.contains('id=cachyos') ||
              content.contains('id="cachyos"') ||
              content.contains('id=archcraft') ||
              content.contains('id="archcraft"') ||
              content.contains('id=blendos') ||
              content.contains('id="blendos"') ||
              content.contains('id=chimeraos') ||
              content.contains('id="chimeraos"') ||
              content.contains('id=biglinux') ||
              content.contains('id="biglinux"') ||
              content.contains('id=steamos') ||
              content.contains('id="steamos"')) {
            return true;
          }
        }
      }
      if (File('/usr/bin/pacman').existsSync() ||
          File('/bin/pacman').existsSync() ||
          File('/usr/local/bin/pacman').existsSync()) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static int compareSemVer(String v1, String v2) {
    final clean1 = v1.trim().replaceFirst(RegExp(r'^v'), '');
    final clean2 = v2.trim().replaceFirst(RegExp(r'^v'), '');

    final parts1 = clean1.split('-');
    final parts2 = clean2.split('-');

    final nums1 = parts1[0].split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final nums2 = parts2[0].split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final n1 = i < nums1.length ? nums1[i] : 0;
      final n2 = i < nums2.length ? nums2[i] : 0;
      if (n1 > n2) return 1;
      if (n1 < n2) return -1;
    }

    final hasPre1 = parts1.length > 1;
    final hasPre2 = parts2.length > 1;
    if (hasPre1 && !hasPre2) return -1; // 1.8.0-beta < 1.8.0
    if (!hasPre1 && hasPre2) return 1;  // 1.8.0 > 1.8.0-beta
    if (hasPre1 && hasPre2) {
      return parts1[1].compareTo(parts2[1]);
    }
    return 0;
  }

  static bool isVersionNewer(String remote, String current) {
    return compareSemVer(remote, current) > 0;
  }

  static Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoCheckKey) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCheckKey, enabled);
  }

  static const Set<String> _trustedDownloadHosts = {
    'github.com',
    'api.github.com',
    'raw.githubusercontent.com',
    'objects.githubusercontent.com',
    'plix.jman100.com',
  };

  static bool isTrustedUpdateUri(Uri uri) {
    if (uri.scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (_trustedDownloadHosts.contains(host)) {
      return true;
    }
    if (host.endsWith('.github.com') || host.endsWith('.githubusercontent.com')) {
      return true;
    }
    return false;
  }

  static HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    // Strict TLS verification: standard OS trusted root CAs are enforced.
    // Self-signed certificates or host wildcards are completely disallowed for updates.
    return client;
  }

  static Future<UpdateInfo?> checkForUpdate() async {
    final candidateUrls = [
      githubReleaseManifestUrl,
      manifestUrl,
      customDomainManifestUrl,
    ];

    for (final url in candidateUrls) {
      final client = _createHttpClient();
      try {
        final uri = Uri.parse(url);
        final isGithubRelease = uri.host.contains('github.com') && uri.path.contains('releases');
        final manifestUri = isGithubRelease ? uri : Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}');
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
      } catch (_) {
      } finally {
        try { client.close(force: true); } catch (_) {}
      }
    }

    // Direct fallback to GitHub Releases API
    final ghClient = _createHttpClient();
    try {
      final request = await ghClient.getUrl(Uri.parse(githubApiReleaseUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Plix-App');
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tagName = json['tag_name']?.toString().replaceFirst(RegExp(r'^v'), '') ?? '1.0.0';
        final assets = json['assets'] as List<dynamic>? ?? [];
        String apkUrl = 'https://github.com/Jman100/plix/releases/latest/download/plix_android.apk';
        String windowsUrl = 'https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe';
        String linuxUrl = 'https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb';
        String linuxArchUrl = 'https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst';
        final isTv = PlixDeviceHelper.isTelevision;
        for (final a in assets) {
          final name = a['name']?.toString() ?? '';
          final dUrl = a['browser_download_url']?.toString();
          if (dUrl != null) {
            if (isTv) {
              if (name == 'plix_android_tv.apk') {
                apkUrl = dUrl;
              } else if (name == 'plix_android.apk' && !apkUrl.contains('_tv')) {
                apkUrl = dUrl;
              }
            } else {
              if (name == 'plix_android.apk') {
                apkUrl = dUrl;
              }
            }
            if (name == 'plix_windows.exe') {
              windowsUrl = dUrl;
            } else if (name == 'plix_linux.deb') {
              linuxUrl = dUrl;
            } else if (name == 'plix_linux_arch.pkg.tar.zst' || name.endsWith('.pkg.tar.zst')) {
              linuxArchUrl = dUrl;
            }
          }
        }
        final notes = json['body']?.toString() ?? '';
        final date = (json['published_at']?.toString() ?? '').split('T').first;
        final hasUpdate = isVersionNewer(tagName, currentVersion);
        final isArch = isArchLinux();
        return UpdateInfo(
          version: tagName,
          versionCode: currentVersionCode,
          apkUrl: apkUrl,
          windowsUrl: windowsUrl,
          linuxUrl: isArch ? linuxArchUrl : linuxUrl,
          linuxArchUrl: linuxArchUrl,
          releaseNotes: notes,
          releaseDate: date,
          hasUpdate: hasUpdate,
        );
      }
    } catch (_) {
    } finally {
      try { ghClient.close(force: true); } catch (_) {}
    }

    return null;
  }

  static Future<void> _downloadFileWithVerification({
    required Uri downloadUri,
    required File targetFile,
    required String? expectedSha256,
    required void Function(double progress) onProgress,
  }) async {
    if (!isTrustedUpdateUri(downloadUri)) {
      throw SecurityException(
        'Refusing to download update from untrusted or non-HTTPS source: $downloadUri',
      );
    }

    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    final isGithub = downloadUri.host.contains('github.com') || downloadUri.host.contains('githubusercontent.com');
    final effectiveUri = (isGithub || downloadUri.queryParameters.containsKey('v') || downloadUri.queryParameters.containsKey('t'))
        ? downloadUri
        : downloadUri.replace(queryParameters: {...downloadUri.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'});

    _isDownloadCancelled = false;
    final client = _createHttpClient();
    _activeDownloadClient = client;

    try {
      final request = await client.getUrl(effectiveUri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.headers.set('Pragma', 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to download update: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();
      Digest? computedDigest;
      final digestSink = ChunkedConversionSink<Digest>.withCallback((digests) {
        if (digests.isNotEmpty) {
          computedDigest = digests.first;
        }
      });
      final byteConversionSink = sha256.startChunkedConversion(digestSink);

      try {
        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          if (_isDownloadCancelled) {
            throw Exception('Download was cancelled by user.');
          }
          sink.add(chunk);
          byteConversionSink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress(receivedBytes / totalBytes);
          }
        }
        await sink.flush();
      } finally {
        byteConversionSink.close();
        await sink.close();
      }

      onProgress(1.0);

      final computedHash = (computedDigest?.toString() ?? '').toLowerCase();
      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        if (computedHash != expectedSha256.toLowerCase().trim()) {
          try {
            await targetFile.delete();
          } catch (_) {}
          throw SecurityException(
            'Security error: Update package checksum mismatch!\n'
            'Expected: $expectedSha256\n'
            'Actual:   $computedHash\n'
            'The downloaded file has been deleted for your safety.',
          );
        }
      }
    } finally {
      _activeDownloadClient = null;
      try { client.close(force: true); } catch (_) {}
    }
  }

  static Future<void> downloadAndInstall({
    required String apkUrl,
    String? windowsUrl,
    String? linuxUrl,
    String? linuxArchUrl,
    String? expectedSha256,
    UpdateInfo? updateInfo,
    required void Function(double progress) onProgress,
  }) async {
    if (Platform.isLinux) {
      final isArch = isArchLinux();
      final defaultUrl = isArch
          ? 'https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst'
          : 'https://github.com/Jman100/plix/releases/latest/download/plix_linux.deb';

      String downloadUrl = (linuxUrl != null && linuxUrl.isNotEmpty) ? linuxUrl : defaultUrl;

      // If running on Arch Linux, ensure we do not download a .deb file
      if (isArch && (downloadUrl.endsWith('.deb') || !downloadUrl.contains('.pkg.tar.zst'))) {
        downloadUrl = (linuxArchUrl != null && linuxArchUrl.isNotEmpty)
            ? linuxArchUrl
            : 'https://github.com/Jman100/plix/releases/latest/download/plix_linux_arch.pkg.tar.zst';
      }

      final isPkgTarZst = downloadUrl.contains('.pkg.tar.zst') || isArch;
      final fileName = isPkgTarZst ? 'plix_linux_arch.pkg.tar.zst' : 'plix_linux.deb';
      final tempDir = Directory.systemTemp.createTempSync('plix_update_');
      final targetFile = File('${tempDir.path}/$fileName');

      final shaToVerify = expectedSha256 ?? updateInfo?.getExpectedSha256ForTarget(fileName);
      await _downloadFileWithVerification(
        downloadUri: Uri.parse(downloadUrl),
        targetFile: targetFile,
        expectedSha256: shaToVerify,
        onProgress: onProgress,
      );

      bool opened = false;

      // Generate a standalone updater shell script that elevates via sudo/doas/pkexec,
      // runs pacman -U (or dpkg -i / rpm -U), shows progress interactively in a terminal,
      // restarts Plix on success, and pauses on error.
      final scriptFile = File('${tempDir.path}/install_update.sh');
      final scriptContent = '''#!/usr/bin/env bash
clear
echo "=========================================="
echo "          Plix Auto-Updater"
echo "=========================================="
echo ""
echo "Installing package:"
echo "  ${targetFile.path}"
echo ""

# Find elevation tool if not already root
ELEVATE=""
if [ "\$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        ELEVATE="sudo"
    elif command -v doas >/dev/null 2>&1; then
        ELEVATE="doas"
    elif command -v pkexec >/dev/null 2>&1; then
        ELEVATE="pkexec"
    fi
fi

INSTALL_SUCCESS=1
if [[ "${targetFile.path}" == *.pkg.tar* ]] || command -v pacman >/dev/null 2>&1; then
    echo "Running: \$ELEVATE pacman -U --noconfirm \"${targetFile.path}\""
    echo ""
    \$ELEVATE pacman -U --noconfirm "${targetFile.path}"
    if [ \$? -eq 0 ]; then
        INSTALL_SUCCESS=0
    fi
elif [[ "${targetFile.path}" == *.deb ]] || command -v dpkg >/dev/null 2>&1; then
    echo "Running: \$ELEVATE dpkg -i \"${targetFile.path}\""
    echo ""
    \$ELEVATE dpkg -i "${targetFile.path}"
    if [ \$? -eq 0 ]; then
        INSTALL_SUCCESS=0
    else
        if command -v apt-get >/dev/null 2>&1; then
            echo ""
            echo "Resolving missing dependencies with apt-get..."
            \$ELEVATE apt-get install -f -y
            if [ \$? -eq 0 ]; then
                INSTALL_SUCCESS=0
            fi
        fi
    fi
elif [[ "${targetFile.path}" == *.rpm ]] || command -v rpm >/dev/null 2>&1; then
    echo "Running: \$ELEVATE rpm -U \"${targetFile.path}\""
    echo ""
    \$ELEVATE rpm -U "${targetFile.path}"
    if [ \$? -eq 0 ]; then
        INSTALL_SUCCESS=0
    fi
fi

echo ""
if [ \$INSTALL_SUCCESS -eq 0 ]; then
    echo "=========================================="
    echo "  Plix updated successfully!"
    echo "  Restarting Plix..."
    echo "=========================================="
    sleep 1.2
    if command -v plix >/dev/null 2>&1; then
        nohup plix >/dev/null 2>&1 &
    elif [ -f /usr/bin/plix ]; then
        nohup /usr/bin/plix >/dev/null 2>&1 &
    elif [ -f /opt/plix/plix ]; then
        nohup /opt/plix/plix >/dev/null 2>&1 &
    fi
    exit 0
else
    echo "=========================================="
    echo "  Installation failed."
    echo "=========================================="
    echo "Press Enter to exit..."
    read -r
    exit 1
fi
''';
      await scriptFile.writeAsString(scriptContent);
      try {
        await Process.run('chmod', ['+x', scriptFile.path]);
      } catch (_) {}

      // Dedicated graphical package installer (e.g. Pamac on Manjaro / Arch)
      if (isArch && File('/usr/bin/pamac-installer').existsSync()) {
        try {
          await Process.start('pamac-installer', [targetFile.path], mode: ProcessStartMode.detached);
          opened = true;
        } catch (_) {}
      }

      // Launch terminal emulator running our installation script
      if (!opened) {
        final scriptPath = scriptFile.path;
        final terminalCommands = <List<String>>[
          if (Platform.environment['TERMINAL'] != null && Platform.environment['TERMINAL']!.isNotEmpty)
            [Platform.environment['TERMINAL']!, '-e', 'bash', scriptPath],
          ['xdg-terminal-exec', 'bash', scriptPath],
          ['konsole', '-e', 'bash', scriptPath],
          ['gnome-terminal', '--', 'bash', scriptPath],
          ['ptyxis', '--', 'bash', scriptPath],
          ['kgx', '-e', 'bash', scriptPath],
          ['xfce4-terminal', '-x', 'bash', scriptPath],
          ['mate-terminal', '-x', 'bash', scriptPath],
          ['alacritty', '-e', 'bash', scriptPath],
          ['kitty', 'bash', scriptPath],
          ['foot', 'bash', scriptPath],
          ['wezterm', 'start', '--', 'bash', scriptPath],
          ['ghostty', '-e', 'bash', scriptPath],
          ['terminator', '-x', 'bash', scriptPath],
          ['tilix', '-e', 'bash', scriptPath],
          ['lxterminal', '-e', 'bash', scriptPath],
          ['qterminal', '-e', 'bash', scriptPath],
          ['x-terminal-emulator', '-e', 'bash', scriptPath],
          ['xterm', '-e', 'bash', scriptPath],
          ['urxvt', '-e', 'bash', scriptPath],
          ['rxvt', '-e', 'bash', scriptPath],
        ];

        // First try checking known binary paths directly
        for (final cmd in terminalCommands) {
          final exe = cmd.first;
          final exists = File('/usr/bin/$exe').existsSync() ||
              File('/usr/local/bin/$exe').existsSync() ||
              File('/bin/$exe').existsSync();
          if (exists) {
            try {
              await Process.start(exe, cmd.sublist(1), mode: ProcessStartMode.detached);
              opened = true;
              break;
            } catch (_) {}
          }
        }

        // If not found in standard paths, try spawning directly through PATH lookup
        if (!opened) {
          for (final cmd in terminalCommands) {
            try {
              await Process.start(cmd.first, cmd.sublist(1), mode: ProcessStartMode.detached);
              opened = true;
              break;
            } catch (_) {}
          }
        }
      }

      if (!opened) {
        // Never call xdg-open on targetFile.path (.pkg.tar.zst) because desktop environments
        // associate archive formats with archive managers like Ark!
        // Instead, copy command to clipboard and inform the user.
        final installCmd = isArch
            ? 'sudo pacman -U "${targetFile.path}"'
            : 'sudo dpkg -i "${targetFile.path}"';
        try {
          await Clipboard.setData(ClipboardData(text: installCmd));
        } catch (_) {}
        try {
          await Process.start('xdg-open', [tempDir.path], mode: ProcessStartMode.detached);
        } catch (_) {}
        throw Exception(
          'Could not launch a terminal automatically. '
          'Please open a terminal and run:\n$installCmd\n'
          '(Command copied to clipboard)',
        );
      }

      await Future.delayed(const Duration(milliseconds: 600));
      exit(0);
    }

    if (Platform.isWindows) {
      final downloadUrl = (windowsUrl != null && windowsUrl.isNotEmpty)
          ? windowsUrl
          : 'https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe';
      final tempDir = Directory.systemTemp.createTempSync('plix_update_');
      final targetFile = File('${tempDir.path}\\plix_setup.exe');

      final shaToVerify = expectedSha256 ?? updateInfo?.getExpectedSha256ForTarget('plix_windows.exe');
      await _downloadFileWithVerification(
        downloadUri: Uri.parse(downloadUrl),
        targetFile: targetFile,
        expectedSha256: shaToVerify,
        onProgress: onProgress,
      );

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

    final shaToVerify = expectedSha256 ?? updateInfo?.getExpectedSha256ForTarget('plix_android.apk');
    await _downloadFileWithVerification(
      downloadUri: Uri.parse(apkUrl),
      targetFile: targetFile,
      expectedSha256: shaToVerify,
      onProgress: onProgress,
    );
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

  final FocusScopeNode _scopeNode = FocusScopeNode();
  final FocusNode _updateBtnFocusNode = FocusNode();
  final FocusNode _laterBtnFocusNode = FocusNode();
  final FocusNode _retryBtnFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();
  final ScrollController _notesScrollController = ScrollController();
  bool _hasMoreNotes = false;
  bool _isNotesFocused = false;

  void _ensureDialogFocused() {
    if (!mounted) return;
    if (!_notesFocusNode.hasFocus &&
        !_updateBtnFocusNode.hasFocus &&
        !_laterBtnFocusNode.hasFocus &&
        !_retryBtnFocusNode.hasFocus) {
      if (_updateBtnFocusNode.canRequestFocus) {
        FocusScope.of(context).requestFocus(_updateBtnFocusNode);
      } else if (_retryBtnFocusNode.canRequestFocus) {
        FocusScope.of(context).requestFocus(_retryBtnFocusNode);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _notesFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isNotesFocused = _notesFocusNode.hasFocus);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDialogFocused();
    });
    Future.delayed(const Duration(milliseconds: 60), _ensureDialogFocused);
    Future.delayed(const Duration(milliseconds: 180), _ensureDialogFocused);
    Future.delayed(const Duration(milliseconds: 350), _ensureDialogFocused);
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
    _scopeNode.dispose();
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
        linuxUrl: widget.updateInfo.linuxUrl,
        linuxArchUrl: widget.updateInfo.linuxArchUrl,
        updateInfo: widget.updateInfo,
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
        node: _scopeNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            final key = event.logicalKey;
            final isDialogFocused = _notesFocusNode.hasFocus ||
                _updateBtnFocusNode.hasFocus ||
                _laterBtnFocusNode.hasFocus ||
                _retryBtnFocusNode.hasFocus;

            if (!isDialogFocused) {
              _ensureDialogFocused();
              if (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter) {
                if (!_isDownloading && _errorMessage == null) {
                  _startDownload();
                }
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: (Platform.isWindows || Platform.isLinux) ? 640 : 520,
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
                          (Platform.isWindows || Platform.isLinux) ? 'Scroll for more' : 'Press \u2191 to scroll notes',
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
                  constraints: BoxConstraints(maxHeight: (Platform.isWindows || Platform.isLinux) ? 220 : 130),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'The system installer will open automatically once download finishes.',
                          style: TextStyle(color: PlixTheme.textSecondary, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          UpdateService.cancelDownload();
                          setState(() {
                            _isDownloading = false;
                            _errorMessage = 'Download was cancelled.';
                          });
                        },
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ],
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
