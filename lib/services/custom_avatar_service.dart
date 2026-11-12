import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/plix_profile.dart';

class CustomAvatarService {
  static String? _customAvatarsDirectoryPath;

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB limit
  static const Set<String> allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};

  /// Initialize and cache the custom avatars directory path.
  static Future<void> init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(path.join(appDir.path, 'custom_avatars'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _customAvatarsDirectoryPath = dir.path;
      debugPrint('[CustomAvatarService] Initialized custom avatars directory: ${dir.path}');
    } catch (e) {
      debugPrint('[CustomAvatarService] Error initializing custom avatars directory: $e');
    }
  }

  /// Whether the given [avatarId] corresponds to a custom avatar.
  static bool isCustomAvatar(String avatarId) {
    if (avatarId.isEmpty) return false;
    return avatarId.startsWith('custom_') ||
        avatarId.startsWith('/') ||
        avatarId.startsWith('\\') ||
        (avatarId.length >= 2 && avatarId[1] == ':');
  }

  /// Get the Directory object for storing custom avatars.
  static Future<Directory> getCustomAvatarsDirectory() async {
    if (_customAvatarsDirectoryPath != null) {
      final dir = Directory(_customAvatarsDirectoryPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, 'custom_avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _customAvatarsDirectoryPath = dir.path;
    return dir;
  }

  /// Synchronously resolve a custom avatar File if available.
  static File? getCustomAvatarFileSync(String avatarId) {
    if (!isCustomAvatar(avatarId)) return null;

    if (File(avatarId).isAbsolute) {
      final file = File(avatarId);
      return file.existsSync() ? file : null;
    }

    final dirPath = _customAvatarsDirectoryPath;
    if (dirPath == null) return null;
    final file = File(path.join(dirPath, avatarId));
    return file.existsSync() ? file : null;
  }

  /// Asynchronously resolve a custom avatar File.
  static Future<File?> getCustomAvatarFile(String avatarId) async {
    if (!isCustomAvatar(avatarId)) return null;

    if (File(avatarId).isAbsolute) {
      final file = File(avatarId);
      return await file.exists() ? file : null;
    }

    final dir = await getCustomAvatarsDirectory();
    final file = File(path.join(dir.path, avatarId));
    return await file.exists() ? file : null;
  }

  /// Retrieve all previously saved custom avatars.
  static Future<List<AvatarOption>> getSavedCustomAvatars() async {
    try {
      final dir = await getCustomAvatarsDirectory();
      final entities = dir.listSync();
      final List<AvatarOption> customList = [];

      entities.sort((a, b) {
        if (a is File && b is File) {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        }
        return 0;
      });

      for (final entity in entities) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final ext = path.extension(fileName).replaceFirst('.', '').toLowerCase();
          if (fileName.startsWith('custom_') && allowedExtensions.contains(ext)) {
            customList.add(AvatarOption(
              id: fileName,
              label: 'Custom',
              assetPath: entity.path,
            ));
          }
        }
      }
      return customList;
    } catch (e) {
      debugPrint('[CustomAvatarService] Error loading saved custom avatars: $e');
      return [];
    }
  }

  /// Validate image data: checks byte size and verifies codec decodability.
  static Future<void> validateImageBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw Exception('Image file is empty.');
    }
    if (bytes.length > maxFileSizeBytes) {
      final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('Image is too large ($sizeMb MB). Maximum allowed size is 10 MB.');
    }

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      frameInfo.image.dispose();
    } catch (e) {
      throw Exception('File is not a supported image format. Supported formats: PNG, JPG, WEBP, GIF.');
    }
  }

  /// Save raw image bytes to custom avatars folder and return the AvatarOption.
  static Future<AvatarOption> saveImageBytes(Uint8List bytes, {String? extension}) async {
    await validateImageBytes(bytes);

    String ext = (extension ?? 'png').replaceAll('.', '').toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      ext = 'png';
    }

    final dir = await getCustomAvatarsDirectory();
    final fileName = 'custom_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final targetFile = File(path.join(dir.path, fileName));
    await targetFile.writeAsBytes(bytes, flush: true);

    return AvatarOption(
      id: fileName,
      label: 'Custom',
      assetPath: targetFile.path,
    );
  }

  /// Pick an image file from the device storage.
  static Future<AvatarOption?> pickFromFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final picked = result.files.first;
    final bytes = await picked.xFile.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception('Could not read image data from selected file.');
    }

    String ext = picked.extension?.toLowerCase() ?? 'png';
    return await saveImageBytes(bytes, extension: ext);
  }

  /// Download an image from an HTTP/HTTPS URL and save it locally.
  static Future<AvatarOption> downloadFromUrl(String urlString) async {
    final trimmed = urlString.trim();
    if (trimmed.isEmpty) {
      throw Exception('Please enter an image URL.');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) {
      throw Exception('Please enter a valid HTTP or HTTPS image URL.');
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'Plix/1.0 (Custom Avatar Downloader)';
      request.headers['Accept'] = 'image/png,image/jpeg,image/webp,image/gif,image/*;q=0.9,*/*;q=0.8';

      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Connection timed out while downloading image.'),
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP error ${response.statusCode}.');
      }

      // Check Content-Type header if provided
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty &&
          !contentType.startsWith('image/') &&
          !contentType.contains('octet-stream')) {
        throw Exception('The URL does not point to an image (received: $contentType).');
      }

      // Check Content-Length header if provided
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxFileSizeBytes) {
        final sizeMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
        throw Exception('Image is too large ($sizeMb MB). Maximum allowed size is 10 MB.');
      }

      // Stream data with size limit guard
      final bytesBuilder = BytesBuilder(copy: false);
      int totalBytes = 0;
      await for (final chunk in response.stream) {
        totalBytes += chunk.length;
        if (totalBytes > maxFileSizeBytes) {
          throw Exception('Image exceeded maximum size limit of 10 MB during download.');
        }
        bytesBuilder.add(chunk);
      }

      final bytes = bytesBuilder.takeBytes();
      if (bytes.isEmpty) {
        throw Exception('Downloaded image file is empty.');
      }

      // Validate image bytes with codec
      await validateImageBytes(bytes);

      // Determine extension
      String ext = 'png';
      if (contentType.contains('jpeg') || contentType.contains('jpg')) {
        ext = 'jpg';
      } else if (contentType.contains('png')) {
        ext = 'png';
      } else if (contentType.contains('webp')) {
        ext = 'webp';
      } else if (contentType.contains('gif')) {
        ext = 'gif';
      } else {
        final pathExt = path.extension(uri.path).replaceFirst('.', '').toLowerCase();
        if (allowedExtensions.contains(pathExt)) {
          ext = pathExt;
        }
      }

      return await saveImageBytes(bytes, extension: ext);
    } finally {
      client.close();
    }
  }
}
