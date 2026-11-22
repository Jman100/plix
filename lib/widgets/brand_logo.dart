import 'dart:math' as math;
import 'dart:ui' as ui;
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


/// Aerodynamic swooshy play icon painter incorporating a lowercase 'p' in orange and white.
class _SwooshyPlayPainter extends CustomPainter {
  final Color? accentColor;

  const _SwooshyPlayPainter({this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 100.0;
    final scaleY = size.height / 100.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final orangeGrad = ui.Gradient.linear(
      const Offset(10, 10),
      const Offset(90, 90),
      [
        const Color(0xFFFFB300),
        accentColor ?? const Color(0xFFFF9100),
        const Color(0xFFFF3D00),
      ],
      [0.0, 0.45, 1.0],
    );

    final orangePaint = Paint()
      ..shader = orangeGrad
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
      ..style = PaintingStyle.fill;

    // Path 1: Lowercase 'p' descender stem and top shoulder arch in dynamic orange swoosh
    final p1 = Path();
    p1.moveTo(21, 91);
    p1.cubicTo(14, 91, 11, 84, 13, 76);
    p1.cubicTo(15, 64, 21, 46, 22, 33);
    p1.cubicTo(23, 21, 31, 12.5, 45, 11.5);
    p1.cubicTo(59, 10.5, 71, 16.5, 78, 24.5);
    p1.cubicTo(63, 24, 50, 28.5, 41, 36.5);
    p1.lineTo(41, 79);
    p1.cubicTo(41, 86, 32, 91, 21, 91);
    p1.close();

    // Path 2: Aerodynamic white play arrow forming the bowl of the lowercase 'p'
    final p2 = Path();
    p2.moveTo(33, 19);
    p2.cubicTo(39, 16, 47, 17.5, 53, 21);
    p2.lineTo(91, 45.5);
    p2.cubicTo(95, 48, 95, 53, 91, 55.5);
    p2.lineTo(53, 80);
    p2.cubicTo(47, 83.5, 39, 85, 33, 82);
    p2.cubicTo(29, 80, 27.5, 76, 27.5, 71.5);
    p2.lineTo(27.5, 29.5);
    p2.cubicTo(27.5, 25, 29, 21, 33, 19);
    p2.close();

    // Path 3: Inner speed swoosh accent inside play triangle bowl
    final p3 = Path();
    p3.moveTo(40, 31);
    p3.cubicTo(49, 38, 60, 46, 72, 50.5);
    p3.cubicTo(60, 55, 49, 63, 40, 70);
    p3.cubicTo(45, 61, 47.5, 55, 47.5, 50.5);
    p3.cubicTo(47.5, 46, 45, 40, 40, 31);
    p3.close();

    // Draw drop shadows
    canvas.save();
    canvas.translate(0, 2.5);
    canvas.drawPath(p1, shadowPaint);
    canvas.drawPath(p2, shadowPaint);
    canvas.restore();

    // Draw main elements
    canvas.drawPath(p1, orangePaint);
    canvas.drawPath(p2, whitePaint);
    canvas.drawPath(p3, orangePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SwooshyPlayPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

/// Branded Plix App Logo featuring a rich deep-violet rounded squircle
/// with an aerodynamic swooshy play symbol in orange and white.
class PlixAppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark; // Retained for compatibility
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
    final effectiveAccent = accentColor ?? const Color(0xFFFF9100);
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
                Color(0xFF4C1885), // Vibrant royal purple top-left highlight
                Color(0xFF280A4E), // Deep purple core
                Color(0xFF120324), // Midnight base
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
          color: Colors.white.withOpacity(0.18),
          width: math.max(1.0, size * 0.02),
        ),
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.88, size * 0.88),
          painter: _SwooshyPlayPainter(accentColor: effectiveAccent),
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
