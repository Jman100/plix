import 'package:flutter/material.dart';
import '../models/plex_media_item.dart';
import '../services/plex_media_service.dart';
import '../app_theme.dart';

/// Rotten Tomatoes Critic Icon Widget using official assets
class TomatoIconWidget extends StatelessWidget {
  final bool isFresh;
  final bool isCertified;
  final double size;

  const TomatoIconWidget({
    super.key,
    required this.isFresh,
    this.isCertified = false,
    this.size = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = isCertified
        ? 'assets/ratings/rt_certified.png'
        : (isFresh ? 'assets/ratings/rt_fresh.png' : 'assets/ratings/rt_rotten.png');

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Rotten Tomatoes Audience Popcorn Icon Widget using official assets
class PopcornIconWidget extends StatelessWidget {
  final bool isFresh;
  final double size;

  const PopcornIconWidget({
    super.key,
    required this.isFresh,
    this.size = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = isFresh
        ? 'assets/ratings/rt_popcorn_fresh.png'
        : 'assets/ratings/rt_popcorn_spilled.png';

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Rotten Tomatoes ratings display (Critic and Audience) for movies
class RottenTomatoesRatingBadge extends StatelessWidget {
  final PlexMediaItem item;
  final double fontSize;
  final double iconSize;

  const RottenTomatoesRatingBadge({
    super.key,
    required this.item,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    final criticScore = item.rtCriticScore;
    final audienceScore = item.rtAudienceScore;

    if (criticScore == null && audienceScore == null) {
      return const SizedBox.shrink();
    }

    final hasCritic = criticScore != null;
    final hasAudience = audienceScore != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasCritic) ...[
          TomatoIconWidget(
            isFresh: item.isRtFresh,
            isCertified: item.isRtCertified,
            size: iconSize,
          ),
          const SizedBox(width: 4),
          Text(
            '$criticScore%',
            style: TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ],
        if (hasCritic && hasAudience) const SizedBox(width: 8),
        if (hasAudience) ...[
          PopcornIconWidget(
            isFresh: item.isRtAudienceFresh,
            size: iconSize,
          ),
          const SizedBox(width: 4),
          Text(
            '$audienceScore%',
            style: TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}

/// IMDb rating badge display using official IMDb asset logo
class ImdbRatingBadge extends StatelessWidget {
  final String rating;
  final double fontSize;
  final double iconSize;

  const ImdbRatingBadge({
    super.key,
    required this.rating,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    if (rating.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: Image.asset(
            'assets/ratings/imdb.png',
            height: iconSize * 0.95,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          rating,
          style: TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// TheTVDB rating badge display using official TVDB asset logo
class TvdbRatingBadge extends StatelessWidget {
  final String rating;
  final double fontSize;
  final double iconSize;

  const TvdbRatingBadge({
    super.key,
    required this.rating,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    if (rating.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: Image.asset(
            'assets/ratings/tvdb.png',
            height: iconSize * 0.95,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          rating,
          style: TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// TheMovieDb (TMDb) Rating Badge
class TmdbRatingBadge extends StatelessWidget {
  final String rating;
  final double fontSize;
  final double iconSize;

  const TmdbRatingBadge({
    super.key,
    required this.rating,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    if (rating.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: Image.asset(
            'assets/ratings/tmdb.png',
            height: iconSize * 0.95,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          rating,
          style: TextStyle(
            color: PlixTheme.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// Unified media rating widget:
/// - Movies: Rotten Tomatoes critic & audience scores (or fallback to TMDB/IMDb/TVDB if no RT scores)
/// - TV Shows & Episodes: IMDb score (or TheTVDB score for Jellyfin/TVDB content)
class MediaRatingWidget extends StatelessWidget {
  final PlexMediaItem item;
  final double fontSize;
  final double iconSize;
  final bool isEpisodeRow;

  const MediaRatingWidget({
    super.key,
    required this.item,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
    this.isEpisodeRow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isMovie) {
      if (item.hasRtRatings) {
        return RottenTomatoesRatingBadge(
          item: item,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      } else if (item.hasTmdbRating) {
        return TmdbRatingBadge(
          rating: item.formattedTmdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      } else if (item.hasImdbRating) {
        return ImdbRatingBadge(
          rating: item.formattedImdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      } else if (item.hasTvdbRating) {
        if (item.isJellyfin) {
          return TmdbRatingBadge(
            rating: item.formattedTvdbRating,
            fontSize: fontSize,
            iconSize: iconSize,
          );
        }
        return TvdbRatingBadge(
          rating: item.formattedTvdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }
      return const SizedBox.shrink();
    }

    if (item.isShow || item.isEpisode) {
      // For Jellyfin content, show TMDb badge with official TMDB logo
      if (item.isJellyfin) {
        final r = item.formattedTmdbRating.isNotEmpty
            ? item.formattedTmdbRating
            : (item.formattedTvdbRating.isNotEmpty ? item.formattedTvdbRating : item.formattedImdbRating);
        if (r.isNotEmpty) {
          return TmdbRatingBadge(
            rating: r,
            fontSize: fontSize,
            iconSize: iconSize,
          );
        }
        return const SizedBox.shrink();
      }

      // Check detailed cache for Plex items
      if (!item.isJellyfin) {
        final cached = PlexMediaService.findDetailedCached(item.ratingKey);
        if (cached != null && cached.hasImdbRating) {
          return ImdbRatingBadge(
            rating: cached.formattedImdbRating,
            fontSize: fontSize,
            iconSize: iconSize,
          );
        }
      }

      // For Plex content or items with IMDb ratings, show IMDb
      if (item.hasImdbRating) {
        return ImdbRatingBadge(
          rating: item.formattedImdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }

      // Fallback for TV show library posters & episode rows that carry TMDb / community rating
      if (item.hasTmdbRating) {
        return ImdbRatingBadge(
          rating: item.formattedTmdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }

      // Fallback to TVDB rating if present
      if (item.hasTvdbRating) {
        return ImdbRatingBadge(
          rating: item.formattedTvdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }

      // General fallback if item has rating or audienceRating
      if (item.rating != null && item.rating! > 0) {
        return ImdbRatingBadge(
          rating: item.rating!.toStringAsFixed(1),
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }
      if (item.audienceRating != null && item.audienceRating! > 0) {
        return ImdbRatingBadge(
          rating: item.audienceRating!.toStringAsFixed(1),
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }

      return const SizedBox.shrink();
    }

    // General fallback for unknown type
    if (item.hasRtRatings) {
      return RottenTomatoesRatingBadge(
        item: item,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else if (item.hasTmdbRating) {
      return TmdbRatingBadge(
        rating: item.formattedTmdbRating,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else if (item.hasImdbRating) {
      return ImdbRatingBadge(
        rating: item.formattedImdbRating,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else if (item.hasTvdbRating) {
      if (item.isJellyfin) {
        return TmdbRatingBadge(
          rating: item.formattedTvdbRating,
          fontSize: fontSize,
          iconSize: iconSize,
        );
      }
      return TvdbRatingBadge(
        rating: item.formattedTvdbRating,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    }

    return const SizedBox.shrink();
  }
}
