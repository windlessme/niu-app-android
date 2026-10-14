enum FloorSpaceKind { classroom, venue, utility, passage, external, gap }

class FloorSpace {
  const FloorSpace({
    required this.id,
    required this.name,
    required this.kind,
    this.note,
    this.span = 1,
  });
  final String id, name;
  final FloorSpaceKind kind;
  final String? note;
  final double span;

  bool get isRoom =>
      kind == FloorSpaceKind.classroom || kind == FloorSpaceKind.venue;
}

class BuildingFloor {
  /// Assigns stable position IDs to cells without room names.
  BuildingFloor({required this.id, required List<List<FloorSpace>> rows})
    : rows = List.unmodifiable([
        for (var row = 0; row < rows.length; row++)
          List<FloorSpace>.unmodifiable([
            for (var col = 0; col < rows[row].length; col++)
              FloorSpace(
                id: rows[row][col].isRoom
                    ? rows[row][col].name
                    : '$id-$row-$col',
                name: rows[row][col].name,
                kind: rows[row][col].kind,
                note: rows[row][col].note,
                span: rows[row][col].span,
              ),
          ]),
      ]);
  final String id;
  final List<List<FloorSpace>> rows;

  String get title => id.startsWith('B')
      ? '地下 ${id.substring(1)} 樓'
      : '${id.substring(0, id.length - 1)} 樓';

  List<FloorSpace> get rooms => List.unmodifiable(
    rows.expand((row) => row).where((space) => space.isRoom),
  );
}

class FloorPlanSource {
  const FloorPlanSource({
    required this.title,
    required this.pdf,
    required this.page,
    required this.revisedOn,
  });
  final String title;
  final Uri pdf, page;
  final String revisedOn;
}

class CampusBuilding {
  CampusBuilding({
    required this.id,
    required this.name,
    required List<BuildingFloor> floors,
    required this.source,
  }) : floors = List.unmodifiable(floors);
  final String id, name;
  final List<BuildingFloor> floors;
  final FloorPlanSource source;

  String get defaultFloorId =>
      floor('1F')?.id ?? (floors.isEmpty ? '' : floors.first.id);

  BuildingFloor? floor(String id) {
    for (final floor in floors) {
      if (floor.id == id) return floor;
    }
    return null;
  }
}

/// Where a room sits in the catalog.
typedef RoomLocation = ({
  CampusBuilding building,
  BuildingFloor floor,
  FloorSpace space,
});

/// Relative layouts transcribed from the school's classroom floor plans.
abstract final class CampusBuildingCatalog {
  static final List<CampusBuilding> buildings = List.unmodifiable([
    _jiaose(),
    _zonghe(),
  ]);

  /// Finds the longest room name mentioned in timetable text.
  static RoomLocation? locate(String text) {
    final normalized = String.fromCharCodes(
      text.runes.map(
        (code) => code >= 0xff01 && code <= 0xff5e ? code - 0xfee0 : code,
      ),
    ).replaceAll(RegExp(r'\s|\u3000'), '');
    RoomLocation? match;
    for (final building in buildings) {
      for (final floor in building.floors) {
        for (final space in floor.rooms) {
          if (normalized.contains(space.name) &&
              (match == null || space.name.length > match.space.name.length)) {
            match = (building: building, floor: floor, space: space);
          }
        }
      }
    }
    return match;
  }
}

FloorSpace _space(
  String name,
  FloorSpaceKind kind, {
  String? note,
  double span = 1,
}) => FloorSpace(id: name, name: name, kind: kind, note: note, span: span);
FloorSpace _room(String name, {String? note}) =>
    _space(name, FloorSpaceKind.classroom, note: note);
FloorSpace _venue(String name, {double span = 1}) =>
    _space(name, FloorSpaceKind.venue, span: span);
FloorSpace _utility(String name, {double span = 1}) =>
    _space(name, FloorSpaceKind.utility, span: span);
FloorSpace _passage(String name, {double span = 1}) =>
    _space(name, FloorSpaceKind.passage, span: span);
FloorSpace _gap({double span = 1}) =>
    _space('', FloorSpaceKind.gap, span: span);

FloorPlanSource _source(String title, String pdf) => FloorPlanSource(
  title: title,
  pdf: Uri.parse(pdf),
  page: Uri.parse('https://academic.niu.edu.tw/p/412-1003-465.php'),
  revisedOn: '2024/05/23',
);

CampusBuilding _jiaose() {
  const notes = {
    101: '學生休息室',
    104: '通識選修優先排課',
    105: '通識選修優先排課',
    106: '通識選修優先排課',
    107: '通識選修優先排課',
    206: 'PBL 問題行動導向優先',
    207: 'PBL 問題行動導向優先',
    208: '環境與永續發展優先',
    209: '人文經典閱讀優先',
    210: '人文經典閱讀優先',
    214: '職涯教育專業教室',
    311: '職涯教育專業教室',
    401: '外語學系優先排課',
    412: '外語學系優先排課',
  };
  FloorSpace room(int number) => _room('教$number', note: notes[number]);
  final floors = [
    BuildingFloor(
      id: 'B1',
      rows: [
        [
          _gap(),
          _venue('原住民族學生資源中心', span: 2),
          _gap(),
          _utility('機房', span: 2),
          _gap(),
          _utility('樓梯'),
        ],
        [
          _gap(),
          _passage('地下室中庭', span: 4),
          _utility('庫房'),
          _gap(),
          _utility('樓梯'),
        ],
      ],
    ),
  ];
  for (var level = 1; level <= 4; level++) {
    final base = level * 100;
    final core = _utility(level >= 2 && level <= 3 ? '樓梯・洗手間' : '樓梯');
    floors.add(
      BuildingFloor(
        id: '${level}F',
        rows: [
          [
            level >= 3 ? room(base + 11) : _gap(),
            for (var n = 10; n >= 6; n--) room(base + n),
            level == 2 ? room(214) : _gap(),
            core,
          ],
          [level == 1 ? _passage('正門') : _gap(), _gap(span: 7)],
          [
            level >= 3 ? room(base + 12) : _gap(),
            for (var n = 1; n <= 5; n++) room(base + n),
            _gap(),
            core,
          ],
        ],
      ),
    );
  }
  return CampusBuilding(
    id: 'jiaose',
    name: '教穡大樓',
    floors: floors,
    source: _source(
      '國立宜蘭大學教穡大樓教室編號及位置圖',
      'https://academic.niu.edu.tw/var/file/3/1003/img/215/770697857.pdf',
    ),
  );
}

CampusBuilding _zonghe() {
  const notes = {203: '進修推廣組辦公室', 303: '教師休息室'};
  FloorSpace room(int number) => _room('綜$number', note: notes[number]);
  final floors = [
    BuildingFloor(
      id: 'B1',
      rows: [
        [_gap(), _room('綜B102'), _room('綜B101'), _gap(span: 6)],
        [
          _gap(),
          _venue('萬斌廳', span: 2),
          _venue('交誼廳'),
          _passage('台階'),
          _gap(span: 3),
          _passage('川堂'),
        ],
      ],
    ),
  ];
  for (var level = 1; level <= 4; level++) {
    final base = level * 100;
    final backCore = _utility(switch (level) {
      1 => '樓梯・電梯',
      4 => '女廁',
      _ => '男廁',
    });
    final frontCore = _utility(level == 1 ? '電梯' : '男廁・女廁');
    floors.add(
      BuildingFloor(
        id: '${level}F',
        rows: [
          [
            _utility('樓梯'),
            room(base + 6),
            room(base + 5),
            room(base + 4),
            backCore,
            _passage('川堂'),
            _utility('樓梯'),
            _passage('戶外川堂'),
            _space('行政大樓', FloorSpaceKind.external),
          ],
          [_gap(span: 9)],
          [
            room(base + 1),
            _passage('川堂'),
            _utility('樓梯'),
            frontCore,
            room(base + 2),
            room(base + 3),
            _utility('樓梯'),
            _passage('戶外川堂'),
            _space('行政大樓', FloorSpaceKind.external),
          ],
        ],
      ),
    );
  }
  return CampusBuilding(
    id: 'zonghe',
    name: '綜合教學大樓',
    floors: floors,
    source: _source(
      '國立宜蘭大學綜合教學大樓教室編號及位置圖',
      'https://academic.niu.edu.tw/var/file/3/1003/img/215/546203924.pdf',
    ),
  );
}
