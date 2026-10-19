import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:niu_mobile/features/tools/building_map_screen.dart';
import 'package:niu_mobile/features/tools/campus_map_data.dart';
import 'package:niu_mobile/features/tools/campus_map_screen.dart';
import 'package:niu_mobile/features/tools/campus_overview_data.dart';
import 'package:niu_mobile/features/tools/campus_overview_painter.dart';
import 'package:niu_mobile/features/tools/floor_map_painter.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampusMap map;
  late CampusOverview overview;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    map = await CampusMap.load(rootBundle);
    overview = await CampusOverview.load(rootBundle);
  });

  test('the overview holds the campus and its buildings', () {
    expect(overview.boundary, isNotEmpty);
    final jiaose = overview.withPlan('jiaose')!;
    expect(jiaose.name, '教穡大樓');
    expect(identical(overview.buildingAt(jiaose.centre), jiaose), isTrue);
    expect(overview.searchBuildings('綜合').single.name, '綜合教學大樓');
    // 復興國中 next door is not ours.
    expect(overview.searchBuildings('群育館'), isEmpty);
    expect(overview.searchBuildings('體育館'), isNotEmpty);
    // Mapped as a multipolygon in OpenStreetMap.
    expect(overview.searchBuildings('紅樓').single.onCampus, isTrue);
    // 司令台 stays on the map and in search, out of the list.
    expect(overview.searchBuildings('司令台').single.listed, isFalse);
    expect(CampusOverviewPainter.mapName('格致大樓（電資學院）'), '格致大樓\n電資學院');
    expect(CampusOverviewPainter.mapName('教穡大樓'), '教穡大樓');
    final frame = OverviewFrame(overview, const Size(390, 700));
    final at = frame.toCanvas(jiaose.centre);
    expect((frame.toMetres(at) - jiaose.centre).distance, lessThan(1e-6));
  });

  test('教穡大樓 has eight floors with the office codes on 1F–4F', () {
    final b = map.building('jiaose')!;
    expect(b.floors.map((f) => f.id), [
      '1F',
      '2F',
      '3F',
      '4F',
      '5F',
      '6F',
      '7F',
      '8F',
    ]);
    expect(b.levels, '地上 8 層');
    expect(b.defaultFloorId, '1F');
    int coded(String id) =>
        b.floor(id)!.rooms.where((r) => r.code != null).length;
    expect(
      [coded('1F'), coded('2F'), coded('3F'), coded('4F')],
      [10, 10, 12, 12],
    );
    expect(b.floor('3F')!.title, '3 樓');
  });

  test('5F–8F carry the signs\' names and the marked numbers', () {
    final b = map.building('jiaose')!;
    MapSpace? find(String floor, String label) =>
        b.floor(floor)!.rooms.where((r) => r.label == label).firstOrNull;
    expect(find('5F', '教515東')!.name, '薄膜實驗室');
    expect(find('7F', '教705')!.name, '商業營運模擬中心');
    expect(find('7F', '教712-1')!.name, isNull);
    expect(find('6F', '教622')!.details, isEmpty);
    expect(find('8F', '智慧休閒農業進修學士學位學程辦公室')!.code, isNull);
    for (final f in b.floors) {
      final toilets = [
        for (final s in f.spaces)
          if (s.kind == MapSpaceKind.restroom) s.name,
      ];
      expect(toilets, containsAll(['男廁', '女廁']), reason: f.id);
    }
    expect(map.search('薄膜').single.space.code, '教515東');
    expect(map.search('學程辦公室').single.floor.id, '8F');
    expect(map.locate('教712-1')!.floor.id, '7F');
    expect(find('8F', '國際會議廳'), isNotNull);
    expect(find('5F', '教511南')!.name, '模擬及性質分析實驗室');
    expect(find('6F', '教610'), isNotNull);
    final link = b.floor('1F')!.links.single;
    expect((link.to, link.name), ('zonghe', '綜合教學大樓'));
  });

  test('locate reads timetable text', () {
    final hit = map.locate('教 305（普通教室）')!;
    expect(hit.floor.id, '3F');
    expect(hit.space.code, '教305');
    expect(map.locate('教３１１')!.space.note, '職涯教育專業教室');
    expect(map.locate('綜503'), isNull);
    expect(map.locate(''), isNull);
  });

  test('工學院大樓 has B1 to 6F with 工 codes', () {
    final b = map.building('gongxue')!;
    expect(b.floors.map((f) => f.id), [
      'B1',
      '1F',
      '2F',
      '3F',
      '4F',
      '5F',
      '6F',
    ]);
    expect(b.levels, '地上 6 層，地下 1 層');
    expect(b.defaultFloorId, '1F');
    expect(map.locate('工B07')!.space.name, '單元操作實驗室');
    expect(map.locate('工 423')!.floor.id, '4F');
    expect(map.search('結構工程').single.space.code, '工228');
    expect(b.floor('5F')!.unit, '環境工程學系');
    expect(map.search('環工').map((r) => r.space.code), [
      '工513',
      '工515',
      '工516',
      '工516-1',
    ]);
    expect(map.search('機械系').map((r) => r.space.code), contains('工301'));
    expect(map.search('化學工程').map((r) => r.space.code), [
      '工605',
      '工603',
      '工601',
    ]);
    expect(map.locate('工513')!.space.details, ['系辦公室', '環境工程學系']);
    expect(overview.withPlan('gongxue')!.name, '工學院大樓');
  });

  test('時習大樓 and 電資二館 have their own codes', () {
    expect(map.building('shixi')!.levels, '地上 5 層');
    expect(map.building('dianzi')!.levels, '地上 4 層');
    expect(map.locate('資 204')!.space.name, '電腦教室');
    expect(map.locate('時507')!.floor.id, '5F');
    expect(overview.withPlan('dianzi')!.name, '電資二館');
    expect(overview.searchBuildings('電資學院').single.name, '格致大樓（電資學院）');
    final bridge = map.building('dianzi')!.floor('2F')!.links.single;
    expect(bridge.toward, const Offset(0, -1)); // north, to 格致大樓
    expect(overview.withPlan('shixi')!.name, '時習大樓');
    // 時化學舍: room numbers as the dorm's directory gives them.
    expect(map.locate('3C17')!.floor.id, '3F');
    expect(map.locate('1C17'), isNull);
    expect(map.locate('資205')!.space.name, '系主任辦公室');
    expect(map.search('資205').map((r) => r.space.name), [
      '系主任辦公室',
      '會議室',
      '系辦公室',
    ]);
  });

  test('格致大樓 shows 電 codes and finds the signs\' E and 格 codes', () {
    expect(map.building('gezhi')!.levels, '地上 6 層');
    final e505 = map.locate('電516')!;
    expect(e505.space.name, '系辦公室');
    expect(e505.space.details, ['系辦公室', '電子工程學系']);
    // The sign's code finds it too, and the shown label stays 電516.
    expect(map.search('E505').map((r) => r.space.label), contains('電516'));
    expect(map.locate('E411')!.space.label, '電402');
    expect(map.locate('格106')!.space.label, '電111');
    // A room the user didn't number shows the sign's code, kept whole.
    final e607 = map.locate('E607')!.space;
    expect(e607.label, 'E607');
    expect(e607.shortCode, isNull);
    expect(map.locate('電205')!.space.shortCode, '205');
    expect(map.search('電機系').map((r) => r.space.label), contains('電205'));
    final bridge = map.building('gezhi')!.floor('2F')!.links.single;
    expect(bridge.to, 'dianzi');
  });

  test('綜合教學大樓 has its 綜 classrooms and the 3F corridor', () {
    final b = map.building('zonghe')!;
    expect(b.levels, '地上 4 層');
    expect(map.locate('綜303-1')!.floor.id, '3F');
    // The wings are separate rings; 3F's corridor makes one.
    expect(b.floor('2F')!.outlines, hasLength(2));
    expect(b.floor('3F')!.outlines, hasLength(1));
    expect(map.locate('綜 101（教室）')!.space.code, '綜101');
    expect(overview.withPlan('zonghe')!.name, '綜合教學大樓');
  });

  test('圖書資訊中心 and 實驗動物中心 have plans', () {
    final tuzi = map.building('tuzi')!;
    expect(tuzi.levels, '地上 7 層，地下 1 層');
    // The north-west wing only its own entrance on 1F reaches.
    final first = tuzi.floor('1F')!;
    expect(first.zones.map((z) => z.name), ['獨立區域', '行政區域']);
    expect(first.zones.first.entrance!.text, '獨立入口');
    final fourth = tuzi.floor('4F')!;
    expect(
      fourth
          .zoneOf(fourth.rooms.firstWhere((r) => r.name == '417 館長室'))!
          .description,
      '獨立區域，由 1 樓獨立入口進出',
    );
    expect(
      fourth.zoneOf(fourth.rooms.firstWhere((r) => r.name == '410 工作準備室')),
      isNull,
    );
    expect(
      map.search('523').where((r) => r.building.id == 'tuzi').single.space.name,
      '523 討論室',
    );
    expect(map.search('電腦教室一').single.space.code, isNull);
    expect(map.search('電算中心').map((r) => r.space.label), contains('電算中心辦公室'));
    expect(map.search('西文圖書區'), hasLength(1));
    expect(map.search('企業培育室').map((r) => r.floor.id).toSet(), {'B1'});
    expect(map.building('dongwu')!.levels, '地上 2 層');
    expect(overview.withPlan('tuzi')!.name, '圖書資訊中心（圖書館）');
    expect(overview.searchBuildings('圖書館').single.plan, 'tuzi');
    expect(overview.withPlan('dongwu')!.name, '實驗動物中心');
  });

  test('the seven buildings drawn on 2026-10-15 have plans', () {
    const levels = {
      'huodong': '地上 5 層',
      'yuyan': '地上 2 層',
      'tongshi': '地上 2 層',
      'xingzheng': '地上 5 層',
      'tiyu': '地上 4 層，地下 1 層',
      'jingde': '地上 7 層',
      'shengzi': '地上 8 層',
      'shipin': '地上 3 層',
    };
    for (final MapEntry(key: id, value: text) in levels.entries) {
      expect(map.building(id)!.levels, text, reason: id);
      expect(overview.withPlan(id), isNotNull, reason: id);
    }
    expect(map.search('求101').single.space.name, '通識教育中心辦公室');
    expect(map.search('LC204').single.space.name, '會議室');
    expect(map.search('校長室').map((r) => r.building.id), contains('xingzheng'));
  });

  test('人文管理學院及外文系 has 1F–4F, rooms numbered in their names', () {
    expect(map.building('renguan')!.levels, '地上 4 層');
    expect(overview.withPlan('renguan'), isNotNull);
    expect(map.search('103').map((r) => r.space.name), contains('103 階梯教室'));
    // Offices noted with the department are found by its short name.
    expect(
      map.search('外文系').map((r) => r.space.name),
      containsAll(['201 外國語文學系辦公室', '400 外國語文學系教學助理工作室']),
    );
    expect(map.search('院長').map((r) => r.floor.id), contains('3F'));
    // The school codes only five rooms, each its own way.
    for (final (text, room) in [
      ('語 101', '101 外國語文學系專業教室（一）'),
      ('語102', '102 外國語文學系專業教室（二）'),
      ('人管階梯教室', '103 階梯教室'),
      ('人文308', '308 外國語文學系會議室'),
      ('人文 402', '402'),
    ]) {
      expect(map.locate(text)?.space.name, room, reason: text);
    }
  });

  test('search matches codes, bare numbers and notes', () {
    expect(map.search('305').map((r) => r.space.label), [
      '教305',
      '工305',
      '資305',
      '電317', // E305 on the sign
      '電305',
      '綜305',
      // 生資大樓 and 學生活動中心 put the number in the name.
      '305 蛋白質純化實驗室',
      '305 社團辦公室',
      '305 課業輔導室',
    ]);
    expect(map.search('外語').map((r) => r.space.code), ['教401', '教412']);
    expect(map.search(' '), isEmpty);
  });

  test('a room is found under its own centre on screen', () {
    final b = map.building('jiaose')!;
    final room = map.locate('教305')!.space;
    for (final size in const [Size(300, 640), Size(800, 500)]) {
      final frame = FloorFrame(b, size);
      expect(frame.rotated, size.height > size.width);
      final onScreen = frame.toCanvas(room.bounds.center);
      expect(
        identical(b.floor('3F')!.roomAt(frame.toMetres(onScreen)), room),
        isTrue,
      );
    }
  });

  Widget app(Widget child) => MaterialApp(theme: NiuTheme.light, home: child);

  testWidgets('opens on a timetable room; floors fold away', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        BuildingMapScreen(
          buildingId: 'jiaose',
          room: '教305',
          map: SynchronousFuture(map),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('教穡大樓'), findsOneWidget);
    expect(find.bySemanticsLabel('樓層，目前3 樓'), findsOneWidget);
    expect(find.bySemanticsLabel('8 樓'), findsNothing);
    expect(find.text('3 樓・普通教室'), findsNothing);
    expect(find.text('教305'), findsWidgets);
    expect(find.byTooltip('取消標示'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('樓層，目前3 樓'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('8 樓'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('樓層，目前8 樓'), findsOneWidget);
    expect(find.byTooltip('取消標示'), findsNothing);
    expect(find.textContaining('間有編號'), findsNothing);
  });

  testWidgets('picking a room in the drawer marks it', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(BuildingMapScreen(buildingId: 'jiaose', map: SynchronousFuture(map))),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 樓'), findsOneWidget);
    await tester.drag(find.text('1 樓'), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('學生休息室'));
    await tester.pumpAndSettle();
    expect(find.text('1 樓・學生休息室'), findsOneWidget);
  });

  testWidgets('a room picked low in the list never pins the drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        BuildingMapScreen(buildingId: 'gongxue', map: SynchronousFuture(map)),
      ),
    );
    await tester.pumpAndSettle();
    final sheet = find.byType(DraggableScrollableSheet);
    // How far the drawer reaches up from the bottom of the screen.
    double height() =>
        844 -
        tester
            .getTopLeft(
              find
                  .descendant(of: sheet, matching: find.byType(DecoratedBox))
                  .first,
            )
            .dy;
    final closed = height();

    // Open the drawer, scroll the list well down, pick a room there.
    await tester.drag(find.text('1 樓'), const Offset(0, -400));
    await tester.pumpAndSettle();
    final open = height();
    expect(open, greaterThan(closed + 200));
    await tester.scrollUntilVisible(
      find.text('工115'),
      200,
      scrollable: find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('工113'));
    await tester.pumpAndSettle();
    expect(height(), closed);
    expect(find.text('1 樓・碩專班研討室一'), findsOneWidget);

    // The header still opens and closes it by drag or tap.
    await tester.drag(find.text('工113').first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(height(), open);
    await tester.drag(find.text('1 樓・碩專班研討室一'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(height(), closed);
    await tester.tap(find.text('1 樓・碩專班研討室一'));
    await tester.pumpAndSettle();
    expect(height(), open);
  });

  testWidgets('a link on an outside wall stays on screen', (tester) async {
    final b = map.building('gongxue')!;
    const size = Size(390, 844);
    final frame = FloorFrame(b, size, padding: const EdgeInsets.all(16));
    final link = b.floor('4F')!.links.single;
    // The pill grows inwards from the doorway on the east wall.
    expect(
      frame.toCanvas(link.at).dx,
      lessThanOrEqualTo(size.width - 16 + .01),
    );
  });

  testWidgets('a room opened as the keyboard closes is still centred', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        BuildingMapScreen(
          buildingId: 'jiaose',
          room: '教511南',
          map: SynchronousFuture(map),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    final b = map.building('jiaose')!;
    const size = Size(390, 844);
    const padding = EdgeInsets.fromLTRB(16, 47 + 8 + 64, 16, 112 + 34 + 16);
    final frame = FloorFrame(b, size, padding: padding);
    final room = map.locate('教511南')!.space;
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    final onScreen = MatrixUtils.transformPoint(
      zoom,
      frame.toCanvas(room.bounds.center),
    );
    final centre = padding.deflateRect(Offset.zero & size).center;
    expect((onScreen - centre).distance, lessThan(1));
  });

  testWidgets('the overview switches to a list and back', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        CampusMapScreen(
          overview: SynchronousFuture(overview),
          map: SynchronousFuture(map),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('以清單顯示'));
    await tester.pumpAndSettle();
    expect(find.text('有樓層平面圖'), findsOneWidget);
    expect(find.text('教穡大樓'), findsOneWidget);
    expect(find.text('地上 8 層'), findsWidgets);
    expect(
      (await SharedPreferences.getInstance()).getBool('campusMapListed'),
      isTrue,
    );
    await tester.scrollUntilVisible(find.text('教師宿舍'), 200);
    expect(find.text('司令台'), findsNothing);
    await Scrollable.ensureVisible(
      tester.element(find.text('教師宿舍')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('教師宿舍'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('以清單顯示'), findsOneWidget);
    expect(find.text('地上 3 層・尚無樓層平面圖'), findsOneWidget);
  });

  testWidgets('the overview finds buildings and rooms and opens plans', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        CampusMapScreen(
          overview: SynchronousFuture(overview),
          map: SynchronousFuture(map),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('© OpenStreetMap 貢獻者'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('搜尋建築或教室'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '412');
    await tester.pumpAndSettle();
    expect(find.text('教412'), findsOneWidget);
    expect(find.text('教穡大樓 4 樓・外語學系優先排課'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '教穡');
    await tester.pumpAndSettle();
    await tester.tap(find.text('教穡大樓'));
    await tester.pumpAndSettle();
    expect(find.text('地上 8 層・有樓層平面圖'), findsOneWidget);
    expect(find.text('查看樓層平面圖'), findsOneWidget);
  });
}
