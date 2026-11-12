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
      colors: [Color(0xFFFFB300), Color(0xFFE5A00D), Color(0xFFFF5722)],
    ),
    ProfileGradientOption(
      id: 'gradient_purple',
      label: 'Cosmic Nebula',
      colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
    ),
    ProfileGradientOption(
      id: 'gradient_sunset',
      label: 'Sunset Horizon',
      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B), Color(0xFFFFA07A)],
    ),
    ProfileGradientOption(
      id: 'gradient_ocean',
      label: 'Electric Ocean',
      colors: [Color(0xFF00C6FF), Color(0xFF0072FF), Color(0xFF1E3C72)],
    ),
    ProfileGradientOption(
      id: 'gradient_emerald',
      label: 'Emerald Aurora',
      colors: [Color(0xFF00F5A0), Color(0xFF00D9F5), Color(0xFF0F5132)],
    ),
    ProfileGradientOption(
      id: 'gradient_neon',
      label: 'Cyberpunk Magenta',
      colors: [Color(0xFFFF007F), Color(0xFF7928CA), Color(0xFF4361EE)],
    ),
    ProfileGradientOption(
      id: 'gradient_cyan',
      label: 'Tropical Lagoon',
      colors: [Color(0xFF4E65FF), Color(0xFF92EFFD), Color(0xFF00C9FF)],
    ),
    ProfileGradientOption(
      id: 'gradient_midnight',
      label: 'Royal Orchid',
      colors: [Color(0xFFB5179E), Color(0xFF7209B7), Color(0xFF3F37C9)],
    ),
    ProfileGradientOption(
      id: 'gradient_dark',
      label: 'Stealth Titanium',
      colors: [Color(0xFF606C88), Color(0xFF3F4C6B), Color(0xFF1F1C2C)],
    ),
    ProfileGradientOption(
      id: 'gradient_ruby',
      label: 'Crimson Ember',
      colors: [Color(0xFFFF0844), Color(0xFFFFB199), Color(0xFF800020)],
    ),
    ProfileGradientOption(
      id: 'gradient_forest',
      label: 'Solar Meadow',
      colors: [Color(0xFFFFE000), Color(0xFF799F0C), Color(0xFF00796B)],
    ),
    ProfileGradientOption(
      id: 'gradient_blaze',
      label: 'Vaporwave Sunset',
      colors: [Color(0xFFFA709A), Color(0xFFFEE140), Color(0xFF48CAE4)],
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
