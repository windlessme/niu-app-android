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
    expect(
      overview.places.where((p) => p.kind == CampusPlaceKind.toilets),
      isNotEmpty,
    );
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
    expect(map.locate('綜203'), isNull);
    expect(map.locate(''), isNull);
  });

  test('search matches codes, bare numbers and notes', () {
    expect(map.search('305').single.space.code, '教305');
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
    expect(find.textContaining('4 間有編號'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('綜合教學大樓'), 200);
    await Scrollable.ensureVisible(
      tester.element(find.text('綜合教學大樓')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('綜合教學大樓'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('以清單顯示'), findsOneWidget);
    expect(find.text('地上 4 層・尚無樓層平面圖'), findsOneWidget);
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
