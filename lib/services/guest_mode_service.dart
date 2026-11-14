import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plex_media_item.dart';
import 'profile_service.dart';

/// Guest Mode Service
/// Manages temporary, isolated in-memory watch history and session state.
/// When Guest Mode is active, no watch history is saved to the server,
/// the profile owner's continue watching row is hidden, and all temporary
/// progress collected during the session is immediately purged on exit.
class GuestModeService {
  GuestModeService._();
  static final GuestModeService instance = GuestModeService._();

  final ValueNotifier<bool> isGuestModeNotifier = ValueNotifier<bool>(false);
  bool get isGuestMode => isGuestModeNotifier.value;

  final ValueNotifier<List<PlexMediaItem>> guestContinueWatchingNotifier =
      ValueNotifier<List<PlexMediaItem>>([]);
  List<PlexMediaItem> get continueWatching => guestContinueWatchingNotifier.value;

  final Map<String, int> _guestViewOffsets = {};
  final Map<String, int> _guestDurations = {};
  final Set<String> _guestWatched = {};

  Future<void> init() async {
    // Guest mode is transient. When the app starts up, even if guest mode
    // was last active (e.g. after a crash or force-close), the guest mode
    // instance is removed and the app always starts in regular mode.
    await exitGuestMode();
  }

  Future<void> setGuestMode(bool enabled) async {
    if (!enabled) {
      await exitGuestMode();
    } else {
      isGuestModeNotifier.value = true;
      _guestViewOffsets.clear();
      _guestDurations.clear();
      _guestWatched.clear();
      guestContinueWatchingNotifier.value = [];
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(ProfileService.key('guest_mode'));
        await prefs.remove(ProfileService.key('anonymous_mode'));
        await prefs.remove('guest_mode');
        await prefs.remove('anonymous_mode');
      } catch (_) {}
    }
  }

  Future<void> exitGuestMode() async {
    // Purge all temporary in-memory watch history collected during guest mode
    _guestViewOffsets.clear();
    _guestDurations.clear();
    _guestWatched.clear();
    guestContinueWatchingNotifier.value = [];
    isGuestModeNotifier.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ProfileService.key('guest_mode'));
      await prefs.remove(ProfileService.key('anonymous_mode'));
      await prefs.remove('guest_mode');
      await prefs.remove('anonymous_mode');
    } catch (_) {}
  }

  void recordPlaybackProgress(PlexMediaItem item, int positionMs, int durationMs) {
    if (!isGuestMode) return;
    if (positionMs <= 0) return;

    final totalDur = durationMs > 0 ? durationMs : (item.duration ?? 0);
    final isFinished = totalDur > 0 && positionMs >= (totalDur * 0.90);

    if (isFinished) {
      _guestWatched.add(item.ratingKey);
      _guestViewOffsets.remove(item.ratingKey);
    } else {
      _guestWatched.remove(item.ratingKey);
      _guestViewOffsets[item.ratingKey] = positionMs;
      if (durationMs > 0) {
        _guestDurations[item.ratingKey] = durationMs;
      }
    }

    final currentList = List<PlexMediaItem>.from(guestContinueWatchingNotifier.value);
    currentList.removeWhere((it) => it.ratingKey == item.ratingKey);

    if (!isFinished && positionMs >= 5000) {
      final updatedItem = item.copyWith(
        viewOffset: positionMs,
        duration: totalDur > 0 ? totalDur : item.duration,
        lastViewedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      currentList.insert(0, updatedItem);
    }

    guestContinueWatchingNotifier.value = currentList;
  }

  int? getViewOffset(String ratingKey) => _guestViewOffsets[ratingKey];
  int? getDuration(String ratingKey) => _guestDurations[ratingKey];
  bool isWatched(String ratingKey) => _guestWatched.contains(ratingKey);

  void toggleWatched(String ratingKey) {
    if (_guestWatched.contains(ratingKey)) {
      _guestWatched.remove(ratingKey);
    } else {
      _guestWatched.add(ratingKey);
      _guestViewOffsets.remove(ratingKey);
    }
  }
}
