import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../services/plex_media_service.dart';

class CastRow extends StatefulWidget {
  final List<MediaPerson> people;
  final PlexMediaService mediaService;
  final ValueChanged<MediaPerson> onPersonTap;
  final String title;

  const CastRow({
    super.key,
    required this.people,
    required this.mediaService,
    required this.onPersonTap,
    this.title = 'Cast & Crew',
  });

  @override
  State<CastRow> createState() => _CastRowState();
}

class _CastRowState extends State<CastRow> {
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(MediaPerson person) {
    final key = '${person.id}_${person.name}_${person.role}';
    return _focusNodes.putIfAbsent(key, () => FocusNode());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.people.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.people.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final person = widget.people[index];
              return _CastCard(
                person: person,
                focusNode: _nodeFor(person),
                imageUrl: widget.mediaService.buildImageUrl(
                  person.thumb,
                  width: 220,
                  height: 330,
                ),
                onTap: () => widget.onPersonTap(person),
                onLeft: index == 0 ? null : () => _nodeFor(widget.people[index - 1]).requestFocus(),
                onRight: index == widget.people.length - 1
                    ? null
                    : () => _nodeFor(widget.people[index + 1]).requestFocus(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CastCard extends StatefulWidget {
  final MediaPerson person;
  final FocusNode focusNode;
  final String imageUrl;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _CastCard({
    required this.person,
    required this.focusNode,
    required this.imageUrl,
    required this.onTap,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_CastCard> createState() => _CastCardState();
}

class _CastCardState extends State<_CastCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _isFocused || _isHovered;
    final initials = widget.person.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
            widget.onRight!();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space ||
                  key == LogicalKeyboardKey.gameButtonA ||
                  key == LogicalKeyboardKey.numpadEnter)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: highlighted ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) {
            if (Platform.isWindows && mounted) {
              setState(() => _isHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 112,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: highlighted ? PlixTheme.cardFocused : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: highlighted ? PlixTheme.plexGold : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 104,
                    height: 130,
                    child: widget.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: PlixTheme.card),
                            errorWidget: (_, __, ___) => _initials(initials),
                          )
                        : _initials(initials),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.person.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlighted ? PlixTheme.textPrimary : PlixTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                if (widget.person.role.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.person.role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlixTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initials(String initials) {
    return Container(
      color: PlixTheme.card,
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: PlixTheme.textMuted,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
