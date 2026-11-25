import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/plex_media_item.dart';
import '../models/plex_server.dart';
import '../models/seerr_models.dart';
import '../screens/details_screen.dart';
import '../screens/player_screen.dart';
import '../services/native_player_service.dart';
import '../services/plex_media_service.dart';
import '../services/plix_device_helper.dart';
import '../services/seerr_service.dart';
import 'plix_button.dart';

class SeerrRequestDialog extends StatefulWidget {
  final PlexServer server;
  final String seerrUrl;
  final SeerrMediaItem item;
  final String clientId;
  final List<PlexServer>? availableServers;

  const SeerrRequestDialog({
    super.key,
    required this.server,
    required this.seerrUrl,
    required this.item,
    required this.clientId,
    this.availableServers,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PlexServer server,
    required String seerrUrl,
    required SeerrMediaItem item,
    required String clientId,
    List<PlexServer>? availableServers,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SeerrRequestDialog(
        server: server,
        seerrUrl: seerrUrl,
        item: item,
        clientId: clientId,
        availableServers: availableServers,
      ),
    );
  }

  @override
  State<SeerrRequestDialog> createState() => _SeerrRequestDialogState();
}

class _SeerrRequestDialogState extends State<SeerrRequestDialog> {
  bool _isLoading = true;
  SeerrMediaDetails? _details;
  final Set<int> _selectedSeasons = {};
  bool _isSubmitting = false;
  bool _isLocatingMedia = false;
  bool _isLocatingTrailer = false;
  String? _errorMessage;

  final FocusNode _closeButtonFocus = FocusNode();
  final FocusNode _submitStandardFocus = FocusNode();
  final FocusNode _submit4kFocus = FocusNode();
  final FocusNode _requestedStandardFocus = FocusNode();
  final FocusNode _requested4kFocus = FocusNode();
  final FocusNode _goToMediaFocus = FocusNode();
  final FocusNode _watchTrailerFocus = FocusNode();
  final FocusNode _cancelButtonFocus = FocusNode();
  final FocusNode _allSeasonsFocus = FocusNode();
  final Map<int, FocusNode> _seasonFocusNodes = {};
  final ScrollController _seasonsScrollController = ScrollController();
  final Map<int, GlobalKey> _seasonTileKeys = {};
  int? _lastFocusedSeasonNumber;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _closeButtonFocus.dispose();
    _submitStandardFocus.dispose();
    _submit4kFocus.dispose();
    _requestedStandardFocus.dispose();
    _requested4kFocus.dispose();
    _goToMediaFocus.dispose();
    _watchTrailerFocus.dispose();
    _cancelButtonFocus.dispose();
    _allSeasonsFocus.dispose();
    _seasonsScrollController.dispose();
    for (final node in _seasonFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final details = await SeerrService().getMediaDetails(
        widget.server,
        widget.seerrUrl,
        widget.item.mediaType,
        widget.item.id,
      );

      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
          // By default for TV shows NO seasons are selected unless downloaded/requested
          _selectedSeasons.clear();
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && PlixDeviceHelper.isTelevision) {
            if (_isContentAvailable) {
              _goToMediaFocus.requestFocus();
            } else if (details != null && details.isMovie) {
              _watchTrailerFocus.requestFocus();
            } else if (details != null && details.isTv) {
              _allSeasonsFocus.requestFocus();
            } else {
              _cancelButtonFocus.requestFocus();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load details: $e';
        });
      }
    }
  }

  bool get _isContentAvailable {
    if (_details != null) {
      if (_details!.isTv) {
        return _details!.seasons.isNotEmpty && _details!.seasons.every((s) => s.isAvailable);
      } else {
        return _details!.isAnyAvailable;
      }
    }
    return widget.item.isAvailable;
  }

  bool get _isAllAvailableOrRequested {
    if (_details == null || !_details!.isTv) return false;
    if (_details!.seasons.isEmpty) return false;
    return _details!.seasons.every((s) => s.isAvailableOrRequested);
  }

  bool get _isAllSelectableSelected {
    if (_details == null || !_details!.isTv) return false;
    final selectable = _details!.seasons.where((s) => !s.isAvailableOrRequested).toList();
    if (selectable.isEmpty) return false;
    return selectable.every((s) => _selectedSeasons.contains(s.seasonNumber));
  }

  void _toggleAllSeasons(bool? val) {
    if (_details == null) return;
    setState(() {
      if (val == true) {
        for (final s in _details!.seasons) {
          if (!s.isAvailableOrRequested) {
            _selectedSeasons.add(s.seasonNumber);
          }
        }
      } else {
        _selectedSeasons.clear();
      }
    });
  }

  void _toggleSeason(int seasonNum) {
    setState(() {
      if (_selectedSeasons.contains(seasonNum)) {
        _selectedSeasons.remove(seasonNum);
      } else {
        _selectedSeasons.add(seasonNum);
      }
    });
  }

  Future<void> _submitRequest({bool is4k = false}) async {
    if (_isSubmitting) return;

    final isTv = widget.item.isTv || (_details?.isTv == true);
    if (isTv && _selectedSeasons.isEmpty && !_isAllAvailableOrRequested) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one season to request.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    List<int>? seasonsToSend;
    if (isTv) {
      seasonsToSend = _selectedSeasons.toList()..sort();
    }

    final result = await SeerrService().submitRequest(
      widget.server,
      widget.seerrUrl,
      mediaType: widget.item.mediaType,
      mediaId: widget.item.id,
      is4k: is4k,
      seasons: seasonsToSend,
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? 'Request for "${widget.item.title}" submitted successfully!',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.message ?? 'Failed to submit request.';
      });
    }
  }

  Future<void> _goToMedia() async {
    if (_isLocatingMedia) return;
    setState(() => _isLocatingMedia = true);

    PlexMediaItem? matchedItem;
    final isTv = widget.item.isTv || (_details?.isTv == true);
    final targetTitle = (_details?.title.isNotEmpty == true ? _details!.title : widget.item.title).trim();

    try {
      // 1. If Plex ratingKey is known from Seerr mediaInfo
      if (widget.server.isPlex && _details?.ratingKey != null && _details!.ratingKey!.isNotEmpty) {
        try {
          matchedItem = await PlexMediaService.forServer(widget.server).getItemMetadata(_details!.ratingKey!);
        } catch (_) {}
      }

      // 2. Search on server by title
      if (matchedItem == null) {
        final searchResults = await PlexMediaService.forServer(widget.server).search(targetTitle);
        for (final it in searchResults) {
          if (it.title.trim().toLowerCase() == targetTitle.toLowerCase()) {
            if (isTv && (it.isShow || it.type == 'show')) {
              matchedItem = it;
              break;
            } else if (!isTv && (it.isMovie || it.type == 'movie')) {
              matchedItem = it;
              break;
            }
          }
        }
        matchedItem ??= searchResults.where((it) {
          return isTv ? (it.isShow || it.type == 'show') : (it.isMovie || it.type == 'movie');
        }).firstOrNull;
      }
    } catch (e) {
      debugPrint('[SeerrRequestDialog] _goToMedia error: $e');
    }

    if (!mounted) return;
    setState(() => _isLocatingMedia = false);

    if (matchedItem != null) {
      Navigator.of(context).pop(false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetailsScreen(
            initialItem: matchedItem!,
            server: widget.server,
            clientId: widget.clientId,
            availableServers: widget.availableServers,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not locate "$targetTitle" on ${widget.server.name}.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  Future<void> _watchTrailer() async {
    if (_isLocatingTrailer) return;
    setState(() => _isLocatingTrailer = true);

    final title = _details?.title.isNotEmpty == true ? _details!.title : widget.item.title;
    final year = _details?.year.isNotEmpty == true ? _details!.year : widget.item.year;

    try {
      // 1. Resolve YouTube trailer key via cache -> TMDB/Seerr relatedVideos -> KinoCheck API fallback
      final videoKey = await SeerrService().resolveYoutubeTrailerKey(
        widget.item.id,
        relatedVideos: _details?.relatedVideos ?? const [],
      );

      if (videoKey != null && videoKey.isNotEmpty) {
        if (mounted) setState(() => _isLocatingTrailer = false);
        await PlixDeviceHelper.openYoutubeTrailer(videoKey, title: title);
        return;
      }

      // 2. If item already exists in local Plex library with metadata, check local server extras
      PlexMediaItem? trailerItem;
      PlexServer? serverToUse;
      if (widget.server.isPlex && _details?.ratingKey != null && _details!.ratingKey!.isNotEmpty) {
        try {
          trailerItem = await PlexMediaService.forServer(widget.server).getMovieTrailer(_details!.ratingKey!);
          if (trailerItem != null) serverToUse = widget.server;
        } catch (_) {}
      }

      if (trailerItem != null) {
        if (!mounted) return;
        setState(() => _isLocatingTrailer = false);
        NativePlayerService().stop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              item: trailerItem!,
              server: serverToUse ?? widget.server,
              clientId: widget.clientId,
              initialPositionMs: 0,
            ),
          ),
        );
        return;
      }

      // 3. Fallback: Search YouTube directly for the official movie trailer
      final fallbackQuery = Uri.encodeComponent('$title $year official trailer');
      final fallbackUrl = 'https://www.youtube.com/results?search_query=$fallbackQuery';
      if (mounted) setState(() => _isLocatingTrailer = false);
      await PlixDeviceHelper.openUrl(fallbackUrl);
    } catch (e) {
      if (mounted) {
        setState(() => _isLocatingTrailer = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play trailer: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatStatus(int? status) {
    if (_details != null && _details!.isMovie) {
      if (_details!.isStandardAvailable && _details!.is4kAvailable) {
        return 'Available (HD & 4K)';
      } else if (_details!.is4kAvailable) {
        return 'Available (4K)';
      } else if (_details!.isStandardAvailable) {
        return 'Available';
      } else if (_details!.is4kRequestedOrAvailable && _details!.isStandardRequestedOrAvailable) {
        return 'Requested (HD & 4K)';
      } else if (_details!.is4kRequestedOrAvailable) {
        return 'Requested (4K)';
      } else if (_details!.isStandardRequestedOrAvailable) {
        return 'Requested';
      }
    }
    switch (status) {
      case 2:
        return 'Pending Approval';
      case 3:
        return 'Processing';
      case 4:
        return 'Partially Available';
      case 5:
        return 'Available';
      default:
        return 'Not Requested';
    }
  }

  Color _statusColor(int? status) {
    if (_details != null && _details!.isAnyAvailable) {
      return Colors.greenAccent;
    }
    if (_details != null && (_details!.isStandardRequestedOrAvailable || _details!.is4kRequestedOrAvailable)) {
      return Colors.orangeAccent;
    }
    switch (status) {
      case 2:
        return Colors.orangeAccent;
      case 3:
        return Colors.lightBlueAccent;
      case 4:
        return Colors.tealAccent;
      case 5:
        return Colors.greenAccent;
      default:
        return PlixTheme.textMuted;
    }
  }

  Widget _buildPosterPlaceholder(double width, double height, {double radius = 10}) {
    final isTv = widget.item.isTv || (_details?.isTv == true);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF1B1D28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTv ? Icons.tv_off_rounded : Icons.movie_filter_rounded,
                size: width > 120 ? 36 : 24,
                color: PlixTheme.textMuted.withOpacity(0.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'No poster\navailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PlixTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterWidget(String posterUrl, double width, double height, {double radius = 10}) {
    if (posterUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: height,
          child: CachedNetworkImage(
            imageUrl: posterUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: const Color(0xFF1B1D28),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => _buildPosterPlaceholder(width, height, radius: radius),
          ),
        ),
      );
    }
    return _buildPosterPlaceholder(width, height, radius: radius);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(1000.0, screenSize.width * 0.92);
    final dialogHeight = math.min(840.0, screenSize.height * 0.94);
    final isCompact = screenSize.width < 700;

    final title = _details?.title.isNotEmpty == true ? _details!.title : widget.item.title;
    final year = _details?.year.isNotEmpty == true ? _details!.year : widget.item.year;
    final overview = _details?.overview ?? widget.item.overview ?? 'No synopsis available.';
    final posterUrl = _details?.posterUrl.isNotEmpty == true ? _details!.posterUrl : widget.item.posterUrl;
    final backdropUrl = _details?.backdropUrl.isNotEmpty == true ? _details!.backdropUrl : widget.item.backdropUrl;
    final isMovie = widget.item.isMovie || (_details?.isMovie == true);
    final isTv = widget.item.isTv || (_details?.isTv == true);
    final mediaStatus = _details?.mediaStatus ?? widget.item.mediaStatus;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.04,
        vertical: screenSize.height * 0.03,
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF14151C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PlixTheme.cardBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Faint Backdrop Banner (compact height to maximize content room)
            if (backdropUrl.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 160,
                child: Opacity(
                  opacity: 0.16,
                  child: CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),

            // Top gradient overlay for backdrop
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF14151C).withOpacity(0.35),
                      const Color(0xFF14151C),
                    ],
                  ),
                ),
              ),
            ),

            // Main Content Area
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar with Server and Close Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: PlixTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: PlixTheme.cardBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.server.isJellyfin ? Icons.cloud_outlined : Icons.live_tv_rounded,
                                size: 14,
                                color: PlixTheme.plexGold,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.server.name,
                                style: const TextStyle(
                                  color: PlixTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isMovie ? Colors.blue.withOpacity(0.2) : Colors.purple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isMovie ? 'MOVIE' : 'TV SERIES',
                            style: TextStyle(
                              color: isMovie ? Colors.lightBlueAccent : Colors.purpleAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Close button on non-TV only
                        if (!PlixDeviceHelper.isTelevision)
                          IconButton(
                            focusNode: _closeButtonFocus,
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Body: Poster + Details
                    Expanded(
                      child: isCompact
                          ? _buildCompactBody(
                              title: title,
                              year: year,
                              overview: overview,
                              posterUrl: posterUrl,
                              mediaStatus: mediaStatus,
                              isMovie: isMovie,
                              isTv: isTv,
                            )
                          : _buildExpandedBody(
                              title: title,
                              year: year,
                              overview: overview,
                              posterUrl: posterUrl,
                              mediaStatus: mediaStatus,
                              isMovie: isMovie,
                              isTv: isTv,
                            ),
                    ),

                    // Error message banner if any
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Action buttons bar
                    Builder(
                      builder: (context) {
                        final actionButtons = <Widget>[
                          if (isMovie) ...[
                            // 1. Available: "Go to Movie" button (primary)
                            //    Not Available: "Watch Trailer" button (primary, in its place)
                            if (_details?.isAnyAvailable == true || mediaStatus == 5)
                              PlixButton(
                                label: _isLocatingMedia ? 'Opening...' : 'Go to Movie',
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                icon: _isLocatingMedia
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.play_arrow_rounded, size: 16),
                                isPrimary: true,
                                focusNode: _goToMediaFocus,
                                onRight: () {
                                  if (_details?.isStandardAvailable != true && mediaStatus != 5) {
                                    if (_details?.isStandardRequestedOrAvailable == true) {
                                      _requestedStandardFocus.requestFocus();
                                    } else {
                                      _submitStandardFocus.requestFocus();
                                    }
                                  } else if (_details?.is4kAvailable != true) {
                                    if (_details?.is4kRequestedOrAvailable == true) {
                                      _requested4kFocus.requestFocus();
                                    } else {
                                      _submit4kFocus.requestFocus();
                                    }
                                  } else {
                                    _cancelButtonFocus.requestFocus();
                                  }
                                },
                                onPressed: _isLocatingMedia ? () {} : _goToMedia,
                              )
                            else
                              PlixButton(
                                label: _isLocatingTrailer ? 'Loading...' : 'Watch Trailer',
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                icon: _isLocatingTrailer
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.theaters_rounded, size: 16),
                                isPrimary: true,
                                focusNode: _watchTrailerFocus,
                                onRight: () {
                                  if (_details?.isStandardAvailable != true && mediaStatus != 5) {
                                    if (_details?.isStandardRequestedOrAvailable == true) {
                                      _requestedStandardFocus.requestFocus();
                                    } else {
                                      _submitStandardFocus.requestFocus();
                                    }
                                  } else if (_details?.is4kAvailable != true) {
                                    if (_details?.is4kRequestedOrAvailable == true) {
                                      _requested4kFocus.requestFocus();
                                    } else {
                                      _submit4kFocus.requestFocus();
                                    }
                                  } else {
                                    _cancelButtonFocus.requestFocus();
                                  }
                                },
                                onPressed: _isLocatingTrailer ? () {} : _watchTrailer,
                              ),

                            // 2. Standard request button (outline style, matches request 4k)
                            if (_details?.isStandardAvailable != true && mediaStatus != 5) ...[
                              if (_details?.isStandardRequestedOrAvailable == true)
                                PlixButton(
                                  label: 'Requested',
                                  fontSize: 12.5,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  icon: const Icon(Icons.check_rounded, size: 15),
                                  isPrimary: false,
                                  focusNode: _requestedStandardFocus,
                                  onLeft: () {
                                    if (_details?.isAnyAvailable == true || mediaStatus == 5) {
                                      _goToMediaFocus.requestFocus();
                                    } else {
                                      _watchTrailerFocus.requestFocus();
                                    }
                                  },
                                  onRight: () {
                                    if (_details?.is4kAvailable != true) {
                                      if (_details?.is4kRequestedOrAvailable == true) {
                                        _requested4kFocus.requestFocus();
                                      } else {
                                        _submit4kFocus.requestFocus();
                                      }
                                    } else {
                                      _cancelButtonFocus.requestFocus();
                                    }
                                  },
                                  onPressed: () {},
                                )
                              else
                                PlixButton(
                                  label: _isSubmitting ? 'Requesting...' : 'Request Movie',
                                  fontSize: 12.5,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                        )
                                      : const Icon(Icons.send_rounded, size: 15),
                                  isPrimary: false,
                                  focusNode: _submitStandardFocus,
                                  onLeft: () {
                                    if (_details?.isAnyAvailable == true || mediaStatus == 5) {
                                      _goToMediaFocus.requestFocus();
                                    } else {
                                      _watchTrailerFocus.requestFocus();
                                    }
                                  },
                                  onRight: () {
                                    if (_details?.is4kAvailable != true) {
                                      if (_details?.is4kRequestedOrAvailable == true) {
                                        _requested4kFocus.requestFocus();
                                      } else {
                                        _submit4kFocus.requestFocus();
                                      }
                                    } else {
                                      _cancelButtonFocus.requestFocus();
                                    }
                                  },
                                  onPressed: () {
                                    if (_isSubmitting) return;
                                    _submitRequest(is4k: false);
                                  },
                                ),
                            ],

                            // 3. 4K request button (outline style)
                            if (_details?.is4kAvailable != true) ...[
                              if (_details?.is4kRequestedOrAvailable == true)
                                PlixButton(
                                  label: '4K Requested',
                                  fontSize: 12.5,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  icon: const Icon(Icons.check_rounded, size: 15),
                                  isPrimary: false,
                                  focusNode: _requested4kFocus,
                                  onLeft: () {
                                    if (_details?.isStandardAvailable != true && mediaStatus != 5) {
                                      if (_details?.isStandardRequestedOrAvailable == true) {
                                        _requestedStandardFocus.requestFocus();
                                      } else {
                                        _submitStandardFocus.requestFocus();
                                      }
                                    } else if (_details?.isAnyAvailable == true || mediaStatus == 5) {
                                      _goToMediaFocus.requestFocus();
                                    } else {
                                      _watchTrailerFocus.requestFocus();
                                    }
                                  },
                                  onRight: () => _cancelButtonFocus.requestFocus(),
                                  onPressed: () {},
                                )
                              else
                                PlixButton(
                                  label: _isSubmitting ? 'Requesting...' : 'Request in 4K',
                                  fontSize: 12.5,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                        )
                                      : const Icon(Icons.four_k_rounded, size: 16),
                                  isPrimary: false,
                                  focusNode: _submit4kFocus,
                                  onLeft: () {
                                    if (_details?.isStandardAvailable != true && mediaStatus != 5) {
                                      if (_details?.isStandardRequestedOrAvailable == true) {
                                        _requestedStandardFocus.requestFocus();
                                      } else {
                                        _submitStandardFocus.requestFocus();
                                      }
                                    } else if (_details?.isAnyAvailable == true || mediaStatus == 5) {
                                      _goToMediaFocus.requestFocus();
                                    } else {
                                      _watchTrailerFocus.requestFocus();
                                    }
                                  },
                                  onRight: () => _cancelButtonFocus.requestFocus(),
                                  onPressed: () {
                                    if (_isSubmitting) return;
                                    _submitRequest(is4k: true);
                                  },
                                ),
                            ],
                          ] else if (isTv) ...[
                            // TV Series
                            if (_isContentAvailable)
                              PlixButton(
                                label: _isLocatingMedia ? 'Opening...' : 'Go to Series',
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                icon: _isLocatingMedia
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.play_arrow_rounded, size: 16),
                                isPrimary: true,
                                focusNode: _goToMediaFocus,
                                onRight: () => _cancelButtonFocus.requestFocus(),
                                onPressed: _isLocatingMedia ? () {} : _goToMedia,
                              )
                            else if (_isAllAvailableOrRequested)
                              PlixButton(
                                label: 'All Seasons Requested',
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                icon: const Icon(Icons.check_rounded, size: 15),
                                isPrimary: false,
                                focusNode: _submitStandardFocus,
                                onRight: () => _cancelButtonFocus.requestFocus(),
                                onPressed: () {},
                              )
                            else
                              PlixButton(
                                label: _isSubmitting ? 'Requesting...' : 'Request Seasons',
                                fontSize: 12.5,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                      )
                                    : const Icon(Icons.send_rounded, size: 15),
                                isPrimary: _selectedSeasons.isNotEmpty,
                                focusNode: _submitStandardFocus,
                                onUp: () {
                                  final seasons = _details?.seasons ?? [];
                                  if (seasons.isNotEmpty) {
                                    final targetSeason = _lastFocusedSeasonNumber ?? seasons.last.seasonNumber;
                                    _seasonFocusNodes[targetSeason]?.requestFocus();
                                  }
                                },
                                onRight: () => _cancelButtonFocus.requestFocus(),
                                onPressed: () {
                                  if (_isSubmitting || _selectedSeasons.isEmpty) return;
                                  _submitRequest();
                                },
                              ),
                          ],

                          // Cancel button is always placed at the bottom / end of the buttons
                          PlixButton(
                            label: 'Cancel',
                            fontSize: 12.5,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            isPrimary: false,
                            focusNode: _cancelButtonFocus,
                            onUp: () {
                              if (isTv) {
                                final seasons = _details?.seasons ?? [];
                                if (seasons.isNotEmpty) {
                                  final targetSeason = _lastFocusedSeasonNumber ?? seasons.last.seasonNumber;
                                  _seasonFocusNodes[targetSeason]?.requestFocus();
                                }
                              }
                            },
                            onLeft: () {
                              if (isMovie) {
                                if (_details?.is4kAvailable != true) {
                                  if (_details?.is4kRequestedOrAvailable == true) {
                                    _requested4kFocus.requestFocus();
                                  } else {
                                    _submit4kFocus.requestFocus();
                                  }
                                } else if (_details?.isStandardAvailable != true && mediaStatus != 5) {
                                  if (_details?.isStandardRequestedOrAvailable == true) {
                                    _requestedStandardFocus.requestFocus();
                                  } else {
                                    _submitStandardFocus.requestFocus();
                                  }
                                } else if (_details?.isAnyAvailable == true || mediaStatus == 5) {
                                  _goToMediaFocus.requestFocus();
                                } else {
                                  _watchTrailerFocus.requestFocus();
                                }
                              } else if (isTv) {
                                if (!_isContentAvailable && !_isAllAvailableOrRequested) {
                                  _submitStandardFocus.requestFocus();
                                } else if (_isContentAvailable) {
                                  _goToMediaFocus.requestFocus();
                                }
                              }
                            },
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ];

                        if (!isCompact) {
                          return Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: actionButtons,
                          );
                        }

                        // Compact portrait/mobile layout: clean symmetrical 2-column rows
                        final rows = <Widget>[];
                        for (int i = 0; i < actionButtons.length; i += 2) {
                          if (i > 0) rows.add(const SizedBox(height: 8));
                          if (i + 1 < actionButtons.length) {
                            rows.add(
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: actionButtons[i],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: actionButtons[i + 1],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            rows.add(
                              SizedBox(
                                width: double.infinity,
                                child: actionButtons[i],
                              ),
                            );
                          }
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBody({
    required String title,
    required String year,
    required String overview,
    required String posterUrl,
    required int? mediaStatus,
    required bool isMovie,
    required bool isTv,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Poster with fallback
        _buildPosterWidget(posterUrl, 180, 270, radius: 10),

        const SizedBox(width: 22),

        // Right Column: Title, Metadata, Overview, Seasons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),

              // Metadata Row: Year, Runtime, Genres, Rating, Status
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (year.isNotEmpty)
                    Text(
                      year,
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                    ),
                  if (_details?.runtime != null && _details!.runtime! > 0)
                    Text(
                      '${_details!.runtime}m',
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                    ),
                  if (_details?.genres.isNotEmpty == true)
                    Text(
                      _details!.genres.take(3).join(', '),
                      style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
                    ),
                  if (_details?.voteAverage != null && _details!.voteAverage! > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 15, color: PlixTheme.plexGold),
                        const SizedBox(width: 4),
                        Text(
                          _details!.voteAverage!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  // Availability Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor(mediaStatus).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _statusColor(mediaStatus).withOpacity(0.5)),
                    ),
                    child: Text(
                      _formatStatus(mediaStatus),
                      style: TextStyle(
                        color: _statusColor(mediaStatus),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Overview (compact lines for TV series so seasons list has maximum space; full scrollable overview for movies)
              if (isTv) ...[
                Text(
                  overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlixTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: PlixTheme.cardBorder, height: 1),
                const SizedBox(height: 6),
                Expanded(
                  child: _buildTvSeasonSelector(),
                ),
              ] else ...[
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      overview,
                      style: const TextStyle(
                        color: PlixTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
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

  Widget _buildCompactBody({
    required String title,
    required String year,
    required String overview,
    required String posterUrl,
    required int? mediaStatus,
    required bool isMovie,
    required bool isTv,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPosterWidget(posterUrl, 90, 135, radius: 8),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$year • ${_formatStatus(mediaStatus)}',
                style: TextStyle(
                  color: _statusColor(mediaStatus),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (isTv && screenHeight >= 500) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerRow,
          const SizedBox(height: 10),
          Text(
            overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Divider(color: PlixTheme.cardBorder, height: 1),
          const SizedBox(height: 6),
          Expanded(
            child: _buildTvSeasonSelector(),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerRow,
          const SizedBox(height: 10),
          Text(
            overview,
            maxLines: isTv ? 3 : null,
            overflow: isTv ? TextOverflow.ellipsis : TextOverflow.visible,
            style: const TextStyle(color: PlixTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (isTv) ...[
            Divider(color: PlixTheme.cardBorder, height: 1),
            const SizedBox(height: 6),
            SizedBox(
              height: 240,
              child: _buildTvSeasonSelector(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTvSeasonSelector() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final seasons = _details?.seasons ?? [];
    if (seasons.isEmpty) {
      return const Center(
        child: Text(
          'No season details available.',
          style: TextStyle(color: PlixTheme.textMuted, fontSize: 13),
        ),
      );
    }

    final selectableSeasons = seasons.where((s) => !s.isAvailableOrRequested).toList();
    final bool isAllRequested = _isAllAvailableOrRequested || selectableSeasons.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with "All Seasons" checkbox
        Row(
          children: [
            const Text(
              'SEASONS',
              style: TextStyle(
                color: PlixTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${seasons.length})',
              style: const TextStyle(color: PlixTheme.textMuted, fontSize: 11.5),
            ),
            const Spacer(),
            Focus(
              focusNode: _allSeasonsFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    if (seasons.isNotEmpty) {
                      _seasonFocusNodes[seasons.first.seasonNumber]?.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    if (_isContentAvailable) {
                      _goToMediaFocus.requestFocus();
                    } else if (!_isAllAvailableOrRequested) {
                      _submitStandardFocus.requestFocus();
                    } else {
                      _cancelButtonFocus.requestFocus();
                    }
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    return KeyEventResult.handled;
                  }
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                       event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.space)) {
                    if (!isAllRequested) {
                      _toggleAllSeasons(!_isAllSelectableSelected);
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: AnimatedBuilder(
                animation: _allSeasonsFocus,
                builder: (context, _) {
                  final isFocused = _allSeasonsFocus.hasFocus;
                  return InkWell(
                    onTap: isAllRequested ? null : () => _toggleAllSeasons(!_isAllSelectableSelected),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isFocused ? Colors.white.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: isFocused
                            ? (PlixTheme.isRainbowBorder
                                ? PlixTheme.rainbowOutlineBorder(width: 1.8)
                                : Border.all(color: PlixTheme.plexGold, width: 1.8))
                            : Border.all(color: Colors.transparent, width: 1.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: isAllRequested ? true : _isAllSelectableSelected,
                              activeColor: isAllRequested ? Colors.grey.shade600 : PlixTheme.plexGold,
                              checkColor: Colors.black,
                              onChanged: isAllRequested ? null : (val) => _toggleAllSeasons(val),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'All Seasons',
                            style: TextStyle(
                              color: isAllRequested ? PlixTheme.textMuted : Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Scrollable seasons list (compact height so many seasons fit on screen)
        Expanded(
          child: ListView.separated(
            controller: _seasonsScrollController,
            itemCount: seasons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final season = seasons[index];
              final isAlreadyPresent = season.isAvailableOrRequested || isAllRequested;
              final isSelected = isAlreadyPresent || _selectedSeasons.contains(season.seasonNumber);
              final tileKey = _seasonTileKeys.putIfAbsent(season.seasonNumber, () => GlobalKey());

              final fn = _seasonFocusNodes.putIfAbsent(
                season.seasonNumber,
                () {
                  final node = FocusNode();
                  node.addListener(() {
                    if (node.hasFocus && mounted) {
                      _lastFocusedSeasonNumber = season.seasonNumber;
                      final ctx = tileKey.currentContext;
                      if (ctx != null) {
                        Scrollable.ensureVisible(
                          ctx,
                          alignment: 0.5,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    }
                  });
                  return node;
                },
              );

              return KeyedSubtree(
                key: tileKey,
                child: Focus(
                  focusNode: fn,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent || event is KeyRepeatEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        if (index == 0) {
                          _allSeasonsFocus.requestFocus();
                          return KeyEventResult.handled;
                        } else {
                          final prevSeason = seasons[index - 1];
                          _seasonFocusNodes[prevSeason.seasonNumber]?.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (_isContentAvailable) {
                          _goToMediaFocus.requestFocus();
                        } else if (!_isAllAvailableOrRequested) {
                          _submitStandardFocus.requestFocus();
                        } else {
                          _cancelButtonFocus.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (index == seasons.length - 1) {
                          if (_isContentAvailable) {
                            _goToMediaFocus.requestFocus();
                          } else if (!_isAllAvailableOrRequested) {
                            _submitStandardFocus.requestFocus();
                          } else {
                            _cancelButtonFocus.requestFocus();
                          }
                          return KeyEventResult.handled;
                        } else {
                          final nextSeason = seasons[index + 1];
                          _seasonFocusNodes[nextSeason.seasonNumber]?.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      if (event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.select ||
                           event.logicalKey == LogicalKeyboardKey.enter ||
                           event.logicalKey == LogicalKeyboardKey.space)) {
                        if (!isAlreadyPresent) {
                          _toggleSeason(season.seasonNumber);
                        }
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimatedBuilder(
                    animation: fn,
                    builder: (context, _) {
                      final isFocused = fn.hasFocus;

                      final BoxBorder tileBorder = isFocused
                          ? (PlixTheme.isRainbowBorder
                              ? PlixTheme.rainbowOutlineBorder(width: 2.0)
                              : Border.all(color: PlixTheme.plexGold, width: 2.0))
                          : Border.all(
                              color: isSelected && !isAlreadyPresent
                                  ? PlixTheme.plexGold.withOpacity(0.4)
                                  : PlixTheme.cardBorder,
                              width: 1.0,
                            );

                      final Color tileBg = isFocused
                          ? (PlixTheme.isRainbowBorder
                              ? Colors.white.withOpacity(0.14)
                              : PlixTheme.plexGold.withOpacity(0.18))
                          : (isAlreadyPresent
                              ? Colors.white.withOpacity(0.03)
                              : (isSelected
                                  ? Colors.white.withOpacity(0.08)
                                  : PlixTheme.surface));

                      return InkWell(
                        onTap: isAlreadyPresent ? null : () => _toggleSeason(season.seasonNumber),
                        borderRadius: BorderRadius.circular(6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: tileBg,
                            borderRadius: BorderRadius.circular(6),
                            border: tileBorder,
                            boxShadow: (isFocused && !PlixTheme.isRainbowBorder)
                                ? [
                                    BoxShadow(
                                      color: PlixTheme.plexGold.withOpacity(0.25),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: isSelected,
                                  activeColor: isAlreadyPresent ? Colors.grey.shade600 : PlixTheme.plexGold,
                                  checkColor: Colors.black,
                                  onChanged: isAlreadyPresent ? null : (_) => _toggleSeason(season.seasonNumber),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                season.name,
                                style: TextStyle(
                                  color: isAlreadyPresent
                                      ? PlixTheme.textMuted
                                      : (isFocused ? Colors.white : PlixTheme.textPrimary),
                                  fontSize: 13,
                                  fontWeight: isFocused || isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                              if (season.episodeCount > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '(${season.episodeCount} ep)',
                                  style: TextStyle(
                                    color: isAlreadyPresent ? Colors.grey.shade700 : PlixTheme.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (isAlreadyPresent)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: season.isAvailable
                                        ? Colors.green.withOpacity(0.18)
                                        : Colors.blue.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: season.isAvailable
                                          ? Colors.greenAccent.withOpacity(0.5)
                                          : Colors.lightBlueAccent.withOpacity(0.5),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    season.isAvailable ? 'Available' : 'Requested',
                                    style: TextStyle(
                                      color: season.isAvailable ? Colors.greenAccent : Colors.lightBlueAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
