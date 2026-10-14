import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/shared.dart';
import 'campus_map_data.dart';
import 'campus_overview_data.dart';
import 'campus_overview_painter.dart';
import 'map_controls.dart';

/// The whole campus from above: buildings, paths and fields, with toilets
/// and food on demand. Tapping a building with floor plans opens them.
class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key, this.overview, this.map});
  final Future<CampusOverview>? overview;
  final Future<CampusMap>? map;
  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  late final Future<(CampusOverview, CampusMap)> data = _load();

  Future<(CampusOverview, CampusMap)> _load() async => (
    await (widget.overview ?? CampusOverview.load()),
    await (widget.map ?? CampusMap.load()),
  );

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(CampusOverview, CampusMap)>(
        future: data,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          if (loaded == null) {
            return Scaffold(
              appBar: const NiuAppBar(title: '校園地圖'),
              body: snapshot.hasError
                  ? const NiuEmpty(title: '校園地圖載入失敗')
                  : const SizedBox.shrink(),
            );
          }
          return _CampusView(overview: loaded.$1, rooms: loaded.$2);
        },
      );
}

class _CampusView extends StatefulWidget {
  const _CampusView({required this.overview, required this.rooms});
  final CampusOverview overview;
  final CampusMap rooms;
  @override
  State<_CampusView> createState() => _CampusViewState();
}

class _CampusViewState extends State<_CampusView>
    with SingleTickerProviderStateMixin {
  final zoom = TransformationController();
  late final flight = AnimationController(
    vsync: this,
    duration: NiuMotion.standard,
  );
  Animation<Matrix4>? _flight;
  OverviewFrame? frame;
  CampusBuilding? selected;
  Set<CampusPlaceKind> places = const {};

  /// Buildings as a list instead of the map; remembered between visits.
  bool listed = false;
  static const _listedKey = 'campusMapListed';

  Future<void> _restoreMode() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(_listedKey);
      if (mounted && saved != null && saved != listed) {
        setState(() => listed = saved);
      }
    } catch (_) {}
  }

  void toggleMode() {
    setState(() {
      listed = !listed;
      if (listed) selected = null;
    });
    final value = listed;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_listedKey, value))
        .ignore();
  }

  static const _top = 64.0, _bottom = 64.0;

  @override
  void initState() {
    super.initState();
    _restoreMode();
    flight.addListener(() {
      final a = _flight;
      if (a != null) zoom.value = a.value;
    });
  }

  @override
  void dispose() {
    flight.dispose();
    zoom.dispose();
    super.dispose();
  }

  void fly(Matrix4 target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      zoom.value = target;
      return;
    }
    _flight = Matrix4Tween(
      begin: zoom.value,
      end: target,
    ).animate(CurvedAnimation(parent: flight, curve: Curves.easeInOutCubic));
    flight.forward(from: 0);
  }

  /// Centres [b] at a zoom where its outline is comfortably big.
  void focus(CampusBuilding b) {
    final f = frame;
    if (f == null) return;
    final area = f.padding.deflateRect(Offset.zero & f.size);
    final size = b.bounds.longestSide * f.scale;
    final scale = (area.shortestSide * .45 / size).clamp(1.0, 6.0);
    final at = f.toCanvas(b.centre);
    fly(
      Matrix4.identity()
        ..translateByDouble(
          area.center.dx - at.dx * scale,
          area.center.dy - at.dy * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
    );
  }

  void select(CampusBuilding? b, {bool focusOn = false}) {
    setState(() => selected = b);
    if (b != null && focusOn) focus(b);
  }

  void tap(Offset canvas) {
    final f = frame;
    if (f == null) return;
    final hit = widget.overview.buildingAt(f.toMetres(canvas));
    select(identical(hit, selected) ? null : hit);
  }

  void openPlan(String building, {String? room}) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.push(campusMapRoute(building, room: room));
  }

  Future<void> search() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _SearchSheet(overview: widget.overview, rooms: widget.rooms),
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case CampusBuilding b:
        select(b, focusOn: true);
      case RoomLocation r:
        openPlan(r.building.id, room: r.space.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final media = MediaQuery.of(context);
    final top = media.viewPadding.top + NiuSpacing.sm;
    final bottom = media.viewPadding.bottom + NiuSpacing.md;
    final padding = EdgeInsets.fromLTRB(
      NiuSpacing.md,
      top + _top,
      NiuSpacing.md,
      bottom + _bottom,
    );
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.canvas,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          frame = OverviewFrame(widget.overview, size, padding: padding);
          return Stack(
            children: [
              if (listed)
                Positioned.fill(
                  child: _BuildingList(
                    overview: widget.overview,
                    rooms: widget.rooms,
                    top: top + _top,
                    onOpen: (b) {
                      final plan = b.plan;
                      if (plan != null) {
                        openPlan(plan);
                      } else {
                        setState(() => listed = false);
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => select(b, focusOn: true),
                        );
                      }
                    },
                  ),
                )
              else
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: zoom,
                    minScale: .8,
                    maxScale: 12,
                    boundaryMargin: const EdgeInsets.all(400),
                    onInteractionStart: (_) => flight.stop(),
                    child: GestureDetector(
                      onTapUp: (d) => tap(d.localPosition),
                      child: Semantics(
                        label: '國立宜蘭大學校園地圖',
                        child: CustomPaint(
                          size: size,
                          painter: CampusOverviewPainter(
                            map: widget.overview,
                            colors: colors,
                            hues: (
                              green: NiuHue.green.background(context),
                              sport: NiuHue.green
                                  .foreground(context)
                                  .withValues(alpha: dark ? .26 : .18),
                              water: NiuHue.cyan.background(context),
                              campus: dark
                                  ? colors.surface
                                  : Color.lerp(
                                      colors.surface,
                                      colors.canvas,
                                      .3,
                                    )!,
                              plan: NiuHue.indigo
                                  .foreground(context)
                                  .withValues(alpha: dark ? .45 : .3),
                              planEdge: NiuHue.indigo.foreground(context),
                            ),
                            textStyle:
                                theme.textTheme.labelSmall ?? const TextStyle(),
                            places: places,
                            padding: padding,
                            selected: selected,
                            zoom: zoom,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (listed)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: top + _top - NiuSpacing.sm,
                  child: ColoredBox(color: colors.canvas),
                ),
              Positioned(
                left: NiuSpacing.md,
                right: NiuSpacing.md,
                top: top,
                child: Row(
                  children: [
                    const MapFloating(child: NiuBackButton()),
                    const SizedBox(width: NiuSpacing.sm),
                    Expanded(
                      child: MapFloating(
                        child: Semantics(
                          button: true,
                          label: '搜尋建築或教室',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: search,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NiuSpacing.lg,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    NiuIcons.search,
                                    size: 20,
                                    color: colors.inkTertiary,
                                  ),
                                  const SizedBox(width: NiuSpacing.sm),
                                  Text(
                                    '搜尋建築、教室',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.inkTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    MapFloating(
                      child: NiuIconButton(
                        icon: listed
                            ? Icons.map_rounded
                            : Icons.view_list_rounded,
                        tooltip: listed ? '以地圖顯示' : '以清單顯示',
                        onPressed: toggleMode,
                      ),
                    ),
                  ],
                ),
              ),
              if (!listed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom,
                  child: AnimatedSwitcher(
                    duration: NiuMotion.duration(context),
                    child: selected == null
                        ? _Controls(
                            key: const ValueKey('controls'),
                            places: places,
                            attribution: widget.overview.attribution,
                            onToggle: (kind) => setState(() {
                              places = places.contains(kind)
                                  ? ({...places}..remove(kind))
                                  : {...places, kind};
                            }),
                            onFit: () => fly(Matrix4.identity()),
                          )
                        : Padding(
                            key: ValueKey(selected!.id),
                            padding: const EdgeInsets.symmetric(
                              horizontal: NiuSpacing.md,
                            ),
                            child: _BuildingCard(
                              building: selected!,
                              levels: selected!.plan == null
                                  ? null
                                  : widget.rooms
                                        .building(selected!.plan!)
                                        ?.levels,
                              onClose: () => select(null),
                              onPlan: selected!.plan == null
                                  ? null
                                  : () => openPlan(selected!.plan!),
                            ),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The campus buildings by name: those with floor plans first.
class _BuildingList extends StatelessWidget {
  const _BuildingList({
    required this.overview,
    required this.rooms,
    required this.top,
    required this.onOpen,
  });
  final CampusOverview overview;
  final CampusMap rooms;
  final double top;
  final ValueChanged<CampusBuilding> onOpen;

  @override
  Widget build(BuildContext context) {
    // One row per name; the map has two 看台, for one.
    final seen = <String>{};
    final named = [
      for (final b in overview.buildings)
        if (b.onCampus && b.name != null && seen.add(b.name!)) b,
    ]..sort((a, b) => a.name!.compareTo(b.name!));
    final planned = [
      for (final b in named)
        if (b.plan != null) b,
    ];
    final others = [
      for (final b in named)
        if (b.plan == null) b,
    ];
    String? levels(CampusBuilding b) {
      final plan = b.plan == null ? null : rooms.building(b.plan!);
      return plan?.levels ?? (b.levels == null ? null : '地上 ${b.levels} 層');
    }

    Widget group(List<CampusBuilding> list) => NiuGroup(
      children: [
        for (final b in list)
          NiuRow(
            icon: Icons.apartment_rounded,
            hue: b.plan == null ? NiuHue.gray : NiuHue.indigo,
            title: b.name!,
            subtitle: levels(b),
            onTap: () => onOpen(b),
          ),
      ],
    );

    return ListView(
      padding: NiuLayout.page(
        context,
        top: top + NiuSpacing.md,
        bottom: MediaQuery.viewPaddingOf(context).bottom + NiuSpacing.xxl,
      ),
      children: [
        if (planned.isNotEmpty)
          NiuSection(first: true, title: '有樓層平面圖', child: group(planned)),
        if (others.isNotEmpty)
          NiuSection(
            first: planned.isEmpty,
            title: '其他建築',
            child: group(others),
          ),
        const SizedBox(height: NiuSpacing.lg),
        Text(
          overview.attribution,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: NiuColors.of(context).inkTertiary,
          ),
        ),
      ],
    );
  }
}

/// Filters on the left, whole-campus and the map credit on the right.
class _Controls extends StatelessWidget {
  const _Controls({
    super.key,
    required this.places,
    required this.attribution,
    required this.onToggle,
    required this.onFit,
  });
  final Set<CampusPlaceKind> places;
  final String attribution;
  final ValueChanged<CampusPlaceKind> onToggle;
  final VoidCallback onFit;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: NiuSpacing.md),
          child: Align(
            alignment: Alignment.centerRight,
            child: MapFloating(
              child: NiuIconButton(
                icon: Icons.fit_screen_rounded,
                tooltip: '顯示整個校園',
                onPressed: onFit,
              ),
            ),
          ),
        ),
        const SizedBox(height: NiuSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.md),
          child: Row(
            children: [
              for (final kind in CampusPlaceKind.values) ...[
                MapFloating(
                  child: Semantics(
                    button: true,
                    selected: places.contains(kind),
                    child: InkWell(
                      onTap: () => onToggle(kind),
                      child: AnimatedContainer(
                        duration: NiuMotion.duration(context),
                        color: places.contains(kind) ? colors.accent : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CampusOverviewPainter.icon(kind),
                              size: 18,
                              color: places.contains(kind)
                                  ? colors.onAccent
                                  : colors.ink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              kind.title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: places.contains(kind)
                                    ? colors.onAccent
                                    : colors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: NiuSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: NiuSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(right: NiuSpacing.md),
          child: Text(
            attribution,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.inkTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.building,
    required this.onClose,
    this.levels,
    this.onPlan,
  });
  final CampusBuilding building;

  /// The floor plans' own count, e.g. 地上 8 層, over the map's.
  final String? levels;
  final VoidCallback onClose;
  final VoidCallback? onPlan;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levels =
        this.levels ??
        (building.levels == null ? null : '地上 ${building.levels} 層');
    return NiuCard(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.lg,
        NiuSpacing.md,
        NiuSpacing.xs,
        NiuSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              NiuIconTile(
                icon: Icons.apartment_rounded,
                hue: onPlan == null ? NiuHue.gray : NiuHue.indigo,
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      building.name ?? '未命名建築',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      [
                        ?levels,
                        onPlan == null ? '尚無樓層平面圖' : '有樓層平面圖',
                      ].join('・'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              NiuIconButton(
                icon: NiuIcons.close,
                tooltip: '關閉',
                onPressed: onClose,
              ),
            ],
          ),
          if (onPlan != null) ...[
            const SizedBox(height: NiuSpacing.md),
            Padding(
              padding: const EdgeInsets.only(right: NiuSpacing.md),
              child: FilledButton.icon(
                onPressed: onPlan,
                icon: const Icon(Icons.layers_rounded),
                label: const Text('查看樓層平面圖'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Buildings and classrooms; returns a [CampusBuilding] or [RoomLocation].
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.overview, required this.rooms});
  final CampusOverview overview;
  final CampusMap rooms;
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String query = '';

  void pick(Object result) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final buildings = widget.overview.searchBuildings(query);
    final rooms = widget.rooms.search(query);
    final empty = query.trim().isNotEmpty && buildings.isEmpty && rooms.isEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: math.max(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      child: SizedBox(
        height: media.size.height * .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NiuSpacing.gutter,
                NiuSpacing.lg,
                NiuSpacing.gutter,
                NiuSpacing.sm,
              ),
              child: NiuSearchField(
                hint: '搜尋建築、教室，例如 教305',
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  NiuSpacing.gutter,
                  0,
                  NiuSpacing.gutter,
                  NiuSpacing.lg,
                ),
                children: [
                  if (empty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: NiuSpacing.lg),
                      child: Text('找不到符合的建築或教室。'),
                    ),
                  for (final b in buildings)
                    NiuRow(
                      icon: Icons.apartment_rounded,
                      hue: b.plan == null ? NiuHue.gray : NiuHue.indigo,
                      title: b.name!,
                      subtitle: b.levels == null ? null : '地上 ${b.levels} 層',
                      onTap: () => pick(b),
                    ),
                  for (final r in rooms.take(30))
                    NiuRow(
                      icon: Icons.meeting_room_outlined,
                      title: r.space.label!,
                      subtitle: [
                        '${r.building.name} ${r.floor.title}',
                        ...r.space.details,
                      ].join('・'),
                      onTap: () => pick(r),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Route of a building's floor plan, optionally marking [room].
String campusMapRoute(String building, {String? room}) => Uri(
  path: '/tools/campus-map/$building',
  queryParameters: room == null ? null : {'room': room},
).toString();
