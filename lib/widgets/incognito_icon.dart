import 'package:flutter/material.dart';

/// Classic Incognito Fedora Hat & Glasses Icon
class IncognitoIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const IncognitoIcon({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return CustomPaint(
      size: Size(size, size * 0.75),
      painter: _IncognitoPainter(color: c),
    );
  }
}

class _IncognitoPainter extends CustomPainter {
  final Color color;
  _IncognitoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // 1. Hat Crown (fedora with indented top)
    final hatPath = Path();
    hatPath.moveTo(w * 0.28, h * 0.36);
    hatPath.lineTo(w * 0.33, h * 0.08);
    hatPath.quadraticBezierTo(w * 0.5, h * 0.16, w * 0.67, h * 0.08);
    hatPath.lineTo(w * 0.72, h * 0.36);
    hatPath.close();
    canvas.drawPath(hatPath, fillPaint);

    // 2. Hat Brim
    final brimRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.38), width: w * 0.88, height: h * 0.13),
      Radius.circular(h * 0.065),
    );
    canvas.drawRRect(brimRect, fillPaint);

    // 3. Glasses (two lenses joined by bridge)
    final lensRadius = w * 0.13;
    final leftCenter = Offset(w * 0.33, h * 0.72);
    final rightCenter = Offset(w * 0.67, h * 0.72);

    canvas.drawCircle(leftCenter, lensRadius, strokePaint);
    canvas.drawCircle(rightCenter, lensRadius, strokePaint);

    final bridgePath = Path();
    bridgePath.moveTo(w * 0.44, h * 0.70);
    bridgePath.quadraticBezierTo(w * 0.5, h * 0.64, w * 0.56, h * 0.70);
    canvas.drawPath(bridgePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _IncognitoPainter oldDelegate) => oldDelegate.color != color;
}
