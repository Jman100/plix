import 'dart:io';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/plix_profile.dart';
import '../services/custom_avatar_service.dart';

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
          color: PlixTheme.plexGold.withOpacity(0.85),
          blurRadius: 28,
          spreadRadius: 4.5,
        ),
      );
      shadows.add(
        BoxShadow(
          color: PlixTheme.plexGold.withOpacity(0.40),
          blurRadius: 48,
          spreadRadius: 8.0,
        ),
      );
    } else if (glow) {
      shadows.add(
        BoxShadow(
          color: PlixTheme.plexGold.withOpacity(0.50),
          blurRadius: 16,
          spreadRadius: 2.0,
        ),
      );
    }

    final bool isCustom = CustomAvatarService.isCustomAvatar(avatarId);
    final File? customFile = isCustom ? CustomAvatarService.getCustomAvatarFileSync(avatarId) : null;

    Widget innerIcon;
    if (isCustom) {
      if (customFile != null && customFile.existsSync()) {
        innerIcon = Image.file(
          customFile,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.person_rounded,
              size: size * 0.65,
              color: Colors.white,
            );
          },
        );
      } else {
        innerIcon = FutureBuilder<File?>(
          future: CustomAvatarService.getCustomAvatarFile(avatarId),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null && snapshot.data!.existsSync()) {
              return Image.file(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person_rounded,
                    size: size * 0.65,
                    color: Colors.white,
                  );
                },
              );
            }
            return Icon(
              Icons.person_rounded,
              size: size * 0.65,
              color: Colors.white,
            );
          },
        );
      }
    } else {
      innerIcon = Image.asset(
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
      );
    }

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
          ? ClipOval(child: Center(child: innerIcon))
          : ClipRRect(borderRadius: BorderRadius.circular(effectiveRadius), child: Center(child: innerIcon)),
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
