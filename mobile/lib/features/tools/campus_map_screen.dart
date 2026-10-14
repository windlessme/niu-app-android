import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/shared.dart';
import 'campus_map_data.dart';

/// Buildings with floor plans, and a classroom search across them.
class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key, this.map});
  final Future<CampusMap>? map;
  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  late final Future<CampusMap> map = widget.map ?? CampusMap.load();
  String query = '';

  void open(MapBuilding building, [MapSpace? room]) {
    // The map aims at the room as it opens; let the keyboard go first.
    FocusManager.instance.primaryFocus?.unfocus();
    context.push(campusMapRoute(building.id, room: room?.label));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CampusMap>(
    future: map,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final results = data?.search(query) ?? const <RoomLocation>[];
      return NiuScrollPage(
        title: '校園地圖',
        children: [
          NiuSearchField(
            hint: '搜尋教室，例如 教305',
            onChanged: (v) => setState(() => query = v),
          ),
          if (query.trim().isNotEmpty)
            NiuSection(
              title: '教室',
              child: results.isEmpty
                  ? const NiuCard(child: Text('找不到符合的教室。'))
                  : NiuGroup(
                      children: [
                        for (final r in results.take(30))
                          NiuRow(
                            icon: Icons.meeting_room_outlined,
                            title: r.space.label!,
                            subtitle: [
                              '${r.building.name} ${r.floor.title}',
                              ...r.space.details,
                            ].join('・'),
                            onTap: () => open(r.building, r.space),
                          ),
                      ],
                    ),
            ),
          NiuSection(
            title: '大樓',
            child: data == null
                ? const SizedBox.shrink()
                : NiuGroup(
                    children: [
                      for (final b in data.buildings)
                        NiuRow(
                          icon: Icons.apartment_rounded,
                          hue: NiuHue.indigo,
                          title: b.name,
                          subtitle: b.levels,
                          onTap: () => open(b),
                        ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}

/// Route of a building's floor plan, optionally marking [room].
String campusMapRoute(String building, {String? room}) => Uri(
  path: '/tools/campus-map/$building',
  queryParameters: room == null ? null : {'room': room},
).toString();
