import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plex_library.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../services/plix_device_helper.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_bottom_nav.dart';
import 'details_screen.dart';

class LibraryScreen extends StatefulWidget {
  final PlexLibrary library;
  final PlexServer server;
  final String clientId;

  const LibraryScreen({
    super.key,
    required this.library,
    required this.server,
    required this.clientId,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibrarySortOption {
  nameAsc,
  nameDesc,
  yearDesc,
  yearAsc,
  dateAdded,
}

class _LibraryScreenState extends State<LibraryScreen> {
  late PlexMediaService _mediaService;
  List<PlexMediaItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _lastSelectedIndex;
  final Map<int, FocusNode> _focusNodes = {};
  _LibrarySortOption _sortOption = _LibrarySortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    _mediaService = PlexMediaService(server: widget.server);
    _loadItems();
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _applySort() {
    setState(() {
      switch (_sortOption) {
        case _LibrarySortOption.nameAsc:
          _items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          break;
        case _LibrarySortOption.nameDesc:
          _items.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
          break;
        case _LibrarySortOption.yearDesc:
          _items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
          break;
        case _LibrarySortOption.yearAsc:
          _items.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
          break;
        case _LibrarySortOption.dateAdded:
          _items.sort((a, b) => (b.originallyAvailableAt ?? "").compareTo(a.originallyAvailableAt ?? ""));
          break;
      }
    });
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _mediaService.getLibraryItems(widget.library.key);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
        _applySort();
        if (_lastSelectedIndex != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_focusNodes.containsKey(_lastSelectedIndex)) {
              _focusNodes[_lastSelectedIndex]?.requestFocus();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load library items: $e';
        });
      }
    }
  }

  void _onItemTap(PlexMediaItem item, int index) {
    _lastSelectedIndex = index;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: item,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_focusNodes.containsKey(index)) {
            _focusNodes[index]?.requestFocus();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final isTv = PlixDeviceHelper.isTelevision;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      appBar: AppBar(
        title: Text(widget.library.title),
        actions: [
          PopupMenuButton<_LibrarySortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort library',
            color: PlixTheme.surface,
            initialValue: _sortOption,
            onSelected: (option) {
              _sortOption = option;
              _applySort();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _LibrarySortOption.nameAsc,
                child: Text('Name (A to Z)', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: _LibrarySortOption.nameDesc,
                child: Text('Name (Z to A)', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: _LibrarySortOption.yearDesc,
                child: Text('Release Year (Newest)', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: _LibrarySortOption.yearAsc,
                child: Text('Release Year (Oldest)', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: _LibrarySortOption.dateAdded,
                child: Text('Date Added (Recently Added)', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
          ),
        ],
      ),
      bottomNavigationBar: (isCompact && !isTv)
          ? PlixBottomNav(
              currentIndex: 3,
              server: widget.server,
              clientId: widget.clientId,
            )
          : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No media found in this library.',
                        style: TextStyle(color: PlixTheme.textSecondary, fontSize: 16),
                      ),
                    )
                  : GridView.builder(
                      clipBehavior: Clip.hardEdge,
                      padding: EdgeInsets.only(
                        left: isCompact ? 14 : 24,
                        right: isCompact ? 14 : 24,
                        top: isCompact ? 12 : 24,
                        bottom: isCompact ? 24 : 140,
                      ),
                      gridDelegate: isCompact
                          ? const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.52,
                            )
                          : const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 165,
                              childAspectRatio: 0.56,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 18,
                            ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return MediaCard(
                              item: item,
                              mediaService: _mediaService,
                              focusNode: _focusNodes.putIfAbsent(index, () => FocusNode()),
                              width: constraints.maxWidth,
                              margin: EdgeInsets.zero,
                              autofocus: index == (_lastSelectedIndex ?? 0),
                              onTap: () => _onItemTap(item, index),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
