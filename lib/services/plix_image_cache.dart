import 'package:flutter/widgets.dart';

/// Central limits for decoded artwork and Flutter's shared image cache.
///
/// Plex Discover artwork can arrive as full-resolution images. Decoding those
/// at their intrinsic size can exhaust memory on a 2 GB TV, so every artwork
/// widget should request and decode at its display size.
class PlixImageCache {
  PlixImageCache._();

  /// Keep the shared decoded-image cache well below the default 100 MB and
  /// leave room for video playback and the rest of the Flutter app.
  static const int maxCacheBytes = 96 * 1024 * 1024;
  static const int maxCacheImages = 200;

  static const int cardWidth = 600;
  static const int cardHeight = 900;
  static const int backdropWidth = 1920;
  static const int backdropHeight = 1080;
  static const int mobileHeroWidth = 800;
  static const int mobileHeroHeight = 450;

  static void configure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = maxCacheImages;
    cache.maximumSizeBytes = maxCacheBytes;
  }

  /// Drop decoded artwork after leaving a large grid. Home reloads its own
  /// artwork immediately, so this frees the watchlist bitmaps before the
  /// transition back to Home starts decoding more images.
  static void trim() {
    PaintingBinding.instance.imageCache.clear();
  }

  /// Narrow a network request so posters are never fetched at absurd sizes.
  static int requestWidth(double logicalWidth, {int cap = cardWidth}) {
    return (logicalWidth * 2).round().clamp(1, cap).toInt();
  }

  static int requestHeight(double logicalHeight, {int cap = cardHeight}) {
    return (logicalHeight * 2).round().clamp(1, cap).toInt();
  }

  /// Physical pixels needed for a widget rendered at [logicalWidth].
  static int decodeWidth(
    BuildContext context,
    double logicalWidth, {
    int cap = cardWidth,
  }) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return (logicalWidth * dpr).ceil().clamp(1, cap).toInt();
  }

  static int decodeHeight(
    BuildContext context,
    double logicalHeight, {
    int cap = cardHeight,
  }) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return (logicalHeight * dpr).ceil().clamp(1, cap).toInt();
  }
}
