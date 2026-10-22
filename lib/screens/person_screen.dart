import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../services/plex_media_service.dart';
import '../widgets/media_card.dart';
import '../widgets/plix_back_button.dart';
import 'details_screen.dart';

class PersonScreen extends StatefulWidget {
  final MediaPerson person;
  final PlexServer server;
  final String clientId;

  const PersonScreen({
    super.key,
    required this.person,
    required this.server,
    required this.clientId,
  });

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late final PlexMediaService _mediaService;
  late MediaPerson _person;
  List<PlexMediaItem> _media = [];
  bool _isLoading = true;
  String? _errorMessage;

  final FocusNode _backFocusNode = FocusNode();
  final Map<String, FocusNode> _mediaFocusNodes = {};
  final ScrollController _gridController = ScrollController();

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _mediaService = PlexMediaService(server: widget.server);
    _load();
  }

  @override
  void dispose() {
    _backFocusNode.dispose();
    _gridController.dispose();
    for (final node in _mediaFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final details = await _mediaService.getPersonDetails(widget.person);
      final media = await _mediaService.getPersonMedia(details);
      final seen = <String>{};
      final unique = media.where((item) => seen.add(item.ratingKey)).toList();
      if (mounted) {
        setState(() {
          _person = details;
          _media = unique;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load this person.';
        });
      }
    }
  }

  FocusNode _focusNodeFor(PlexMediaItem item) {
    return _mediaFocusNodes.putIfAbsent(item.ratingKey, () => FocusNode());
  }

  void _focusFirstMedia() {
    if (_media.isEmpty) return;
    _focusNodeFor(_media.first).requestFocus();
  }

  void _openMedia(PlexMediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          initialItem: item,
          server: widget.server,
          clientId: widget.clientId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 720;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isCompact ? 14 : 28, 16, 20, 8),
              child: Row(
                children: [
                  PlixBackButton(
                    focusNode: _backFocusNode,
                    autofocus: true,
                    onDown: _focusFirstMedia,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Cast & Crew',
                      style: TextStyle(
                        color: PlixTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 18 : 32),
              child: _buildHeader(isCompact),
            ),
            const SizedBox(height: 22),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    final imageUrl = _mediaService.buildImageUrl(
      _person.thumb,
      width: 300,
      height: 450,
    );
    final initials = _person.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: isCompact ? 104 : 144,
            height: isCompact ? 148 : 202,
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: PlixTheme.card),
                    errorWidget: (_, __, ___) => _initials(initials, isCompact),
                  )
                : _initials(initials, isCompact),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _person.name,
                style: TextStyle(
                  color: PlixTheme.textPrimary,
                  fontSize: isCompact ? 24 : 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_person.role.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  _person.role,
                  style: TextStyle(
                    color: PlixTheme.plexGold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                _person.type == 'crew' ? 'Crew' : 'Cast',
                style: const TextStyle(
                  color: PlixTheme.textMuted,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
              if (_person.summary != null && _person.summary!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Flexible(
                  child: Text(
                    _person.summary!,
                    maxLines: isCompact ? 4 : 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: PlixTheme.plexGold),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: PlixTheme.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Appears in',
            style: TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _media.isEmpty
              ? const Center(
                  child: Text(
                    'No other media found on this server.',
                    style: TextStyle(color: PlixTheme.textMuted),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 18.0;
                    final columns = (constraints.maxWidth / 164).floor().clamp(2, 8);
                    final cellWidth =
                        (constraints.maxWidth - (spacing * (columns - 1))) / columns;
                    final cellHeight = cellWidth * 1.5 + 58;
                    return GridView.builder(
                      controller: _gridController,
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: spacing,
                        childAspectRatio: cellWidth / cellHeight,
                      ),
                      itemCount: _media.length,
                      itemBuilder: (context, index) {
                        final item = _media[index];
                        final isFirstRow = index < columns;
                        final isFirstColumn = index % columns == 0;
                        return MediaCard(
                          item: item,
                          mediaService: _mediaService,
                          focusNode: _focusNodeFor(item),
                          width: cellWidth - 8,
                          onTap: () => _openMedia(item),
                          onUp: isFirstRow ? () => _backFocusNode.requestFocus() : null,
                          onLeft: isFirstColumn
                              ? null
                              : () => _focusNodeFor(_media[index - 1]).requestFocus(),
                          onRight: (index + 1) % columns == 0 || index == _media.length - 1
                              ? null
                              : () => _focusNodeFor(_media[index + 1]).requestFocus(),
                          onDown: index + columns >= _media.length
                              ? null
                              : () => _focusNodeFor(_media[index + columns]).requestFocus(),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _initials(String initials, bool isCompact) {
    return Container(
      color: PlixTheme.card,
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: PlixTheme.textMuted,
          fontSize: isCompact ? 30 : 42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
