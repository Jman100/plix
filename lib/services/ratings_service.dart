import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_service.dart';

enum RatingsMode {
  off,
  detailsOnly,
  posters;

  static RatingsMode fromString(String? val) {
    switch (val) {
      case 'off':
        return RatingsMode.off;
      case 'posters':
        return RatingsMode.posters;
      case 'details_only':
      default:
        return RatingsMode.detailsOnly;
    }
  }

  String toKey() {
    switch (this) {
      case RatingsMode.off:
        return 'off';
      case RatingsMode.posters:
        return 'posters';
      case RatingsMode.detailsOnly:
        return 'details_only';
    }
  }

  String get label {
    switch (this) {
      case RatingsMode.off:
        return 'Off';
      case RatingsMode.detailsOnly:
        return 'Show in Details Only';
      case RatingsMode.posters:
        return 'Show on Posters';
    }
  }
}

class RatingsService extends ChangeNotifier {
  static final RatingsService instance = RatingsService._internal();
  RatingsService._internal();

  RatingsMode _mode = RatingsMode.detailsOnly;
  RatingsMode get mode => _mode;

  bool get isOff => _mode == RatingsMode.off;
  bool get showInDetails => _mode == RatingsMode.detailsOnly || _mode == RatingsMode.posters;
  bool get showOnPosters => _mode == RatingsMode.posters;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = ProfileService.key('show_ratings');
      final val = prefs.getString(key) ?? prefs.getString('show_ratings');
      _mode = RatingsMode.fromString(val);
      notifyListeners();
    } catch (e) {
      debugPrint('[RatingsService] Error initializing ratings settings: $e');
    }
  }

  Future<void> setMode(RatingsMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = ProfileService.key('show_ratings');
      await prefs.setString(key, newMode.toKey());
      await prefs.setString('show_ratings', newMode.toKey());
    } catch (e) {
      debugPrint('[RatingsService] Error saving ratings mode: $e');
    }
  }

  Future<void> cycleMode() async {
    final next = _mode == RatingsMode.detailsOnly
        ? RatingsMode.posters
        : _mode == RatingsMode.posters
            ? RatingsMode.off
            : RatingsMode.detailsOnly;
    await setMode(next);
  }
}
