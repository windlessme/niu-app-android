import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/tools/floor_plan_data.dart';

void main() {
  final buildings = CampusBuildingCatalog.buildings;
  final jiaose = buildings[0];
  final zonghe = buildings[1];

  test('building and floor order, titles, and defaults', () {
    expect(buildings.map((b) => b.id), ['jiaose', 'zonghe']);
    expect(buildings.map((b) => b.name), ['教穡大樓', '綜合教學大樓']);
    for (final building in buildings) {
      expect(building.floors.length, 5);
      expect(building.floors.map((f) => f.id), ['B1', '1F', '2F', '3F', '4F']);
      expect(building.floors.map((f) => f.title), [
        '地下 1 樓',
        '1 樓',
        '2 樓',
        '3 樓',
        '4 樓',
      ]);
      expect(building.defaultFloorId, '1F');
      expect(building.floor('5F'), isNull);
    }
    final basementOnly = CampusBuilding(
      id: 'test',
      name: 'test',
      floors: [jiaose.floor('B1')!],
      source: jiaose.source,
    );
    expect(basementOnly.defaultFloorId, 'B1');
  });

  test('room notes and floor placement', () {
    FloorSpace room(CampusBuilding building, String floor, String name) =>
        building.floor(floor)!.rooms.singleWhere((s) => s.name == name);
    expect(room(jiaose, '1F', '教101').note, '學生休息室');
    expect(room(jiaose, '2F', '教214').note, '職涯教育專業教室');
    expect(room(jiaose, '3F', '教311').note, '職涯教育專業教室');
    expect(room(jiaose, '3F', '教312').note, isNull);
    expect(
      jiaose
          .floor('1F')!
          .rooms
          .where((s) => s.name == '教311' || s.name == '教312'),
      isEmpty,
    );
    expect(room(zonghe, 'B1', '綜B101').kind, FloorSpaceKind.classroom);
    expect(room(zonghe, '3F', '綜303').note, '教師休息室');
    expect(room(zonghe, '2F', '綜203').note, '進修推廣組辦公室');
  });

  test('stable unique IDs and immutable rows', () {
    for (final building in buildings) {
      for (final floor in building.floors) {
        final cells = floor.rows.expand((r) => r).toList();
        expect(cells.map((s) => s.id).toSet().length, cells.length);
        for (var r = 0; r < floor.rows.length; r++) {
          for (var c = 0; c < floor.rows[r].length; c++) {
            final space = floor.rows[r][c];
            expect(space.id, space.isRoom ? space.name : '${floor.id}-$r-$c');
          }
        }
        expect(() => floor.rows.clear(), throwsUnsupportedError);
        expect(() => floor.rows.first.clear(), throwsUnsupportedError);
      }
    }
    expect(() => buildings.clear(), throwsUnsupportedError);
    expect(() => jiaose.floors.clear(), throwsUnsupportedError);
  });

  test('rooms retain row-major order', () {
    expect(jiaose.floor('B1')!.rooms.map((s) => s.name), ['原住民族學生資源中心']);
    expect(jiaose.floor('2F')!.rooms.map((s) => s.name), [
      '教210',
      '教209',
      '教208',
      '教207',
      '教206',
      '教214',
      '教201',
      '教202',
      '教203',
      '教204',
      '教205',
    ]);
    expect(jiaose.floor('3F')!.rooms.map((s) => s.name), [
      '教311',
      '教310',
      '教309',
      '教308',
      '教307',
      '教306',
      '教312',
      '教301',
      '教302',
      '教303',
      '教304',
      '教305',
    ]);
    expect(zonghe.floor('B1')!.rooms.map((s) => s.name), [
      '綜B102',
      '綜B101',
      '萬斌廳',
      '交誼廳',
    ]);
    expect(zonghe.floor('4F')!.rooms.map((s) => s.name), [
      '綜406',
      '綜405',
      '綜404',
      '綜401',
      '綜402',
      '綜403',
    ]);
  });

  test('layout cells, spans, and facilities match the source', () {
    final basement = jiaose.floor('B1')!;
    expect(basement.rows.map((r) => r.map((s) => s.name).toList()), [
      ['', '原住民族學生資源中心', '', '機房', '', '樓梯'],
      ['', '地下室中庭', '庫房', '', '樓梯'],
    ]);
    expect(basement.rows[0].map((s) => s.span), [1, 2, 1, 2, 1, 1]);
    expect(basement.rows[1].map((s) => s.span), [1, 4, 1, 1, 1]);
    for (var level = 1; level <= 4; level++) {
      final floor = jiaose.floor('${level}F')!;
      expect(floor.rows.map((r) => r.length), [8, 2, 8]);
      expect(floor.rows[1][0].name, level == 1 ? '正門' : '');
      expect(floor.rows[1][1].span, 7);
      expect(
        floor.rows[0].last.name,
        level == 2 || level == 3 ? '樓梯・洗手間' : '樓梯',
      );
      final other = zonghe.floor('${level}F')!;
      expect(other.rows.map((r) => r.length), [9, 1, 9]);
      expect(other.rows[1].single.span, 9);
      expect(
        other.rows[0][4].name,
        level == 1
            ? '樓梯・電梯'
            : level == 4
            ? '女廁'
            : '男廁',
      );
      expect(other.rows[2][3].name, level == 1 ? '電梯' : '男廁・女廁');
      expect(other.rows[0].last.kind, FloorSpaceKind.external);
    }
    expect(zonghe.floor('B1')!.rows[0].map((s) => s.span), [1, 1, 1, 6]);
    expect(zonghe.floor('B1')!.rows[1].map((s) => s.span), [1, 2, 1, 1, 3, 1]);
  });

  test('source metadata is preserved', () {
    expect(jiaose.source.title, '國立宜蘭大學教穡大樓教室編號及位置圖');
    expect(zonghe.source.title, '國立宜蘭大學綜合教學大樓教室編號及位置圖');
    expect(
      jiaose.source.pdf.toString(),
      'https://academic.niu.edu.tw/var/file/3/1003/img/215/770697857.pdf',
    );
    expect(
      zonghe.source.pdf.toString(),
      'https://academic.niu.edu.tw/var/file/3/1003/img/215/546203924.pdf',
    );
    for (final building in buildings) {
      expect(
        building.source.page.toString(),
        'https://academic.niu.edu.tw/p/412-1003-465.php',
      );
      expect(building.source.revisedOn, '2024/05/23');
    }
  });

  test('locate normalizes timetable text and returns the location', () {
    for (final text in ['教305', '教 305', '教305(電腦教室)', '教　３０５', '教\t3\n05']) {
      final location = CampusBuildingCatalog.locate(text)!;
      expect(location.building, same(jiaose));
      expect(location.floor.id, '3F');
      expect(location.space.name, '教305');
    }
    for (final text in ['綜B101', '綜Ｂ１０１']) {
      expect(CampusBuildingCatalog.locate(text)!.floor.id, 'B1');
    }
    expect(CampusBuildingCatalog.locate('綜合教學大樓 綜203')!.space.name, '綜203');
    expect(CampusBuildingCatalog.locate('教305 綜B101')!.space.name, '綜B101');
    expect(
      CampusBuildingCatalog.locate('原住民族學生資源中心')!.space.kind,
      FloorSpaceKind.venue,
    );
    for (final text in ['', '圖書館', '教999', '樓梯', '行政大樓']) {
      expect(CampusBuildingCatalog.locate(text), isNull);
    }
  });
}
