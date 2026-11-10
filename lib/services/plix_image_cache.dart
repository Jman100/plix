import 'package:flutter/widgets.dart';

/// Central limits for decoded artwork and Flutter's shared image cache.
///
/// Plex artwork can arrive as full-resolution images. Decoding those
/// at their intrinsic size can exhaust memory on a 1-2 GB TV, so every artwork
/// widget should request and decode at its display size.
class PlixImageCache {
  PlixImageCache._();

  /// Keep the shared decoded-image cache compact to leave room for video playback,
  /// UI textures, and prevent Android low-memory killer (LMK) aborts on low-RAM TVs.
  static const int maxCacheBytes = 32 * 1024 * 1024;
  static const int maxCacheImages = 60;

  static const int cardWidth = 320;
  static const int cardHeight = 480;
  static const int backdropWidth = 1920;
  static const int backdropHeight = 1080;
  static const int mobileHeroWidth = 800;
  static const int mobileHeroHeight = 450;

  static bool _configured = false;

  static void configure() {
    if (_configured) return;
    _configured = true;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = maxCacheImages;
    cache.maximumSizeBytes = maxCacheBytes;
    WidgetsBinding.instance.addObserver(_MemoryPressureObserver());
  }

  /// Drop decoded artwork after leaving a large grid or on memory pressure.
  static void trim() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
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

class _MemoryPressureObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PlixImageCache.trim();
  }
}
