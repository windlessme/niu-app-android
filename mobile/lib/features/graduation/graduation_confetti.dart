import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Confetti that keeps falling over the page once every graduation
/// requirement is met. It never takes taps, is hidden from screen readers
/// and stays off when the system asks for less motion.
class GraduationConfetti extends StatefulWidget {
  const GraduationConfetti({super.key});

  @override
  State<GraduationConfetti> createState() => _GraduationConfettiState();
}

class _GraduationConfettiState extends State<GraduationConfetti>
    with SingleTickerProviderStateMixin {
  /// Same pieces on every build: each one's place depends only on time.
  static final pieces = () {
    final random = Random(0x4E4955);
    return List.generate(70, (_) => _Piece(random));
  }();

  late final Ticker ticker;
  final elapsed = ValueNotifier(Duration.zero);

  @override
  void initState() {
    super.initState();
    // A ticker stops by itself while the route is covered or the app is in
    // the background.
    ticker = createTicker((time) => elapsed.value = time)..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(elapsed),
          ),
        ),
      ),
    );
  }
}

class _Piece {
  _Piece(Random random)
    : x = random.nextDouble(),
      fall = 70 + random.nextDouble() * 80,
      offset = random.nextDouble(),
      sway = 8 + random.nextDouble() * 20,
      swaySpeed = .8 + random.nextDouble() * 1.2,
      spin = -3 + random.nextDouble() * 6,
      flip = 2 + random.nextDouble() * 4,
      circle = random.nextDouble() < .2,
      color = palette[random.nextInt(palette.length)] {
    width = circle ? 7 : 6 + random.nextDouble() * 3;
    height = circle ? 7 : 10 + random.nextDouble() * 6;
  }

  static const palette = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00C7BE),
    Color(0xFF007AFF),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
  ];

  /// Fraction across the page, fall speed (px/s) and where in the fall it
  /// starts, so pieces don't arrive together.
  final double x, fall, offset;
  final double sway, swaySpeed, spin, flip;
  final bool circle;
  final Color color;
  late final double width, height;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.elapsed) : super(repaint: elapsed);
  final ValueNotifier<Duration> elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 24.0;
    final t = elapsed.value.inMicroseconds / 1e6;
    final travel = size.height + margin * 2;
    final paint = Paint();
    for (final piece in _GraduationConfettiState.pieces) {
      final y = (t * piece.fall + piece.offset * travel) % travel - margin;
      final x =
          piece.x * size.width +
          sin(t * piece.swaySpeed + piece.offset * 2 * pi) * piece.sway;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(t * piece.spin + piece.offset * 2 * pi)
        // Narrowing the piece looks like it flipping over.
        ..scale(max(.15, cos(t * piece.flip + piece.offset * 4).abs()), 1);
      paint.color = piece.color.withValues(alpha: .9);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: piece.width,
        height: piece.height,
      );
      if (piece.circle) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.elapsed != elapsed;
}
