import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plix_profile.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  static ProfileService get instance => _instance;

  ProfileService._internal();

  static const String _prefProfilesKey = 'plix_profiles_list';
  static const String _prefActiveProfileIdKey = 'plix_active_profile_id';

  final List<PlixProfile> _profiles = [];
  PlixProfile? _activeProfile;
  final ValueNotifier<PlixProfile?> activeProfileNotifier = ValueNotifier<PlixProfile?>(null);

  List<PlixProfile> get profiles => List.unmodifiable(_profiles);
  PlixProfile? get activeProfile => _activeProfile;
  static String? get activeProfileId => _instance._activeProfile?.id;

  /// True if there is only one profile and it has a PIN, or all profiles have PINs.
  /// When true, always asking "who's watching" at startup is strictly enforced.
  bool get shouldForceAlwaysAsk {
    if (_profiles.isEmpty) return false;
    return _profiles.every((p) => p.hasPin);
  }

  static String key(String baseKey) {
    final curId = activeProfileId;
    if (curId == null || curId.isEmpty) return baseKey;
    return 'prof_${curId}_$baseKey';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _profiles.clear();

    final rawJson = prefs.getString(_prefProfilesKey);
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;
        for (final item in list) {
          _profiles.add(PlixProfile.fromJson(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[ProfileService] Error parsing profiles: $e');
      }
    }

    if (_profiles.isNotEmpty) {
      final activeId = prefs.getString(_prefActiveProfileIdKey);
      _activeProfile = _profiles.firstWhere(
        (p) => p.id == activeId,
        orElse: () => _profiles.first,
      );
      activeProfileNotifier.value = _activeProfile;

      // Clean up any lingering unscoped keys so they cannot leak into other profiles
      final keysToClean = [
        'plix_auth_token',
        'plix_user',
        'plix_saved_jellyfin_servers',
        'plix_pinned_servers',
        'plix_active_server_id',
        'plix_favorite_library_composite_ids',
        'plix_server_added_order',
      ];
      for (final k in keysToClean) {
        await prefs.remove(k);
      }
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith('plix_cached_libraries_') && !k.startsWith('prof_')) {
          await prefs.remove(k);
        }
      }
      return;
    }

    // Check if migration is needed for existing users
    final hasSavedToken = prefs.containsKey('plix_auth_token');
    final hasSavedJf = prefs.containsKey('plix_saved_jellyfin_servers');
    final hasSavedActiveServer = prefs.containsKey('plix_active_server_id') || prefs.containsKey('active_server_id');
    final hasSavedFavorites = prefs.containsKey('plix_favorite_library_composite_ids');
    final isExistingUser = hasSavedToken || hasSavedJf || hasSavedActiveServer || hasSavedFavorites;

    if (isExistingUser) {
      debugPrint('[ProfileService] Migrating existing user data to Default profile...');
      const defaultId = 'default';
      final defaultProfile = PlixProfile(
        id: defaultId,
        name: 'Default',
        avatarId: 'avatar_default',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      // Copy existing settings to prof_default_ keys
      final keysToMigrate = [
        'plix_auth_token',
        'plix_auth_user',
        'plix_saved_jellyfin_servers',
        'plix_active_server_id',
        'plix_pinned_servers',
        'plix_favorite_library_composite_ids',
        'plix_server_added_order',
        'app_theme_preset_id',
        'app_theme_color_id',
        'app_theme_custom_bg',
        'app_theme_custom_surf',
        'app_theme_custom_card',
        'app_theme_custom_border',
        'app_theme_custom_color_val',
        'autoplay_next_episode',
        'autoplay_trigger_seconds',
        'auto_skip_intro',
        'continue_playback_screen_off',
        'tv_player_cast_crew',
        'quick_rewind_seconds',
        'skip_ahead_seconds',
      ];

      for (final k in keysToMigrate) {
        if (prefs.containsKey(k)) {
          final val = prefs.get(k);
          final targetKey = 'prof_${defaultId}_$k';
          if (val is String) {
            await prefs.setString(targetKey, val);
          } else if (val is bool) {
            await prefs.setBool(targetKey, val);
          } else if (val is int) {
            await prefs.setInt(targetKey, val);
          } else if (val is double) {
            await prefs.setDouble(targetKey, val);
          } else if (val is List) {
            await prefs.setStringList(targetKey, val.map((e) => e.toString()).toList());
          }
        }
      }

      // Also migrate cached libraries
      for (final k in prefs.getKeys()) {
        if (k.startsWith('plix_cached_libraries_')) {
          final val = prefs.get(k);
          final targetKey = 'prof_${defaultId}_$k';
          if (val is List) {
            await prefs.setStringList(targetKey, val.map((e) => e.toString()).toList());
          } else if (val is String) {
            await prefs.setString(targetKey, val);
          }
        }
      }

      _profiles.add(defaultProfile);
      _activeProfile = defaultProfile;
      activeProfileNotifier.value = defaultProfile;
      await _saveProfiles(prefs);
      await prefs.setString(_prefActiveProfileIdKey, defaultId);
      debugPrint('[ProfileService] Migration complete. Active profile: Default');
    } else {
      // Brand new user: profiles remain empty so initial profile creation is triggered
      _activeProfile = null;
      activeProfileNotifier.value = null;
    }
  }

  Future<void> _saveProfiles(SharedPreferences prefs) async {
    final raw = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_prefProfilesKey, raw);
  }

  Future<PlixProfile> createProfile({
    required String name,
    required String avatarId,
    String avatarColorId = 'gradient_gold',
    String? pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedName = name.trim();
    final safeName = trimmedName.length > 20 ? trimmedName.substring(0, 20) : (trimmedName.isEmpty ? 'Profile' : trimmedName);
    final cleanPin = (pin != null && pin.trim().length == 4) ? pin.trim() : null;

    final newProfile = PlixProfile(
      id: 'prof_${DateTime.now().microsecondsSinceEpoch}_${_profiles.length}',
      name: safeName,
      avatarId: avatarId,
      avatarColorId: avatarColorId,
      pin: cleanPin,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _profiles.add(newProfile);
    _activeProfile = newProfile;
    activeProfileNotifier.value = newProfile;

    await _saveProfiles(prefs);
    await prefs.setString(_prefActiveProfileIdKey, newProfile.id);
    return newProfile;
  }

  Future<void> updateProfile(PlixProfile updated) async {
    final prefs = await SharedPreferences.getInstance();
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx != -1) {
      final trimmedName = updated.name.trim();
      final safeName = trimmedName.length > 20 ? trimmedName.substring(0, 20) : (trimmedName.isEmpty ? 'Profile' : trimmedName);
      final cleanUpdated = updated.copyWith(name: safeName);
      _profiles[idx] = cleanUpdated;
      if (_activeProfile?.id == updated.id) {
        _activeProfile = updated;
        activeProfileNotifier.value = updated;
      }
      await _saveProfiles(prefs);
    }
  }

  Future<bool> deleteProfile(String profileId) async {
    if (_profiles.length <= 1) return false;
    final prefs = await SharedPreferences.getInstance();
    _profiles.removeWhere((p) => p.id == profileId);

    // Clean up scoped keys for the deleted profile
    final prefix = 'prof_${profileId}_';
    final allKeys = prefs.getKeys().toList();
    for (final k in allKeys) {
      if (k.startsWith(prefix)) {
        await prefs.remove(k);
      }
    }

    if (_activeProfile?.id == profileId) {
      _activeProfile = _profiles.first;
      activeProfileNotifier.value = _activeProfile;
      await prefs.setString(_prefActiveProfileIdKey, _activeProfile!.id);
    }

    await _saveProfiles(prefs);
    return true;
  }

  Future<void> cancelProfileCreation(String draftProfileId, {String? restoreProfileId}) async {
    final prefs = await SharedPreferences.getInstance();
    _profiles.removeWhere((p) => p.id == draftProfileId);

    // Clean up scoped keys for the cancelled draft profile
    final prefix = 'prof_${draftProfileId}_';
    final allKeys = prefs.getKeys().toList();
    for (final k in allKeys) {
      if (k.startsWith(prefix)) {
        await prefs.remove(k);
      }
    }

    if (restoreProfileId != null && _profiles.any((p) => p.id == restoreProfileId)) {
      _activeProfile = _profiles.firstWhere((p) => p.id == restoreProfileId);
    } else if (_profiles.isNotEmpty) {
      _activeProfile = _profiles.first;
    } else {
      _activeProfile = null;
    }
    activeProfileNotifier.value = _activeProfile;
    if (_activeProfile != null) {
      await prefs.setString(_prefActiveProfileIdKey, _activeProfile!.id);
    } else {
      await prefs.remove(_prefActiveProfileIdKey);
    }

    await _saveProfiles(prefs);
  }

  Future<void> setActiveProfile(String profileId) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId, orElse: () => _profiles.first);
    _activeProfile = profile;
    activeProfileNotifier.value = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActiveProfileIdKey, profile.id);
  }
}
