import 'dart:math' as math;
import '../app_theme.dart';
import 'package:flutter/material.dart';

class PlexLogo extends StatelessWidget {
  final double size;
  final Color color;

  const PlexLogo({
    super.key,
    this.size = 24.0,
    this.color = const Color(0xFFE5A00D),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PlexLogoPainter(color: color),
    );
  }
}

class _PlexLogoPainter extends CustomPainter {
  final Color color;

  _PlexLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // Official Plex chevron arrow path (24x24 viewBox)
    final path = Path();
    path.moveTo(11.643, 0);
    path.lineTo(4.68, 0);
    path.lineTo(12.359, 12);
    path.lineTo(4.68, 24);
    path.lineTo(11.643, 24);
    path.lineTo(19.322, 12);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlexLogoPainter oldDelegate) => oldDelegate.color != color;
}

class JellyfinLogo extends StatelessWidget {
  final double size;
  final Color color;

  const JellyfinLogo({
    super.key,
    this.size = 24.0,
    this.color = const Color(0xFF8E51DC),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _JellyfinLogoPainter(color: color),
    );
  }
}

class _JellyfinLogoPainter extends CustomPainter {
  final Color color;

  _JellyfinLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // Official Jellyfin logo path with even-odd fill (24x24 viewBox)
    final path = Path()..fillType = PathFillType.evenOdd;

    // Outer contour
    path.moveTo(12.0, 0.002);
    path.cubicTo(8.826, 0.002, -1.398, 18.537, 0.16, 21.666);
    path.cubicTo(1.72, 24.795, 22.3, 24.76, 23.842, 21.666);
    path.cubicTo(25.384, 18.572, 15.177, 0.0, 12.0, 0.0);
    path.close();

    // Middle cutout ring
    path.moveTo(19.76, 18.949);
    path.cubicTo(18.752, 20.977, 5.267, 20.999, 4.246, 18.949);
    path.cubicTo(3.224, 16.9, 9.92, 4.755, 12.003, 4.755);
    path.cubicTo(14.084, 4.755, 20.773, 16.921, 19.76, 18.949);
    path.close();

    // Inner droplet
    path.moveTo(12.0, 9.198);
    path.cubicTo(10.946, 9.198, 7.554, 15.348, 8.07, 16.387);
    path.cubicTo(8.588, 17.427, 15.418, 17.414, 15.93, 16.387);
    path.cubicTo(16.441, 15.36, 13.056, 9.198, 12.0, 9.198);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JellyfinLogoPainter oldDelegate) => oldDelegate.color != color;
}


/// Branded Plix App Logo matching the official app icon styling.
/// Displays a rich deep-violet rounded squircle with stylized 'pli' in white and 'x' in accent color.
class PlixAppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark; // true = "plix", false = "px"
  final double? borderRadius;
  final bool glow;
  final Color? accentColor;
  final Gradient? customGradient;

  const PlixAppLogo({
    super.key,
    this.size = 38.0,
    this.showWordmark = false,
    this.borderRadius,
    this.glow = false,
    this.accentColor,
    this.customGradient,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? PlixTheme.plexGold;
    final radius = borderRadius ?? (size * 0.24);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: customGradient ??
            const RadialGradient(
              center: Alignment(-0.25, -0.35),
              radius: 1.15,
              colors: [
                Color(0xFF3B156E), // Vibrant royal purple top-left highlight
                Color(0xFF260A4B), // Deep purple core
                Color(0xFF130326), // Midnight base
              ],
              stops: [0.0, 0.55, 1.0],
            ),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: effectiveAccent.withOpacity(0.35),
              blurRadius: size * 0.35,
              spreadRadius: 2,
            ),
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.08),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
          width: math.max(1.0, size * 0.02),
        ),
      ),
      child: Center(
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: showWordmark ? 'pli' : 'p',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: showWordmark ? (size * 0.34) : (size * 0.44),
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Roboto',
                  letterSpacing: showWordmark ? -0.5 : -0.2,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.65),
                      offset: Offset(0, size * 0.03),
                      blurRadius: size * 0.06,
                    ),
                  ],
                ),
              ),
              TextSpan(
                text: 'x',
                style: TextStyle(
                  color: effectiveAccent,
                  fontSize: showWordmark ? (size * 0.34) : (size * 0.44),
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Roboto',
                  letterSpacing: showWordmark ? -0.5 : -0.2,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.65),
                      offset: Offset(0, size * 0.03),
                      blurRadius: size * 0.06,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standalone styled 'plix' wordmark
class PlixWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;
  final Color? accentColor;
  final bool hasShadow;

  const PlixWordmark({
    super.key,
    this.fontSize = 22.0,
    this.letterSpacing = 0.5,
    this.accentColor,
    this.hasShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? PlixTheme.plexGold;
    final shadowList = hasShadow
        ? [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(0, 1.5),
              blurRadius: 4.0,
            ),
          ]
        : null;

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'pli',
            style: TextStyle(
              color: PlixTheme.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontFamily: 'Roboto',
              letterSpacing: letterSpacing,
              shadows: shadowList,
            ),
          ),
          TextSpan(
            text: 'x',
            style: TextStyle(
              color: effectiveAccent,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontFamily: 'Roboto',
              letterSpacing: letterSpacing,
              shadows: shadowList,
            ),
          ),
        ],
      ),
    );
  }
}
