import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'campus_map_data.dart';

/// Maps a building's metres onto a canvas. Wide buildings on tall canvases
/// turn 90° clockwise, so the west end sits on top; every floor of one
/// building shares the same framing.
class FloorFrame {
  FloorFrame(
    this.building,
    this.size, {
    this.padding = const EdgeInsets.all(16),
  }) {
    final b = building.bounds;
    final room = padding.deflateSize(size);
    rotated = b.width > b.height && room.height > room.width;
    final w = rotated ? b.height : b.width;
    final h = rotated ? b.width : b.height;
    scale = math.max(math.min(room.width / w, room.height / h), .01);
  }

  final MapBuilding building;
  final Size size;

  /// Room kept clear for controls floating over the plan.
  final EdgeInsets padding;
  late final bool rotated;
  late final double scale;

  Matrix4 get matrix {
    final c = building.bounds.center;
    final area = padding.deflateRect(Offset.zero & size).center;
    final m = Matrix4.identity()
      ..translateByDouble(area.dx, area.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    if (rotated) m.rotateZ(math.pi / 2);
    return m..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  Offset toCanvas(Offset metres) => MatrixUtils.transformPoint(matrix, metres);

  Offset toMetres(Offset canvas) =>
      MatrixUtils.transformPoint(Matrix4.inverted(matrix), canvas);
}

class FloorMapPainter extends CustomPainter {
  FloorMapPainter({
    required this.building,
    required this.floor,
    required this.colors,
    required this.hues,
    required this.textStyle,
    this.padding = const EdgeInsets.all(16),
    this.selected,
  });

  final MapBuilding building;
  final MapFloor floor;
  final NiuColors colors;
  final ({Color restroom, Color restroomEdge, Color terrace}) hues;
  final TextStyle textStyle;
  final EdgeInsets padding;
  final MapSpace? selected;

  static const _gap = .18, _radius = .45;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = FloorFrame(building, size, padding: padding);
    canvas.save();
    canvas.transform(frame.matrix.storage);
    final px = 1 / frame.scale; // one logical pixel, in metres

    final outline = Path()..addPolygon(floor.outline, true);
    canvas.drawShadow(outline, colors.shadow, 4 * px, false);
    canvas.drawPath(outline, Paint()..color = colors.surface);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = colors.hairline,
    );

    const order = [
      MapSpaceKind.terrace,
      MapSpaceKind.corridor,
      MapSpaceKind.shaft,
      MapSpaceKind.room,
      MapSpaceKind.restroom,
      MapSpaceKind.stairs,
      MapSpaceKind.elevator,
    ];
    for (final kind in order) {
      for (final s in floor.spaces) {
        if (s.kind == kind) _space(canvas, s, px);
      }
    }
    canvas.restore();

    for (final s in floor.rooms) {
      final label = s.code;
      if (label == null) continue;
      final box = s.bounds;
      final width = (frame.rotated ? box.height : box.width) * frame.scale;
      final on = identical(s, selected);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: textStyle.copyWith(
            color: on ? colors.onAccent : colors.ink,
            fontWeight: on ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > width - 4) continue;
      painter.paint(
        canvas,
        frame.toCanvas(box.center) -
            Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  void _space(Canvas canvas, MapSpace s, double px) {
    final on = identical(s, selected);
    final (fill, edge) = switch (s.kind) {
      MapSpaceKind.terrace => (hues.terrace, null),
      MapSpaceKind.corridor => (colors.surface, null),
      MapSpaceKind.shaft => (colors.canvas, colors.fillStrong),
      MapSpaceKind.room =>
        on
            ? (colors.accent, colors.accent)
            : (colors.accentSoft, colors.accent.withValues(alpha: .3)),
      MapSpaceKind.restroom => (hues.restroom, hues.restroomEdge),
      MapSpaceKind.stairs || MapSpaceKind.elevator => (
        colors.fillStrong,
        colors.inkTertiary.withValues(alpha: .35),
      ),
    };
    final flat =
        s.kind == MapSpaceKind.corridor || s.kind == MapSpaceKind.terrace;
    final width = (on ? 2 : 1) * px;
    if (flat || !s.isRect) {
      // Polygons share walls; clipped strokes inset them like the tiles.
      canvas.save();
      canvas.clipPath(s.path);
      canvas.drawPath(s.path, Paint()..color = fill);
      if (!flat) {
        canvas.drawPath(
          s.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (_gap + width) * 2
            ..color = edge ?? fill,
        );
        canvas.drawPath(
          s.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _gap * 2
            ..color = colors.surface,
        );
      }
      canvas.restore();
    } else {
      final tile = RRect.fromRectAndRadius(
        s.bounds.deflate(_gap),
        const Radius.circular(_radius),
      );
      canvas.drawRRect(tile, Paint()..color = fill);
      if (edge != null) {
        canvas.drawRRect(
          tile,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = edge,
        );
      }
    }
    final b = s.bounds;
    final line = Paint()
      ..color = colors.inkTertiary.withValues(alpha: .35)
      ..strokeWidth = px;
    switch (s.kind) {
      case MapSpaceKind.stairs:
        final across = b.width >= b.height;
        final from = (across ? b.left : b.top) + .8;
        final to = (across ? b.right : b.bottom) - .8;
        for (var t = from; t < to; t += .45) {
          canvas.drawLine(
            across ? Offset(t, b.top + .5) : Offset(b.left + .5, t),
            across ? Offset(t, b.bottom - .5) : Offset(b.right - .5, t),
            line,
          );
        }
      case MapSpaceKind.elevator || MapSpaceKind.shaft:
        final m = s.kind == MapSpaceKind.elevator ? .4 : .8;
        final r = b.deflate(m);
        canvas.drawLine(r.topLeft, r.bottomRight, line);
        canvas.drawLine(r.topRight, r.bottomLeft, line);
      default:
    }
  }

  @override
  bool shouldRepaint(FloorMapPainter old) =>
      old.floor != floor ||
      old.selected != selected ||
      old.padding != padding ||
      old.colors != colors ||
      old.textStyle != textStyle;
}
