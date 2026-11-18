import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/download_service.dart';
import '../services/plix_device_helper.dart';
import '../services/plex_auth_service.dart';
import '../services/plex_media_service.dart';
import '../services/plex_server_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_home_button.dart';
import 'details_screen.dart';

class DownloadsScreen extends StatefulWidget {
  final PlexServer server;
  final PlexAuthService authService;
  final PlexServerService serverService;
  final String clientId;

  const DownloadsScreen({
    super.key,
    required this.server,
    required this.authService,
    required this.serverService,
    required this.clientId,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late PlexMediaService _mediaService;
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _homeButtonFocusNode = FocusNode();
  final Map<int, FocusNode> _focusNodes = {};

  String _filter = 'all'; // 'all', 'movies', 'shows'

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);
    DownloadService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onServiceUpdate);
    _backButtonFocusNode.dispose();
    _homeButtonFocusNode.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  List<PlexMediaItem> _getFilteredItems() {
    final ds = DownloadService.instance;
    final movies = ds.getDownloadedMovies();
    final shows = ds.getDownloadedShows();

    if (_filter == 'movies') return movies;
    if (_filter == 'shows') return shows;
    return [...shows, ...movies];
  }

  Future<void> _openDetails(PlexMediaItem item) async {
    PlexServer targetServer = widget.server;
    final itemServerId = item.serverId ?? item.server?.clientIdentifier;
    try {
      final token = await widget.authService.getSavedToken() ?? '';
      final servers = await widget.serverService.fetchServers(token);
      if (itemServerId != null && itemServerId.isNotEmpty) {
        targetServer = servers.firstWhere(
          (s) => s.clientIdentifier == itemServerId,
          orElse: () => (item.server != null && item.server!.connections.isNotEmpty)
              ? item.server!
              : widget.server,
        );
      }
    } catch (_) {}

    PlexMediaItem? targetEpisode;
    if (item.isShow) {
      final downloadedEps = DownloadService.instance.getDownloadedEpisodesForShow(item.ratingKey);
      if (downloadedEps.isNotEmpty) {
        downloadedEps.sort((a, b) {
          final sA = a.parentIndex ?? 0;
          final sB = b.parentIndex ?? 0;
          if (sA != sB) return sA.compareTo(sB);
          final eA = a.index ?? 0;
          final eB = b.index ?? 0;
          return eA.compareTo(eB);
        });
        targetEpisode = downloadedEps.first;
      }
    } else if (item.isEpisode) {
      targetEpisode = item;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: (item.isEpisode ? item : item.copyWith(server: targetServer)),
          initialSeasonKey: targetEpisode?.parentRatingKey,
          initialEpisodeKey: targetEpisode?.ratingKey,
          initialEpisode: targetEpisode,
          server: targetServer,
          clientId: widget.clientId,
          onlyDownloaded: false,
        ),
      ),
    );
  }

  int _gridCrossAxisCount(BuildContext context, bool isCompact) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscapePhone = mediaQuery.orientation == Orientation.landscape &&
        (PlixDeviceHelper.isPhone(context) || mediaQuery.size.height < 550);

    if (isLandscapePhone) {
      final width = mediaQuery.size.width;
      if (width > 800) return 6;
      return 5;
    }

    if (isCompact) {
      final width = mediaQuery.size.width;
      if (width > 600) return 4;
      if (width > 420) return 3;
      return 3;
    }
    final width = mediaQuery.size.width;
    if (width > 1600) return 7;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final activeTasks = DownloadService.instance.activeTasks;
    final items = _getFilteredItems();

    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            _buildTopBar(isCompact, activeTasks.length),

            // Active Downloads List
            if (activeTasks.isNotEmpty) _buildActiveDownloadsList(activeTasks, isCompact),

            // Filter Tabs (if both movies and shows exist)
            _buildFilterRow(isCompact),

            // Content Grid or Empty State
            Expanded(
              child: items.isEmpty && activeTasks.isEmpty
                  ? _buildEmptyState()
                  : _buildGrid(items, isCompact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isCompact, int activeCount) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscapePhone = mediaQuery.orientation == Orientation.landscape &&
        (PlixDeviceHelper.isPhone(context) || mediaQuery.size.height < 550);

    return Container(
      color: PlixTheme.background,
      padding: EdgeInsets.symmetric(
        horizontal: isLandscapePhone ? 16 : (isCompact ? 16 : 28),
        vertical: isLandscapePhone ? 6 : (isCompact ? 12 : 16),
      ),
      child: Row(
        children: [
          PlixBackButton(
            focusNode: _backButtonFocusNode,
            forceShow: true,
            onRight: () => _homeButtonFocusNode.requestFocus(),
          ),
          const SizedBox(width: 10),
          PlixHomeButton(
            focusNode: _homeButtonFocusNode,
            onLeft: () => _backButtonFocusNode.requestFocus(),
          ),
          SizedBox(width: isCompact ? 12 : 16),
          const Text(
            'Downloads',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          if (activeCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: PlixTheme.plexGold.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PlixTheme.plexGold.withOpacity(0.5)),
              ),
              child: Text(
                '$activeCount downloading',
                style: TextStyle(
                  color: PlixTheme.plexGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveDownloadsList(List<DownloadTask> tasks, bool isCompact) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 28, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PlixTheme.plexGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.downloading_rounded, size: 16, color: PlixTheme.plexGold),
              const SizedBox(width: 8),
              const Text(
                'Active Downloads',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${tasks.length} in progress',
                style: const TextStyle(color: PlixTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...tasks.map((task) => _buildActiveTaskItem(task, isCompact)),
        ],
      ),
    );
  }

  Widget _buildActiveTaskItem(DownloadTask task, bool isCompact) {
    final progress = task.progress;
    final pct = (progress * 100).toInt();

    String displayTitle = task.title;
    if (task.seriesTitle != null && task.seriesTitle!.isNotEmpty) {
      final sStr = task.seasonIndex != null ? 'S${task.seasonIndex!.toString().padLeft(2, '0')}' : '';
      final eStr = task.episodeIndex != null ? 'E${task.episodeIndex!.toString().padLeft(2, '0')}' : '';
      final epTag = sStr.isNotEmpty || eStr.isNotEmpty ? '$sStr$eStr • ' : '';
      displayTitle = '${task.seriesTitle} • $epTag${task.title}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(color: PlixTheme.plexGold, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => DownloadService.instance.cancelDownload(task.ratingKey),
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.01, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
              minHeight: 4,
            ),
          ),
          if (task.totalBytes > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${(task.receivedBytes / 1048576).toStringAsFixed(1)} MB / ${(task.totalBytes / 1048576).toStringAsFixed(1)} MB',
              style: const TextStyle(color: PlixTheme.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterRow(bool isCompact) {
    final ds = DownloadService.instance;
    final hasMovies = ds.getDownloadedMovies().isNotEmpty;
    final hasShows = ds.getDownloadedShows().isNotEmpty;

    if (!hasMovies && !hasShows) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 28,
        vertical: 8,
      ),
      child: Row(
        children: [
          _buildFilterChip('all', 'All'),
          if (hasShows) ...[
            const SizedBox(width: 8),
            _buildFilterChip('shows', 'TV Shows'),
          ],
          if (hasMovies) ...[
            const SizedBox(width: 8),
            _buildFilterChip('movies', 'Movies'),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? PlixTheme.plexGold : PlixTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? PlixTheme.plexGold : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(
                Icons.download_done_rounded,
                size: 48,
                color: PlixTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Downloads Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Downloaded movies and episodes will appear here so you can watch them offline without an internet connection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PlixTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<PlexMediaItem> items, bool isCompact) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscapePhone = mediaQuery.orientation == Orientation.landscape &&
        (PlixDeviceHelper.isPhone(context) || mediaQuery.size.height < 550);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isLandscapePhone ? 16 : (isCompact ? 14 : 28)),
      child: GridView.builder(
        padding: EdgeInsets.only(
          top: isLandscapePhone ? 6 : 10,
          bottom: isCompact ? 24 : 60,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridCrossAxisCount(context, isCompact),
          crossAxisSpacing: isLandscapePhone ? 10 : (isCompact ? 10 : 16),
          mainAxisSpacing: isLandscapePhone ? 10 : (isCompact ? 12 : 18),
          childAspectRatio: isLandscapePhone ? 0.53 : (isCompact ? 0.51 : 0.52),
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return LayoutBuilder(
            builder: (context, constraints) {
              return MediaCard(
                item: item,
                mediaService: _mediaService,
                focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                width: constraints.maxWidth,
                margin: EdgeInsets.zero,
                enableHighlight: !isCompact && !isLandscapePhone,
                onTap: () => _openDetails(item),
              );
            },
          );
        },
      ),
    );
  }
}
