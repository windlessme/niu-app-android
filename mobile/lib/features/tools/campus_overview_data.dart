import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

/// One building outline; [plan] names its floor plans when they exist.
class CampusBuilding {
  CampusBuilding({
    required this.id,
    required this.polygon,
    required this.onCampus,
    this.name,
    this.levels,
    this.plan,
  });

  factory CampusBuilding.fromJson(Map<String, dynamic> json) => CampusBuilding(
    id: json['id'] as int,
    polygon: _points(json['polygon']),
    onCampus: json['campus'] as bool? ?? false,
    name: json['name'] as String?,
    levels: json['levels'] as int?,
    plan: json['plan'] as String?,
  );

  final int id;
  final List<Offset> polygon;
  final bool onCampus;
  final String? name;
  final int? levels;
  final String? plan;

  late final Path path = Path()..addPolygon(polygon, true);
  late final Rect bounds = path.getBounds();

  /// Area-weighted centre, where the name goes.
  late final Offset centre = () {
    var a = 0.0, x = 0.0, y = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final p = polygon[i], q = polygon[(i + 1) % polygon.length];
      final cross = p.dx * q.dy - q.dx * p.dy;
      a += cross;
      x += (p.dx + q.dx) * cross;
      y += (p.dy + q.dy) * cross;
    }
    return a.abs() < 1e-6 ? bounds.center : Offset(x / (3 * a), y / (3 * a));
  }();
}

enum CampusAreaKind { sport, green, water, parking }

enum CampusRoadKind { street, service, path }

/// The campus overview from OpenStreetMap, in metres east (x) and south (y)
/// of the campus centre; north is up. Shared with iOS under app-content.
class CampusOverview {
  CampusOverview({
    required this.attribution,
    required this.bounds,
    required this.boundary,
    required this.buildings,
    required this.areas,
    required this.roads,
  });

  factory CampusOverview.fromJson(Map<String, dynamic> json) {
    final b = [for (final v in json['bounds'] as List) (v as num).toDouble()];
    return CampusOverview(
      attribution: json['attribution'] as String,
      bounds: Rect.fromLTRB(b[0], b[1], b[2], b[3]),
      boundary: _points(json['boundary']),
      buildings: [
        for (final e in json['buildings'] as List)
          CampusBuilding.fromJson(e as Map<String, dynamic>),
      ],
      areas: [
        for (final e in json['areas'] as List)
          (
            kind: CampusAreaKind.values.byName(e['kind'] as String),
            path: Path()..addPolygon(_points(e['polygon']), true),
          ),
      ],
      roads: [
        for (final e in json['roads'] as List)
          (
            kind: CampusRoadKind.values.byName(e['kind'] as String),
            line: _points(e['line']),
          ),
      ],
    );
  }

  static const asset = 'assets/campus_map/campus.json';
  static Future<CampusOverview>? _shared;

  /// Parsed once per app run.
  static Future<CampusOverview> load([AssetBundle? bundle]) {
    Future<CampusOverview> read() async => CampusOverview.fromJson(
      jsonDecode(await (bundle ?? rootBundle).loadString(asset))
          as Map<String, dynamic>,
    );
    return bundle == null ? _shared ??= read() : read();
  }

  final String attribution;
  final Rect bounds;
  final List<Offset> boundary;
  final List<CampusBuilding> buildings;
  final List<({CampusAreaKind kind, Path path})> areas;
  final List<({CampusRoadKind kind, List<Offset> line})> roads;

  late final Path boundaryPath = Path()..addPolygon(boundary, true);

  /// What the first view frames: the campus with a little street around it.
  late final Rect campus = boundaryPath.getBounds().inflate(60);

  /// The building under [point], campus buildings first.
  CampusBuilding? buildingAt(Offset point) {
    CampusBuilding? hit;
    for (final b in buildings) {
      if (!b.bounds.contains(point) || !b.path.contains(point)) continue;
      if (hit == null || b.onCampus && !hit.onCampus) hit = b;
    }
    return hit;
  }

  /// Named campus buildings whose name contains [query].
  List<CampusBuilding> searchBuildings(String query) {
    final q = query.replaceAll(RegExp(r'\s'), '');
    if (q.isEmpty) return const [];
    return [
      for (final b in buildings)
        if (b.onCampus && (b.name?.contains(q) ?? false)) b,
    ];
  }

  CampusBuilding? withPlan(String plan) {
    for (final b in buildings) {
      if (b.plan == plan) return b;
    }
    return null;
  }
}

Offset _point(Object? p) {
  final list = p as List;
  return Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
}

List<Offset> _points(Object? list) => [for (final p in list as List) _point(p)];
