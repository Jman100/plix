import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../services/plex_media_service.dart';
import '../services/plix_image_cache.dart';

class MediaCard extends StatefulWidget {
  final PlexMediaItem item;
  final PlexMediaService mediaService;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final void Function(FocusNode node, bool focused)? onFocusWithNode;
  final FocusNode? focusNode;
  final double width;
  final double aspectRatio;
  final bool autofocus;
  final bool enableHighlight;
  final bool isForcedHighlighted;
  final bool showResolutionBadge;
  final EdgeInsetsGeometry? margin;

  const MediaCard({
    super.key,
    required this.item,
    required this.mediaService,
    required this.onTap,
    this.onFocusChange,
    this.onFocusWithNode,
    this.focusNode,
    this.width = 140,
    this.aspectRatio = 2 / 3,
    this.autofocus = false,
    this.enableHighlight = true,
    this.isForcedHighlighted = false,
    this.showResolutionBadge = false,
    this.margin,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.blockRight = false,
    this.blockDown = false,
    this.onHover,
  });

  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool blockRight;
  final bool blockDown;
  final ValueChanged<bool>? onHover;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      widget.onFocusChange?.call(_focusNode.hasFocus);
      widget.onFocusWithNode?.call(_focusNode, _focusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant MediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocus);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width / widget.aspectRatio;
    final imageWidth = PlixImageCache.requestWidth(widget.width);
    final imageHeight = PlixImageCache.requestHeight(height);
    final imageUrl = widget.mediaService.buildImageUrl(
      widget.item.posterThumb,
      width: imageWidth,
      height: imageHeight,
    );

    final isHighlighted = widget.isForcedHighlighted || (widget.enableHighlight && (_isFocused || _isHovered));

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            if (widget.onRight != null) {
              widget.onRight!();
              return KeyEventResult.handled;
            }
            if (widget.blockRight) {
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            if (widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            if (widget.blockDown) {
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent && (key == LogicalKeyboardKey.select ||
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
        scale: isHighlighted ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) {
            if (Platform.isWindows && mounted) {
              setState(() => _isHovered = hovered);
            }
            widget.onHover?.call(hovered);
          },
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.white.withOpacity(0.05),
          splashColor: PlixTheme.plexGold.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: widget.width,
            margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poster image with border
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: height,
                  width: widget.width,
                  decoration: BoxDecoration(
                    color: PlixTheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHighlighted ? PlixTheme.plexGold : Colors.transparent,
                      width: 3.0,
                    ),
                    boxShadow: isHighlighted
                        ? [
                            BoxShadow(
                              color: PlixTheme.plexGold.withOpacity(0.5),
                              blurRadius: 14,
                              spreadRadius: 2,
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            )
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: PlixImageCache.decodeWidth(context, widget.width),
                            memCacheHeight: PlixImageCache.decodeHeight(context, height),
                            placeholder: (context, url) => Container(
                              color: PlixTheme.card,
                              child: const Center(
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: PlixTheme.textMuted,
                                  size: 32,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: PlixTheme.card,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: PlixTheme.textMuted,
                                  size: 32,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: PlixTheme.card,
                            child: const Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: PlixTheme.textMuted,
                                size: 32,
                              ),
                            ),
                          ),

                        // In-progress orange progress bar
                        if (widget.item.isInProgress)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: widget.item.progressPercentage,
                              backgroundColor: Colors.black.withOpacity(0.7),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                PlixTheme.plexGold,
                              ),
                              minHeight: 4,
                            ),
                          ),

                        // Episode badge (e.g. S1:E4)
                        if (widget.item.isEpisode && widget.item.parentIndex != null)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'S${widget.item.parentIndex}:E${widget.item.index ?? 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Watched checkmark
                        if (widget.item.isWatched)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check,
                                color: PlixTheme.plexGold,
                                size: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Title and subtitle
                Text(
                  widget.item.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isHighlighted ? PlixTheme.textPrimary : PlixTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                if (widget.item.cardSubtitle.isNotEmpty ||
                    (widget.showResolutionBadge && widget.item.formattedResolution.isNotEmpty)) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.item.cardSubtitle.isNotEmpty)
                        Expanded(
                          child: Text(
                            widget.item.cardSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlixTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (widget.showResolutionBadge && widget.item.formattedResolution.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: PlixTheme.plexGold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.item.formattedResolution,
                            style: TextStyle(
                              color: PlixTheme.plexGold,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
