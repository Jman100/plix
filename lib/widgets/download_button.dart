import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/download_service.dart';
import '../services/plix_device_helper.dart';
import '../services/plex_media_service.dart';
import 'plix_button.dart';

class DownloadButton extends StatefulWidget {
  final PlexMediaItem item;
  final PlexServer server;
  final PlexMediaService mediaService;
  final bool isWide;
  final bool isCircle;
  final bool isIconOnly;
  final FocusNode? focusNode;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const DownloadButton({
    super.key,
    required this.item,
    required this.server,
    required this.mediaService,
    this.isWide = false,
    this.isCircle = false,
    this.isIconOnly = false,
    this.focusNode,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _canDownload = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    DownloadService.instance.addListener(_onDownloadServiceUpdate);
  }

  @override
  void didUpdateWidget(covariant DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.ratingKey != widget.item.ratingKey ||
        oldWidget.server.clientIdentifier != widget.server.clientIdentifier) {
      _checkPermission();
    }
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadServiceUpdate);
    super.dispose();
  }

  void _onDownloadServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPermission() async {
    if (PlixDeviceHelper.isTelevision) {
      if (mounted) setState(() => _canDownload = false);
      return;
    }
    final allowed = await DownloadService.instance.canUserDownload(widget.server);
    if (mounted) {
      setState(() {
        _canDownload = allowed;
        _checkingPermission = false;
      });
    }
  }

  Future<void> _startDownload() async {
    final item = widget.item;
    final server = widget.server;
    String? downloadUrl;

    Map<String, String>? headers;
    if (server.isPlex) {
      final partKey = item.partKey;
      if (partKey != null && partKey.isNotEmpty) {
        final directUrl = widget.mediaService.buildDirectPlayUrl(partKey);
        downloadUrl = directUrl.contains('?') ? '$directUrl&download=1' : '$directUrl?download=1';
      }
    } else if (server.isJellyfin) {
      final base = server.activeConnectionUri ??
          (server.connections.isNotEmpty ? server.connections.first.uri : widget.mediaService.baseUrl);
      final token = server.accessToken;
      final cleanId = item.ratingKey.replaceFirst('jellyfin_', '');
      downloadUrl = '$base/Items/$cleanId/Download?api_key=$token';
      headers = {
        if (token.isNotEmpty) 'X-Emby-Token': token,
      };
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download URL unavailable for this media file.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final thumb = item.isEpisode
        ? (item.thumb ?? item.art ?? item.posterThumb)
        : (item.posterThumb ?? item.thumb);
    final thumbUrl = (thumb != null && thumb.isNotEmpty)
        ? widget.mediaService.buildImageUrl(thumb, width: 300, height: 450)
        : null;
    final showPoster = item.grandparentThumb ?? item.posterThumb;
    final showThumbUrl = (showPoster != null && showPoster.isNotEmpty)
        ? widget.mediaService.buildImageUrl(showPoster, width: 400, height: 600)
        : null;
    final art = item.art;
    final artUrl = (art != null && art.isNotEmpty)
        ? widget.mediaService.buildImageUrl(art, width: 1920, height: 1080)
        : null;

    String? showSummary;
    if (item.isEpisode && item.grandparentRatingKey != null && item.grandparentRatingKey!.isNotEmpty) {
      try {
        final showMeta = await widget.mediaService.getItemMetadata(item.grandparentRatingKey!);
        if (showMeta.summary.isNotEmpty) {
          showSummary = showMeta.summary;
        }
      } catch (_) {}
    }
    showSummary ??= item.summary;

    await DownloadService.instance.startDownload(
      item: item,
      server: server,
      downloadUrl: downloadUrl,
      thumbUrl: thumbUrl,
      showThumbUrl: showThumbUrl,
      artUrl: artUrl,
      showSummary: showSummary,
      headers: headers,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading "${item.title}"...'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PlixTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Download?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${widget.item.title}" from this device?',
          style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.deleteDownload(widget.item.ratingKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download deleted.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PlixTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Cancel Download?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to cancel downloading "${widget.item.title}"?',
          style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Downloading', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Download', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.cancelDownload(widget.item.ratingKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlixDeviceHelper.isTelevision || (!_canDownload && !_checkingPermission)) {
      return const SizedBox.shrink();
    }

    final isDownloaded = DownloadService.instance.isDownloaded(widget.item.ratingKey);
    final task = DownloadService.instance.getTask(widget.item.ratingKey);
    final isDownloading = task != null && task.isRunning;

    // 1. Downloading State
    if (isDownloading) {
      final progress = task.progress;
      final pct = (progress * 100).toInt();

      if (widget.isIconOnly) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _confirmCancel,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                  ),
                  const Icon(Icons.close_rounded, size: 10, color: Colors.white70),
                ],
              ),
            ),
          ),
        );
      }

      if (widget.isCircle) {
        return GestureDetector(
          onTap: _confirmCancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PlixTheme.card,
                  border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
                      ),
                    ),
                    const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$pct%',
                style: TextStyle(
                  color: PlixTheme.plexGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }

      if (widget.isWide) {
        return Container(
          width: double.infinity,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: PlixTheme.isOLED ? const Color(0xFF141416) : PlixTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              children: [
                // Fill progress bar
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.03, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: PlixTheme.plexGold.withOpacity(0.35),
                    ),
                  ),
                ),
                // Content overlay
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PlixTheme.plexGold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            task.totalBytes > 0
                                ? 'Downloading $pct% • ${(task.receivedBytes / 1048576).toStringAsFixed(1)} / ${(task.totalBytes / 1048576).toStringAsFixed(1)} MB'
                                : 'Downloading $pct%...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _confirmCancel,
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        return InkWell(
          onTap: _confirmCancel,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: PlixTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PlixTheme.plexGold.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PlixTheme.plexGold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct%',
                  style: TextStyle(color: PlixTheme.plexGold, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
              ],
            ),
          ),
        );
      }
    }

    // 2. Downloaded State -> Delete Button
    if (isDownloaded) {
      if (widget.isIconOnly) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _confirmDelete,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.download_done_rounded,
              size: 22,
              color: PlixTheme.plexGold,
            ),
          ),
        );
      }

      if (widget.isCircle) {
        return GestureDetector(
          onTap: _confirmDelete,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PlixTheme.card,
                  border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5)),
                ),
                child: Center(
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 20,
                    color: PlixTheme.plexGold,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Downloaded',
                style: TextStyle(
                  color: PlixTheme.plexGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }

      if (widget.isWide) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
            label: const Text(
              'Delete Download',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.5)),
              backgroundColor: const Color(0xFFEF4444).withOpacity(0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );
      } else {
        return PlixButton(
          isPrimary: false,
          focusNode: widget.focusNode,
          fontSize: 12.0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
          label: 'Delete',
          textColor: const Color(0xFFEF4444),
          borderColor: const Color(0xFFEF4444).withOpacity(0.5),
          backgroundColor: const Color(0xFFEF4444).withOpacity(0.08),
          onLeft: widget.onLeft,
          onRight: widget.onRight,
          onUp: widget.onUp,
          onDown: widget.onDown,
          onPressed: _confirmDelete,
        );
      }
    }

    // 3. Not Downloaded State -> Download Button
    if (widget.isIconOnly) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startDownload,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.download_rounded,
            size: 22,
            color: Colors.white70,
          ),
        ),
      );
    }

    if (widget.isCircle) {
      return GestureDetector(
        onTap: _startDownload,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PlixTheme.card,
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Download',
              style: TextStyle(
                color: PlixTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.isWide) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: OutlinedButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
          label: const Text(
            'Download',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            side: const BorderSide(color: Colors.white24),
            backgroundColor: PlixTheme.isOLED ? const Color(0xFF141416) : PlixTheme.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    } else {
      return PlixButton(
        isPrimary: false,
        focusNode: widget.focusNode,
        fontSize: 12.0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        icon: const Icon(Icons.download_rounded, size: 16),
        label: 'Download',
        onLeft: widget.onLeft,
        onRight: widget.onRight,
        onUp: widget.onUp,
        onDown: widget.onDown,
        onPressed: _startDownload,
      );
    }
  }
}
