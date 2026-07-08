import 'package:flutter/material.dart';

/// Servexa brand mark: a bold white "S" on an indigo→violet gradient
/// squircle, with an amber spark on the S's start terminal. Pure vector
/// (CustomPainter) — crisp at any size, no image assets.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ServexaSPainter(),
    );
  }
}

class _ServexaSPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // Badge: rounded square with the Servexa indigo→violet gradient.
    final badge = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.24)),
      badge,
    );

    // Soft top-edge highlight for a touch of depth (still flat overall).
    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h * 0.5), Radius.circular(w * 0.24)),
      highlight,
    );

    // The "S": one continuous spine, two symmetric hooks, round caps.
    final s = Path()
      ..moveTo(w * 0.665, h * 0.285)
      // top hook: sweeps left and curls under
      ..cubicTo(w * 0.585, h * 0.165, w * 0.315, h * 0.185, w * 0.330, h * 0.345)
      // middle diagonal of the S
      ..cubicTo(w * 0.345, h * 0.500, w * 0.655, h * 0.500, w * 0.670, h * 0.655)
      // bottom hook: sweeps left and curls out
      ..cubicTo(w * 0.685, h * 0.815, w * 0.415, h * 0.835, w * 0.335, h * 0.715);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.135
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(s, stroke);

    // Amber spark on the S's start terminal — the brand accent.
    canvas.drawCircle(
      Offset(w * 0.665, h * 0.285),
      w * 0.045,
      Paint()..color = const Color(0xFFF59E0B),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
