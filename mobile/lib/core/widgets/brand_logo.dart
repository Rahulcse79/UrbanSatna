import 'package:flutter/material.dart';

/// Vector brand mark: a flowing three-band "S" ribbon (orange → violet →
/// green) matching the Servexa identity — crisp at any size, no assets.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RibbonSPainter(),
    );
  }
}

class _RibbonSPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.22;

    Paint band(List<Color> colors, Offset from, Offset to) => Paint()
      ..shader = LinearGradient(colors: colors)
          .createShader(Rect.fromPoints(from, to))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Top curl: orange → amber
    final top = Path()
      ..moveTo(w * 0.78, h * 0.22)
      ..quadraticBezierTo(w * 0.50, h * 0.02, w * 0.30, h * 0.24);
    canvas.drawPath(
        top,
        band(const [Color(0xFFF59E0B), Color(0xFFF97316)],
            Offset(w * 0.78, h * 0.22), Offset(w * 0.30, h * 0.24)));

    // Middle sweep: indigo → violet (the spine of the S)
    final mid = Path()
      ..moveTo(w * 0.30, h * 0.24)
      ..cubicTo(w * 0.05, h * 0.52, w * 0.95, h * 0.48, w * 0.70, h * 0.76);
    canvas.drawPath(
        mid,
        band(const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            Offset(w * 0.30, h * 0.24), Offset(w * 0.70, h * 0.76)));

    // Bottom curl: green → teal
    final bottom = Path()
      ..moveTo(w * 0.70, h * 0.76)
      ..quadraticBezierTo(w * 0.50, h * 0.98, w * 0.22, h * 0.78);
    canvas.drawPath(
        bottom,
        band(const [Color(0xFF10B981), Color(0xFF14B8A6)],
            Offset(w * 0.70, h * 0.76), Offset(w * 0.22, h * 0.78)));

    // Sparkle accent
    final sparkle = Paint()..color = const Color(0xFFF59E0B);
    canvas.drawCircle(Offset(w * 0.88, h * 0.10), w * 0.035, sparkle);
    canvas.drawCircle(
        Offset(w * 0.95, h * 0.20), w * 0.02, sparkle..color = const Color(0xFF7C3AED));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
