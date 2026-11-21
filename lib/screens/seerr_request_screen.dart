import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../services/plix_device_helper.dart';
import '../services/seerr_service.dart';
import '../widgets/plix_back_button.dart';
import '../widgets/plix_button.dart';
import '../widgets/plix_home_button.dart';
import '../widgets/plix_tv_text_field.dart';

class SeerrRequestScreen extends StatefulWidget {
  final String initialQuery;

  const SeerrRequestScreen({super.key, this.initialQuery = ''});

  @override
  State<SeerrRequestScreen> createState() => _SeerrRequestScreenState();
}

class _SeerrRequestScreenState extends State<SeerrRequestScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _backButtonFocus = FocusNode();
  final FocusNode _homeButtonFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<FocusNode> _resultFocusNodes = [];

  String _query = '';
  List<SeerrSearchResult> _results = [];
  bool _isSearching = false;
  String? _error;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _textController.text = _query;
    SeerrService.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      setState(() {});
      if (_query.isNotEmpty && SeerrService.instance.isConfigured) {
        _performSearch();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _query.isEmpty) _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFieldFocusNode.dispose();
    _backButtonFocus.dispose();
    _homeButtonFocus.dispose();
    _scrollController.dispose();
    for (final n in _resultFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _resetFocusNodes(int count) {
    for (final n in _resultFocusNodes) {
      n.dispose();
    }
    _resultFocusNodes
      ..clear()
      ..addAll(List.generate(count, (_) => FocusNode()));
  }

  Future<void> _performSearch() async {
    final q = _query.trim();
    if (q.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await SeerrService.instance.search(q);
      if (!mounted || generation != _searchGeneration) return;
      _resetFocusNodes(results.length);
      setState(() {
        _results = results;
        _isSearching = false;
      });
      if (results.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _resultFocusNodes.isNotEmpty) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
            _resultFocusNodes.first.requestFocus();
          }
        });
      }
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      _resetFocusNodes(0);
      setState(() {
        _results = [];
        _isSearching = false;
        _error = e.toString();
      });
    }
  }

  void _focusFirstResult() {
    if (_resultFocusNodes.isNotEmpty) _resultFocusNodes.first.requestFocus();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        width: 360,
        backgroundColor: PlixTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PlixTheme.plexGold.withOpacity(0.5)),
        ),
      ),
    );
  }

  Future<void> _openRequestDialog(int index) async {
    final item = _results[index];
    final newStatus = await showDialog<SeerrMediaStatus>(
      context: context,
      builder: (_) => SeerrRequestDialog(item: item),
    );
    if (!mounted) return;
    if (newStatus != null) {
      setState(() {
        _results[index] = item.copyWith(status: newStatus);
      });
      _showToast('Requested ${item.title}');
    }
    if (index < _resultFocusNodes.length) _resultFocusNodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = PlixDeviceHelper.isCompact(context);
    final configured = SeerrService.instance.isConfigured;

    return Scaffold(
      backgroundColor: PlixTheme.background,
      body: SafeArea(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape || event.logicalKey == LogicalKeyboardKey.goBack)) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(isCompact: isCompact, configured: configured),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32),
                  child: _buildBody(isCompact: isCompact, configured: configured),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar({required bool isCompact, required bool configured}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 12),
      child: Row(
        children: [
          if (!Platform.isAndroid || PlixDeviceHelper.isTelevision || MediaQuery.of(context).orientation == Orientation.landscape) ...[
            PlixBackButton(
              focusNode: _backButtonFocus,
              onRight: () => _homeButtonFocus.requestFocus(),
              onDown: _results.isNotEmpty ? _focusFirstResult : () => _textFieldFocusNode.requestFocus(),
            ),
            const SizedBox(width: 10),
            PlixHomeButton(
              focusNode: _homeButtonFocus,
              onLeft: () => _backButtonFocus.requestFocus(),
              onRight: () => _textFieldFocusNode.requestFocus(),
              onDown: _results.isNotEmpty ? _focusFirstResult : () => _textFieldFocusNode.requestFocus(),
            ),
            SizedBox(width: isCompact ? 12 : 20),
          ] else ...[
            Icon(Icons.add_to_queue_rounded, color: PlixTheme.plexGold, size: 24),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: AnimatedBuilder(
              animation: _textFieldFocusNode,
              builder: (context, _) {
                final isFocused = _textFieldFocusNode.hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 48,
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  decoration: BoxDecoration(
                    color: PlixTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isFocused ? PlixTheme.plexGold : PlixTheme.cardBorder,
                      width: isFocused ? 2.0 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_to_queue_rounded,
                        color: isFocused ? PlixTheme.plexGold : PlixTheme.textMuted,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PlixTvTextField(
                          controller: _textController,
                          focusNode: _textFieldFocusNode,
                          hintText: SeerrService.instance.server != null
                              ? 'Search to request from ${SeerrService.instance.server!.name}...'
                              : 'Search movies & TV shows to request...',
                          imeAction: 'search',
                          style: const TextStyle(color: PlixTheme.textPrimary, fontSize: 16),
                          hintStyle: const TextStyle(color: PlixTheme.textMuted, fontSize: 16),
                          onChanged: (val) => _query = val,
                          onSubmitted: (val) {
                            _query = val;
                            if (configured) _performSearch();
                          },
                          onLeft: () => _homeButtonFocus.requestFocus(),
                          onDown: _focusFirstResult,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({required IconData icon, required String title, required String subtitle}) {
    return Align(
      alignment: const Alignment(0, -0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: PlixTheme.textMuted.withOpacity(0.5)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PlixTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PlixTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({required bool isCompact, required bool configured}) {
    if (!configured) {
      return _buildMessage(
        icon: Icons.link_off_rounded,
        title: 'Not Signed In to Seerr',
        subtitle: 'Sign in to Seerr from Settings with your Plex or Jellyfin account to request media.',
      );
    }
    if (_isSearching) {
      return Align(
        alignment: const Alignment(0, -0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(PlixTheme.plexGold)),
            const SizedBox(height: 16),
            const Text('Searching Seerr...', style: TextStyle(color: PlixTheme.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }
    if (_error != null) {
      return _buildMessage(icon: Icons.error_outline_rounded, title: 'Something went wrong', subtitle: _error!);
    }
    if (_query.trim().isEmpty) {
      return _buildMessage(
        icon: Icons.add_to_queue_rounded,
        title: 'Request Movies & TV Shows',
        subtitle: 'Search for a title to request it through Seerr.',
      );
    }
    if (_results.isEmpty) {
      return _buildMessage(
        icon: Icons.movie_filter_outlined,
        title: 'No results found for "$_query"',
        subtitle: 'Check the spelling or try searching for another title.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = isCompact
            ? (constraints.maxWidth / 115).floor().clamp(3, 7)
            : (constraints.maxWidth / 150).floor().clamp(4, 12);
        return FocusTraversalGroup(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 60),
            clipBehavior: Clip.none,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: isCompact ? 10 : 14,
              mainAxisSpacing: isCompact ? 12 : 16,
              childAspectRatio: 0.52,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final row = index ~/ crossAxisCount;
              return _SeerrResultCard(
                key: ValueKey('seerr_${_results[index].mediaType}_${_results[index].tmdbId}'),
                item: _results[index],
                focusNode: index < _resultFocusNodes.length ? _resultFocusNodes[index] : null,
                onUp: row == 0 ? () => _textFieldFocusNode.requestFocus() : null,
                onTap: () => _openRequestDialog(index),
              );
            },
          ),
        );
      },
    );
  }
}

Color _statusColor(SeerrMediaStatus status) {
  switch (status) {
    case SeerrMediaStatus.available:
      return const Color(0xFF22C55E);
    case SeerrMediaStatus.partiallyAvailable:
      return const Color(0xFF14B8A6);
    case SeerrMediaStatus.pending:
      return const Color(0xFFF59E0B);
    case SeerrMediaStatus.processing:
      return const Color(0xFF6366F1);
    case SeerrMediaStatus.none:
    case SeerrMediaStatus.unknown:
    case SeerrMediaStatus.deleted:
      return PlixTheme.textMuted;
  }
}

class _SeerrResultCard extends StatefulWidget {
  final SeerrSearchResult item;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback? onUp;

  const _SeerrResultCard({
    super.key,
    required this.item,
    required this.onTap,
    this.focusNode,
    this.onUp,
  });

  @override
  State<_SeerrResultCard> createState() => _SeerrResultCardState();
}

class _SeerrResultCardState extends State<_SeerrResultCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final highlighted = _isFocused || _isHovered;
    final accent = PlixTheme.plexGold;
    final showStatus = item.status != SeerrMediaStatus.none && item.status != SeerrMediaStatus.unknown && item.status != SeerrMediaStatus.deleted;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.2,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: highlighted ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      color: PlixTheme.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: highlighted ? accent : PlixTheme.cardBorder,
                        width: highlighted ? 2.5 : 1.0,
                      ),
                      boxShadow: highlighted
                          ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, spreadRadius: 1)]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          item.posterUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.posterUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _placeholder(item),
                                  placeholder: (_, __) => _placeholder(item),
                                )
                              : _placeholder(item),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: _badge(item.isMovie ? 'MOVIE' : 'SERIES', Colors.black.withOpacity(0.7), Colors.white),
                          ),
                          if (showStatus)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _badge(item.status.label.toUpperCase(), _statusColor(item.status), Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlighted ? Colors.white : PlixTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.year != null)
                  Text(
                    item.year!,
                    style: const TextStyle(color: PlixTheme.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(SeerrSearchResult item) {
    return Container(
      color: PlixTheme.surface,
      alignment: Alignment.center,
      child: Icon(
        item.isMovie ? Icons.movie_outlined : Icons.tv_rounded,
        color: PlixTheme.textMuted,
        size: 36,
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}

class SeerrRequestDialog extends StatefulWidget {
  final SeerrSearchResult item;

  const SeerrRequestDialog({super.key, required this.item});

  @override
  State<SeerrRequestDialog> createState() => _SeerrRequestDialogState();
}

class _SeerrRequestDialogState extends State<SeerrRequestDialog> {
  final FocusNode _requestFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();

  List<SeerrSeason> _seasons = [];
  final Set<int> _selectedSeasons = {};
  bool _loadingSeasons = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.item.isTv) _loadSeasons();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (widget.item.status.canRequest ? _requestFocus : _cancelFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _requestFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSeasons() async {
    setState(() => _loadingSeasons = true);
    try {
      final seasons = await SeerrService.instance.getTvSeasons(widget.item.tmdbId);
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _selectedSeasons
          ..clear()
          ..addAll(seasons.where((s) => s.status.canRequest && s.status != SeerrMediaStatus.partiallyAvailable).map((s) => s.seasonNumber));
        _loadingSeasons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSeasons = false;
        _error = e.toString();
      });
    }
  }

  bool get _canSubmit {
    if (_submitting || !widget.item.status.canRequest) return false;
    if (widget.item.isTv) {
      if (_loadingSeasons) return false;
      if (_seasons.isNotEmpty && _selectedSeasons.isEmpty) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final requestable = _seasons.where((s) => s.status.canRequest).map((s) => s.seasonNumber).toSet();
      final selectedAll = _seasons.isNotEmpty && requestable.length == _seasons.length && _selectedSeasons.length == _seasons.length;
      final status = await SeerrService.instance.request(
        widget.item,
        seasons: widget.item.isTv && !selectedAll && _selectedSeasons.isNotEmpty ? (_selectedSeasons.toList()..sort()) : null,
      );
      if (mounted) Navigator.of(context).pop(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accent = PlixTheme.plexGold;
    final requestable = item.status.canRequest;

    return AlertDialog(
      backgroundColor: PlixTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: PlixTheme.cardBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Icon(Icons.add_to_queue_rounded, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.year != null ? '${item.title} (${item.year})' : item.title,
              style: const TextStyle(color: PlixTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: PlixTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PlixTheme.cardBorder),
                    ),
                    child: Text(
                      item.isMovie ? 'Movie' : 'TV Series',
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(item.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _statusColor(item.status)),
                    ),
                    child: Text(
                      item.status.label,
                      style: TextStyle(color: _statusColor(item.status), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (item.voteAverage != null && item.voteAverage! > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, color: Color(0xFFF5C518), size: 16),
                    const SizedBox(width: 3),
                    Text(
                      item.voteAverage!.toStringAsFixed(1),
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              if (item.overview != null && item.overview!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  item.overview!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ],
              if (item.isTv && requestable) ...[
                const SizedBox(height: 16),
                const Text(
                  'Seasons',
                  style: TextStyle(color: PlixTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (_loadingSeasons)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(accent)),
                      ),
                    ),
                  )
                else if (_seasons.isEmpty)
                  const Text(
                    'All seasons will be requested.',
                    style: TextStyle(color: PlixTheme.textMuted, fontSize: 12.5),
                  )
                else
                  ..._seasons.map((s) {
                    final selectable = s.status.canRequest && s.status != SeerrMediaStatus.partiallyAvailable;
                    final checked = _selectedSeasons.contains(s.seasonNumber);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: accent,
                      checkColor: Colors.black,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selectable ? checked : true,
                      onChanged: selectable
                          ? (v) => setState(() {
                                if (v == true) {
                                  _selectedSeasons.add(s.seasonNumber);
                                } else {
                                  _selectedSeasons.remove(s.seasonNumber);
                                }
                              })
                          : null,
                      title: Text(
                        s.name,
                        style: TextStyle(
                          color: selectable ? PlixTheme.textPrimary : PlixTheme.textMuted,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        selectable
                            ? '${s.episodeCount} episode${s.episodeCount == 1 ? '' : 's'}'
                            : s.status.label,
                        style: TextStyle(
                          color: selectable ? PlixTheme.textMuted : _statusColor(s.status),
                          fontSize: 11.5,
                        ),
                      ),
                    );
                  }),
              ],
              if (!requestable) ...[
                const SizedBox(height: 14),
                Text(
                  item.status == SeerrMediaStatus.available
                      ? 'This title is already available on your server.'
                      : 'This title has already been requested.',
                  style: const TextStyle(color: PlixTheme.textMuted, fontSize: 12.5),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      actions: [
        PlixButton(
          focusNode: _cancelFocus,
          isPrimary: false,
          label: requestable ? 'Cancel' : 'Close',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onPressed: () => Navigator.of(context).pop(),
          onRight: requestable ? () => _requestFocus.requestFocus() : null,
        ),
        if (requestable)
          PlixButton(
            focusNode: _requestFocus,
            label: _submitting ? 'Requesting...' : 'Request',
            icon: const Icon(Icons.send_rounded, size: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: _submit,
            onLeft: () => _cancelFocus.requestFocus(),
          ),
      ],
    );
  }
}
