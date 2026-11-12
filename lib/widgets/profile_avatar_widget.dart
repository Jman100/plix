import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plix_profile.dart';

class ProfileAvatarWidget extends StatelessWidget {
  final String avatarId;
  final String? avatarColorId;
  final double size;
  final bool isSelected;
  final bool isFocused;
  final bool glow;
  final bool isCircular;
  final double? borderRadius;
  final VoidCallback? onTap;

  const ProfileAvatarWidget({
    super.key,
    required this.avatarId,
    this.avatarColorId,
    this.size = 40,
    this.isSelected = false,
    this.isFocused = false,
    this.glow = false,
    this.isCircular = true,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = PlixProfile.getAssetPath(avatarId);
    final effectiveRadius = borderRadius ?? (isCircular ? size / 2 : 12.0);
    final gradientOption = ProfileGradientOption.getGradientOption(avatarColorId);

    List<BoxShadow> shadows = [];
    if (isFocused) {
      shadows.add(
        BoxShadow(
          color: PlixTheme.plexGold.withOpacity(0.65),
          blurRadius: 18,
          spreadRadius: 2.5,
        ),
      );
    } else if (glow) {
      shadows.add(
        BoxShadow(
          color: PlixTheme.plexGold.withOpacity(0.35),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      );
    }

    final Widget innerIcon = Center(
      child: Image.asset(
        assetPath,
        width: size * 0.82,
        height: size * 0.82,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.person_rounded,
            size: size * 0.65,
            color: Colors.white,
          );
        },
      ),
    );

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircular ? null : BorderRadius.circular(effectiveRadius),
        gradient: gradientOption.gradient,
        boxShadow: shadows,
        border: Border.all(
          color: isFocused
              ? PlixTheme.plexGold
              : isSelected
                  ? PlixTheme.plexGold.withOpacity(0.9)
                  : Colors.white.withOpacity(0.20),
          width: isFocused ? 2.5 : (isSelected ? 2.0 : 1.2),
        ),
      ),
      child: isCircular
          ? ClipOval(child: innerIcon)
          : ClipRRect(borderRadius: BorderRadius.circular(effectiveRadius), child: innerIcon),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: isCircular ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(effectiveRadius)),
          child: content,
        ),
      );
    }

    return content;
  }
}
