import 'package:flutter/material.dart';

class AvatarOption {
  final String id;
  final String label;
  final String assetPath;

  const AvatarOption({
    required this.id,
    required this.label,
    required this.assetPath,
  });
}

class ProfileGradientOption {
  final String id;
  final String label;
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const ProfileGradientOption({
    required this.id,
    required this.label,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  LinearGradient get gradient => LinearGradient(colors: colors, begin: begin, end: end);

  static const List<ProfileGradientOption> availableGradients = [
    ProfileGradientOption(
      id: 'gradient_gold',
      label: 'Plix Gold',
      colors: [Color(0xFFF5A623), Color(0xFFD48806)],
    ),
    ProfileGradientOption(
      id: 'gradient_purple',
      label: 'Cosmic Purple',
      colors: [Color(0xFF8E51DC), Color(0xFF5B259F)],
    ),
    ProfileGradientOption(
      id: 'gradient_sunset',
      label: 'Sunset Crimson',
      colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
    ),
    ProfileGradientOption(
      id: 'gradient_ocean',
      label: 'Ocean Blue',
      colors: [Color(0xFF0072FF), Color(0xFF00C6FF)],
    ),
    ProfileGradientOption(
      id: 'gradient_emerald',
      label: 'Emerald Green',
      colors: [Color(0xFF00B09B), Color(0xFF96C93D)],
    ),
    ProfileGradientOption(
      id: 'gradient_neon',
      label: 'Neon Magenta',
      colors: [Color(0xFFFF007F), Color(0xFF7928CA)],
    ),
    ProfileGradientOption(
      id: 'gradient_cyan',
      label: 'Electric Cyan',
      colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
    ),
    ProfileGradientOption(
      id: 'gradient_midnight',
      label: 'Midnight Indigo',
      colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
    ),
    ProfileGradientOption(
      id: 'gradient_dark',
      label: 'Stealth Slate',
      colors: [Color(0xFF2C3E50), Color(0xFF1A1A1D)],
    ),
    ProfileGradientOption(
      id: 'gradient_ruby',
      label: 'Royal Ruby',
      colors: [Color(0xFFE52D27), Color(0xFFB31217)],
    ),
    ProfileGradientOption(
      id: 'gradient_forest',
      label: 'Deep Forest',
      colors: [Color(0xFF134E5E), Color(0xFF71B280)],
    ),
    ProfileGradientOption(
      id: 'gradient_blaze',
      label: 'Tangerine Blaze',
      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
    ),
  ];

  static ProfileGradientOption getGradientOption(String? id) {
    return availableGradients.firstWhere(
      (g) => g.id == id,
      orElse: () => availableGradients.first,
    );
  }
}

class PlixProfile {
  final String id;
  final String name;
  final String avatarId;
  final String avatarColorId;
  final String? pin;
  final int createdAt;

  const PlixProfile({
    required this.id,
    required this.name,
    required this.avatarId,
    this.avatarColorId = 'gradient_gold',
    this.pin,
    required this.createdAt,
  });

  bool get hasPin => pin != null && pin!.trim().length == 4;

  PlixProfile copyWith({
    String? id,
    String? name,
    String? avatarId,
    String? avatarColorId,
    String? pin,
    int? createdAt,
    bool clearPin = false,
  }) {
    return PlixProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarId: avatarId ?? this.avatarId,
      avatarColorId: avatarColorId ?? this.avatarColorId,
      pin: clearPin ? null : (pin ?? this.pin),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarId': avatarId,
      'avatarColorId': avatarColorId,
      if (pin != null && pin!.isNotEmpty) 'pin': pin,
      'createdAt': createdAt,
    };
  }

  factory PlixProfile.fromJson(Map<String, dynamic> json) {
    return PlixProfile(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? 'Default',
      avatarId: json['avatarId'] as String? ?? 'avatar_default',
      avatarColorId: json['avatarColorId'] as String? ?? 'gradient_gold',
      pin: json['pin'] as String?,
      createdAt: json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static const List<AvatarOption> availableAvatars = [
    AvatarOption(id: 'avatar_default', label: 'Default', assetPath: 'assets/avatars/avatar_default.png'),
    AvatarOption(id: 'avatar_windows', label: 'Windows', assetPath: 'assets/avatars/avatar_windows.png'),
    AvatarOption(id: 'avatar_android', label: 'Android', assetPath: 'assets/avatars/avatar_android.png'),
    AvatarOption(id: 'avatar_linux', label: 'Linux', assetPath: 'assets/avatars/avatar_linux.png'),
    AvatarOption(id: 'avatar_cinema', label: 'Cinema', assetPath: 'assets/avatars/avatar_cinema.png'),
    AvatarOption(id: 'avatar_popcorn', label: 'Popcorn', assetPath: 'assets/avatars/avatar_popcorn.png'),
    AvatarOption(id: 'avatar_tv', label: 'Retro TV', assetPath: 'assets/avatars/avatar_tv.png'),
    AvatarOption(id: 'avatar_gamepad', label: 'Gamer', assetPath: 'assets/avatars/avatar_gamepad.png'),
    AvatarOption(id: 'avatar_headphones', label: 'Audiophile', assetPath: 'assets/avatars/avatar_headphones.png'),
    AvatarOption(id: 'avatar_rocket', label: 'Rocket', assetPath: 'assets/avatars/avatar_rocket.png'),
    AvatarOption(id: 'avatar_star', label: 'Star', assetPath: 'assets/avatars/avatar_star.png'),
    AvatarOption(id: 'avatar_crown', label: 'Royal', assetPath: 'assets/avatars/avatar_crown.png'),
    AvatarOption(id: 'avatar_robot', label: 'Robot', assetPath: 'assets/avatars/avatar_robot.png'),
    AvatarOption(id: 'avatar_camera', label: 'Director', assetPath: 'assets/avatars/avatar_camera.png'),
    AvatarOption(id: 'avatar_alien', label: 'Alien', assetPath: 'assets/avatars/avatar_alien.png'),
    AvatarOption(id: 'avatar_cat', label: 'Cool Cat', assetPath: 'assets/avatars/avatar_cat.png'),
    AvatarOption(id: 'avatar_dog', label: 'Puppy', assetPath: 'assets/avatars/avatar_dog.png'),
    AvatarOption(id: 'avatar_flame', label: 'Flame', assetPath: 'assets/avatars/avatar_flame.png'),
    AvatarOption(id: 'avatar_sparkles', label: 'Cosmic', assetPath: 'assets/avatars/avatar_sparkles.png'),
    AvatarOption(id: 'avatar_globe', label: 'Explorer', assetPath: 'assets/avatars/avatar_globe.png'),
    AvatarOption(id: 'avatar_diamond', label: 'Diamond', assetPath: 'assets/avatars/avatar_diamond.png'),
  ];

  static String getAssetPath(String avatarId) {
    final match = availableAvatars.firstWhere(
      (a) => a.id == avatarId,
      orElse: () => availableAvatars.first,
    );
    return match.assetPath;
  }
}
