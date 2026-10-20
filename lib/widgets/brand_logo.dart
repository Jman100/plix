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
