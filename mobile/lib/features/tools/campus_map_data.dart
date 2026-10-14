import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

/// What a space on a floor plan is; drawn and hit-tested by kind.
enum MapSpaceKind {
  room,
  corridor,
  stairs,
  elevator,
  restroom,
  shaft,
  terrace;

  static MapSpaceKind parse(String value) => switch (value) {
    'room' => room,
    'stairs' => stairs,
    'elevator' => elevator,
    'restroom' => restroom,
    'void' => shaft,
    'terrace' => terrace,
    _ => corridor,
  };
}

/// One space in metres; [code] matches the school's classroom code.
class MapSpace {
  MapSpace({
    required this.kind,
    required this.points,
    required this.isRect,
    this.code,
    this.name,
    this.note,
    this.aka = const [],
  });

  factory MapSpace.fromJson(Map<String, dynamic> json) {
    final rect = json['rect'] as List?;
    final points = rect != null
        ? _rectPoints(rect)
        : [for (final p in json['polygon'] as List) _offset(p)];
    return MapSpace(
      kind: MapSpaceKind.parse(json['kind'] as String),
      points: points,
      isRect: rect != null,
      code: json['code'] as String?,
      name: json['name'] as String?,
      note: json['note'] as String?,
      aka: [for (final a in json['aka'] as List? ?? const []) a as String],
    );
  }

  final MapSpaceKind kind;
  final List<Offset> points;
  final bool isRect;
  final String? code;

  /// What the sign calls it, e.g. 薄膜實驗室 or 男廁.
  final String? name;
  final String? note;

  /// Other codes the school uses for the room (E505, 格101): searchable and
  /// found in timetables, never shown.
  final List<String> aka;

  /// The code without its building character (教305 → 305) when it has
  /// one; E and 格 codes keep theirs.
  String? get shortCode {
    final c = code;
    if (c == null ||
        c.isEmpty ||
        c.codeUnitAt(0) < 0x2E80 ||
        c.startsWith('格')) {
      return null;
    }
    return c.substring(1);
  }

  /// Everything a timetable or search might call the room.
  late final List<String> names = [?label, ...aka];

  late final Rect bounds = _bounds(points);
  late final Path path = Path()..addPolygon(points, true);

  bool get isRoom => kind == MapSpaceKind.room;

  /// Code, else name; what a list or card leads with.
  String? get label => code ?? name;

  /// The name and note under a code, or just the note under a name.
  List<String> get details => [if (code != null) ?name, ?note];
}

/// A way out of the building towards another one.
class MapLink {
  const MapLink({
    required this.to,
    required this.name,
    required this.at,
    required this.toward,
  });

  factory MapLink.fromJson(Map<String, dynamic> json) => MapLink(
    to: json['to'] as String,
    name: json['name'] as String,
    at: _offset(json['at']),
    toward: _offset(json['toward']),
  );

  /// The other building's id, and its name for the sign.
  final String to, name;

  /// Where the sign sits and which way it points, in metres.
  final Offset at, toward;
}

class MapFloor {
  MapFloor({
    required this.id,
    required this.outline,
    required this.spaces,
    this.links = const [],
    this.unit,
    this.aliases = const [],
  });

  factory MapFloor.fromJson(Map<String, dynamic> json) => MapFloor(
    id: json['id'] as String,
    outline: [for (final p in json['outline'] as List) _offset(p)],
    spaces: [
      for (final s in json['spaces'] as List)
        MapSpace.fromJson(s as Map<String, dynamic>),
    ],
    links: [
      for (final l in json['links'] as List? ?? const [])
        MapLink.fromJson(l as Map<String, dynamic>),
    ],
    unit: json['unit'] as String?,
    aliases: [
      for (final a in json['aliases'] as List? ?? const []) a as String,
    ],
  );

  final String id;
  final List<Offset> outline;
  final List<MapSpace> spaces;
  final List<MapLink> links;

  /// Who the floor belongs to, e.g. 環境工程學系, and what people call it.
  final String? unit;
  final List<String> aliases;

  /// Whether [query] names this floor's unit: 環工, 機械系, 化學工程.
  bool namesUnit(String query) =>
      unit != null &&
      (unit!.contains(query) ||
          aliases.any((a) => a.contains(query) || query.contains(a)));

  /// 'B1' → '地下 1 樓', '3F' → '3 樓'.
  String get title => id.startsWith('B')
      ? '地下 ${id.substring(1)} 樓'
      : '${id.substring(0, id.length - 1)} 樓';

  late final List<MapSpace> rooms = [
    for (final s in spaces)
      if (s.isRoom) s,
  ];

  late final Rect bounds = [
    _bounds(outline),
    for (final s in spaces) s.bounds,
  ].reduce((a, b) => a.expandToInclude(b));

  /// The smallest room under [point], else nothing; corridors aren't picked.
  MapSpace? roomAt(Offset point) {
    MapSpace? hit;
    for (final s in rooms) {
      if (s.path.contains(point) &&
          (hit == null || s.bounds.shortestSide < hit.bounds.shortestSide)) {
        hit = s;
      }
    }
    return hit;
  }
}

class MapBuilding {
  MapBuilding({required this.id, required this.name, required this.floors});

  factory MapBuilding.fromJson(Map<String, dynamic> json) => MapBuilding(
    id: json['id'] as String,
    name: json['name'] as String,
    floors: [
      for (final f in json['floors'] as List)
        MapFloor.fromJson(f as Map<String, dynamic>),
    ],
  );

  final String id, name;
  final List<MapFloor> floors;

  String get defaultFloorId =>
      floor('1F')?.id ?? (floors.isEmpty ? '' : floors.first.id);

  MapFloor? floor(String id) {
    for (final f in floors) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Shared by every floor so switching floors keeps the same framing.
  late final Rect bounds = floors
      .map((f) => f.bounds)
      .reduce((a, b) => a.expandToInclude(b));

  /// '地上 8 層，地下 1 層'.
  String get levels {
    final below = floors.where((f) => f.id.startsWith('B')).length;
    final above = floors.length - below;
    return below == 0 ? '地上 $above 層' : '地上 $above 層，地下 $below 層';
  }
}

/// Where a room sits; returned by [CampusMap.locate].
typedef RoomLocation = ({MapBuilding building, MapFloor floor, MapSpace space});

/// Buildings drawn from each floor's evacuation sign; the JSON is shared with
/// iOS under app-content/campus-map and bundled here for offline use.
class CampusMap {
  CampusMap(this.buildings);

  static const assets = [
    'assets/campus_map/jiaose.json',
    'assets/campus_map/gongxue.json',
    'assets/campus_map/shixi.json',
    'assets/campus_map/dianzi.json',
    'assets/campus_map/shihua.json',
    'assets/campus_map/gezhi.json',
    'assets/campus_map/zonghe.json',
  ];

  final List<MapBuilding> buildings;

  static Future<CampusMap>? _shared;

  /// Parsed once per app run.
  static Future<CampusMap> load([AssetBundle? bundle]) {
    Future<CampusMap> read() async {
      final source = bundle ?? rootBundle;
      return CampusMap([
        for (final path in assets)
          MapBuilding.fromJson(
            jsonDecode(await source.loadString(path)) as Map<String, dynamic>,
          ),
      ]);
    }

    return bundle == null ? _shared ??= read() : read();
  }

  MapBuilding? building(String id) {
    for (final b in buildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Finds a classroom code or name in timetable text such as '教305' or
  /// '教 305（電腦教室）'; whitespace and full-width forms are ignored and the
  /// longest match wins.
  RoomLocation? locate(String text) {
    final normalized = String.fromCharCodes(
      text.runes.map((c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c),
    ).replaceAll(RegExp(r'\s'), '');
    if (normalized.isEmpty) return null;
    RoomLocation? match;
    var matched = 0;
    for (final b in buildings) {
      for (final f in b.floors) {
        for (final s in f.rooms) {
          if (s.label == null) continue;
          for (final name in s.names) {
            if (normalized.contains(name) &&
                (match == null || name.length > matched)) {
              match = (building: b, floor: f, space: s);
              matched = name.length;
            }
          }
        }
      }
    }
    return match;
  }

  /// Rooms whose code, name or note contains [query], in building and
  /// floor order; a bare number matches codes ('305' → 教305), and a
  /// department's name or nickname its offices ('環工' → 系辦公室).
  List<RoomLocation> search(String query) {
    final q = query.replaceAll(RegExp(r'\s'), '');
    if (q.isEmpty) return const [];
    bool hit(MapSpace s) {
      final code = s.code;
      return code != null &&
              (code.contains(q) || (s.shortCode?.startsWith(q) ?? false)) ||
          s.aka.any((a) => a.contains(q)) ||
          (s.name?.contains(q) ?? false) ||
          (s.note?.contains(q) ?? false);
    }

    return [
      for (final b in buildings)
        for (final f in b.floors)
          for (final s in f.rooms)
            if (s.label != null &&
                (hit(s) || s.note == f.unit && f.namesUnit(q)))
              (building: b, floor: f, space: s),
    ];
  }
}

Offset _offset(Object? p) {
  final list = p as List;
  return Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
}

List<Offset> _rectPoints(List rect) {
  final [x, y, w, h] = [for (final v in rect) (v as num).toDouble()];
  return [
    Offset(x, y),
    Offset(x + w, y),
    Offset(x + w, y + h),
    Offset(x, y + h),
  ];
}

Rect _bounds(List<Offset> points) {
  var l = points.first.dx, t = points.first.dy, r = l, b = t;
  for (final p in points) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}
