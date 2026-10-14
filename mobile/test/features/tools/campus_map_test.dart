import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/tools/building_map_screen.dart';
import 'package:niu_mobile/features/tools/campus_map_data.dart';
import 'package:niu_mobile/features/tools/campus_map_screen.dart';
import 'package:niu_mobile/features/tools/floor_map_painter.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampusMap map;
  setUpAll(() async => map = await CampusMap.load(rootBundle));

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

  testWidgets('searching a room lists where it is', (tester) async {
    await tester.pumpWidget(app(CampusMapScreen(map: SynchronousFuture(map))));
    await tester.pumpAndSettle();
    expect(find.text('教穡大樓'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '412');
    await tester.pumpAndSettle();
    expect(find.text('教412'), findsOneWidget);
    expect(find.text('教穡大樓 4 樓・外語學系優先排課'), findsOneWidget);
  });
}
