import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'campus_overview_data.dart';

/// Maps the overview's metres onto a canvas, north up, framing the campus
/// in the area [padding] leaves clear.
class OverviewFrame {
  OverviewFrame(this.map, this.size, {this.padding = EdgeInsets.zero}) {
    final room = padding.deflateRect(Offset.zero & size);
    final c = map.campus;
    scale = math.max(
      math.min(room.width / c.width, room.height / c.height),
      .01,
    );
    offset = room.center - c.center * scale;
  }

  final CampusOverview map;
  final Size size;
  final EdgeInsets padding;
  late final double scale;
  late final Offset offset;

  Offset toCanvas(Offset metres) => metres * scale + offset;
  Offset toMetres(Offset canvas) => (canvas - offset) / scale;
}

typedef OverviewHues = ({
  Color green,
  Color sport,
  Color water,
  Color campus,
  Color plan,
  Color planEdge,
});

class CampusOverviewPainter extends CustomPainter {
  CampusOverviewPainter({
    required this.map,
    required this.colors,
    required this.hues,
    required this.textStyle,
    this.padding = EdgeInsets.zero,
    this.selected,
    this.zoom,
  }) : super(repaint: zoom);

  final CampusOverview map;
  final NiuColors colors;
  final OverviewHues hues;
  final TextStyle textStyle;

  final EdgeInsets padding;
  final CampusBuilding? selected;
  final TransformationController? zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = OverviewFrame(map, size, padding: padding);
    final z = zoom?.value.getMaxScaleOnAxis() ?? 1;
    // One screen pixel, in metres, whatever the zoom.
    final px = 1 / (frame.scale * z);

    canvas.save();
    canvas.translate(frame.offset.dx, frame.offset.dy);
    canvas.scale(frame.scale);

    canvas.drawPath(map.boundaryPath, Paint()..color = hues.campus);
    for (final a in map.areas) {
      final color = switch (a.kind) {
        CampusAreaKind.sport => hues.sport,
        CampusAreaKind.green => hues.green,
        CampusAreaKind.water => hues.water,
        CampusAreaKind.parking => colors.fill,
      };
      canvas.drawPath(a.path, Paint()..color = color);
    }

    Path line(List<Offset> points) => Path()..addPolygon(points, false);
    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colors.hairline;
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colors.surface;
    // Streets keep a readable width on screen but never shrink below their
    // real width when zoomed in.
    double width(CampusRoadKind kind) => switch (kind) {
      CampusRoadKind.street => math.max(7.0, 5 * px),
      CampusRoadKind.service => math.max(3.5, 3 * px),
      CampusRoadKind.path => math.max(1.2, 1.5 * px),
    };
    for (final kind in CampusRoadKind.values.reversed) {
      for (final r in map.roads) {
        if (r.kind != kind || kind == CampusRoadKind.path) continue;
        canvas.drawPath(
          line(r.line),
          casing..strokeWidth = width(kind) + 2 * px,
        );
      }
    }
    for (final kind in CampusRoadKind.values.reversed) {
      for (final r in map.roads) {
        if (r.kind != kind) continue;
        canvas.drawPath(
          line(r.line),
          (kind == CampusRoadKind.path
                ? (Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeCap = StrokeCap.round
                    ..color = colors.surface.withValues(alpha: .9))
                : road)
            ..strokeWidth = width(kind),
        );
      }
    }

    for (final b in map.buildings) {
      final on = identical(b, selected);
      final (fill, edge) = on
          ? (colors.accent, colors.accent)
          : b.plan != null
          ? (hues.plan, hues.planEdge)
          : b.onCampus
          ? (colors.accentSoft, colors.accent.withValues(alpha: .3))
          : (colors.fillStrong, colors.hairline);
      canvas.drawPath(b.path, Paint()..color = fill);
      canvas.drawPath(
        b.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (on ? 2 : 1) * px
          ..color = edge,
      );
    }
    canvas.drawPath(
      map.boundaryPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..color = colors.accent,
    );
    canvas.restore();

    // Labels in screen space: fixed size, no overlaps, selection first.
    final taken = <Rect>[];
    bool place(Rect r) {
      if (taken.any((t) => t.overlaps(r))) return false;
      taken.add(r.inflate(2 / z));
      return true;
    }

    final fontSize = (textStyle.fontSize ?? 11) / z;

    final named =
        [
          for (final b in map.buildings)
            if (b.onCampus && b.name != null) b,
        ]..sort((a, b) {
          // Picked first, then buildings with plans, then those with a name
          // people know them by (格致大樓 is 電資學院), then the rest;
          // 司令台 and the like last.
          int rank(CampusBuilding x) => identical(x, selected)
              ? 0
              : x.plan != null
              ? 1
              : x.name!.contains('（')
              ? 2
              : x.listed
              ? 3
              : 4;
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0
              ? byRank
              : b.bounds.longestSide.compareTo(a.bounds.longestSide);
        });
    // The part of the canvas on screen, where labels are laid out.
    final visible = MatrixUtils.inverseTransformRect(
      zoom?.value ?? Matrix4.identity(),
      Offset.zero & size,
    );
    for (final b in named) {
      final on = identical(b, selected);
      // On the building, else around it, then a size smaller, so the
      // crowded west side of campus keeps its names at the whole-campus view.
      final at = frame.toCanvas(b.centre);
      final half = b.bounds.size * frame.scale / 2;
      for (final size in [fontSize, fontSize * .85]) {
        final label = _text(
          mapName(b.name!),
          size,
          on ? colors.accent : colors.ink,
          weight: on || b.plan != null ? FontWeight.w700 : FontWeight.w500,
          halo: colors.canvas,
        );
        final w = label.width, h = label.height;
        final dx = half.width + w / 2, dy = half.height + h / 2;
        Rect? spot;
        for (final d in [
          Offset.zero,
          Offset(0, -dy),
          Offset(0, dy),
          Offset(-dx, 0),
          Offset(dx, 0),
          Offset(dx, -dy),
          Offset(-dx, -dy),
          Offset(dx, dy),
          Offset(-dx, dy),
        ]) {
          final r = Rect.fromCenter(center: at + d, width: w, height: h);
          // Only centred labels may run off screen; moved ones stay on it.
          if (d != Offset.zero && !visible.contains(r.topLeft)) continue;
          if (d != Offset.zero && !visible.contains(r.bottomRight)) continue;
          if (place(r)) {
            spot = r;
            break;
          }
        }
        if (spot != null) {
          label.paint(canvas, spot.topLeft);
          break;
        }
      }
    }
  }

  TextPainter _text(
    String text,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w500,
    Color? halo,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: textStyle.copyWith(
        fontSize: size,
        color: color,
        fontWeight: weight,
        shadows: halo == null
            ? null
            : [
                for (final o in const [
                  Offset(1, 0),
                  Offset(-1, 0),
                  Offset(0, 1),
                  Offset(0, -1),
                ])
                  Shadow(color: halo, offset: o * size / 12),
              ],
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
  )..layout();

  /// A name with another in brackets stacks them, so 格致大樓（電資學院）
  /// takes the width of one and leaves room for its neighbours' names.
  static String mapName(String name) => name.replaceAllMapped(
    RegExp(r'\s*[（(]([^）)]+)[）)]\s*$'),
    (m) => '\n${m[1]}',
  );

  @override
  bool shouldRepaint(CampusOverviewPainter old) =>
      old.map != map ||
      old.selected != selected ||
      old.colors != colors ||
      old.padding != padding;
}
