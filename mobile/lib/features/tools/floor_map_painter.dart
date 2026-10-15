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
    this.zoom,
  }) : super(repaint: zoom);

  final MapBuilding building;
  final MapFloor floor;
  final NiuColors colors;
  final ({
    Color restroom,
    Color restroomEdge,
    Color terrace,
    Color link,
    Color linkFill,
  })
  hues;
  final TextStyle textStyle;
  final EdgeInsets padding;
  final MapSpace? selected;

  /// The viewer's zoom; labels keep their screen size and appear in rooms
  /// that grow big enough for them.
  final TransformationController? zoom;

  static const _gap = .18, _radius = .45;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = FloorFrame(building, size, padding: padding);
    canvas.save();
    canvas.transform(frame.matrix.storage);
    final px = 1 / frame.scale; // one logical pixel, in metres

    final outline = Path();
    for (final ring in floor.outlines) {
      outline.addPolygon(ring, true);
    }
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
    for (final line in floor.closed) {
      _closed(canvas, line, px);
    }
    canvas.restore();

    final z = zoom?.value.getMaxScaleOnAxis() ?? 1;
    final base = (textStyle.fontSize ?? 11) / z;
    for (final link in floor.links) {
      _link(canvas, frame, link, z);
    }
    for (final s in floor.spaces) {
      if (s.kind != MapSpaceKind.room && s.kind != MapSpaceKind.restroom) {
        continue;
      }
      final label = s.label;
      if (label == null) continue;
      final box = s.bounds;
      final width = (frame.rotated ? box.height : box.width) * frame.scale;
      final height = (frame.rotated ? box.width : box.height) * frame.scale;
      final on = identical(s, selected);
      TextPainter layout(String text, double size, {int lines = 1}) =>
          TextPainter(
            text: TextSpan(
              text: text,
              style: textStyle.copyWith(
                fontSize: size,
                color: on
                    ? colors.onAccent
                    : s.isRoom
                    ? colors.ink
                    : colors.inkSecondary,
                fontWeight: on || s.code != null
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            maxLines: lines,
          )..layout(maxWidth: lines == 1 ? double.infinity : width - 4 / z);
      bool fits(TextPainter t) =>
          !t.didExceedMaxLines &&
          t.width <= width - 4 / z &&
          t.height <= height - 2 / z;
      // The full code, then without the building's character, then smaller
      // down to 7 px on screen, so even a cupboard-sized room keeps its
      // number in the whole-floor view; long names stay in the drawer.
      final options = [label, ?s.shortCode];
      TextPainter? shown;
      for (final text in options) {
        final t = layout(text, base);
        if (fits(t)) {
          shown = t;
          break;
        }
        final shrink = math.min(
          (width - 4 / z) / t.width,
          (height - 2 / z) / t.height,
        );
        if (identical(text, options.last) && base * shrink * z >= 7) {
          final small = layout(text, base * shrink * .98);
          if (fits(small)) shown = small;
        }
      }
      // A room known only by its name, like 理論與計算流力實驗室, wraps onto
      // up to three lines before it gives up.
      if (shown == null && s.code == null && width > 4 / z) {
        for (var size = base; size * z >= 7; size *= .9) {
          final t = layout(label, size, lines: 3);
          if (fits(t)) {
            shown = t;
            break;
          }
        }
      }
      if (shown == null) continue;
      shown.paint(
        canvas,
        frame.toCanvas(box.center) - Offset(shown.width / 2, shown.height / 2),
      );
    }
  }

  /// A pill reading 往… with an arrow towards the other building.
  void _link(Canvas canvas, FloorFrame frame, MapLink link, double z) {
    final ink = hues.link;
    // The arrow turns with the plan.
    var d = link.toward;
    if (frame.rotated) d = Offset(-d.dy, d.dx);
    d = d / d.distance;
    // A link through a north or south wall reads top to bottom, one
    // character a line, so it fits the narrow walkway it stands in.
    final upright = d.dy.abs() > d.dx.abs();
    final label = '往${link.name}';
    final text = TextPainter(
      text: TextSpan(
        text: upright ? label.characters.join('\n') : label,
        style: textStyle.copyWith(
          fontSize: (textStyle.fontSize ?? 11) / z,
          fontWeight: FontWeight.w600,
          color: ink,
          height: upright ? 1.05 : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final arrow = 10 / z, pad = 6 / z, gap = 4 / z;
    final w = upright
        ? math.max(text.width, arrow) + pad
        : text.width + arrow + gap + pad * 2;
    final h = upright
        ? text.height + arrow + gap + pad * 2
        : math.max(text.height, arrow) + pad;
    // The pill stays inside, its arrow end at the doorway, so a link on an
    // outside wall is never cut off by the screen edge.
    final centre = frame.toCanvas(link.at) - Offset(d.dx * w, d.dy * h) / 2;
    final pill = Rect.fromCenter(center: centre, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, Radius.circular(math.min(w, h) / 2)),
      Paint()..color = hues.linkFill,
    );
    // Text away from the doorway, the arrow at it.
    final towards = upright ? d.dy > 0 : d.dx > 0;
    final Offset textAt;
    final Offset arrowAt;
    if (upright) {
      textAt = Offset(
        centre.dx - text.width / 2,
        towards ? pill.top + pad : pill.bottom - pad - text.height,
      );
      arrowAt = Offset(
        centre.dx,
        towards ? pill.bottom - pad - arrow / 2 : pill.top + pad + arrow / 2,
      );
    } else {
      textAt = Offset(
        towards ? pill.left + pad : pill.right - pad - text.width,
        centre.dy - text.height / 2,
      );
      arrowAt = Offset(
        towards ? pill.right - pad - arrow / 2 : pill.left + pad + arrow / 2,
        centre.dy,
      );
    }
    text.paint(canvas, textAt);
    final tip = arrowAt + d * arrow / 2;
    final back = tip - d * arrow;
    final side = Offset(-d.dy, d.dx) * arrow * .45;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + side.dx, back.dy + side.dy)
        ..lineTo(back.dx - side.dx, back.dy - side.dy)
        ..close(),
      Paint()..color = ink,
    );
  }

  /// A door no one may pass: a red bar across it, crossed out halfway.
  void _closed(Canvas canvas, List<Offset> line, double px) {
    if (line.length < 2) return;
    final paint = Paint()
      ..color = colors.error
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * px
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..addPolygon(line, false), paint);
    var left = 0.0;
    for (var i = 1; i < line.length; i++) {
      left += (line[i] - line[i - 1]).distance;
    }
    left /= 2;
    var mid = line.last;
    for (var i = 1; i < line.length; i++) {
      final step = (line[i] - line[i - 1]).distance;
      if (left <= step && step > 0) {
        mid = Offset.lerp(line[i - 1], line[i], left / step)!;
        break;
      }
      left -= step;
    }
    final r = 5 * px;
    paint.strokeWidth = 2 * px;
    canvas.drawLine(mid + Offset(-r, -r), mid + Offset(r, r), paint);
    canvas.drawLine(mid + Offset(r, -r), mid + Offset(-r, r), paint);
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
