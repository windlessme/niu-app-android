import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'campus_map_data.dart';
import 'floor_map_painter.dart';

/// One building, a floor at a time: the plan fills the page, floors stack on
/// the right as in the building, and tapping a room marks it.
class BuildingMapScreen extends StatelessWidget {
  const BuildingMapScreen({
    super.key,
    required this.buildingId,
    this.room,
    this.map,
  });
  final String buildingId;

  /// A classroom code to open on and mark, e.g. from the timetable.
  final String? room;
  final Future<CampusMap>? map;

  @override
  Widget build(BuildContext context) => FutureBuilder<CampusMap>(
    future: map ?? CampusMap.load(),
    builder: (context, snapshot) {
      final building = snapshot.data?.building(buildingId);
      if (building == null) {
        return Scaffold(
          appBar: const NiuAppBar(title: '校園地圖'),
          body: snapshot.connectionState == ConnectionState.done
              ? const NiuEmpty(title: '找不到這棟大樓')
              : const SizedBox.shrink(),
        );
      }
      final found = room == null ? null : snapshot.data!.locate(room!);
      return _BuildingView(
        building: building,
        initial: found?.building == building ? found : null,
      );
    },
  );
}

class _BuildingView extends StatefulWidget {
  const _BuildingView({required this.building, this.initial});
  final MapBuilding building;
  final RoomLocation? initial;
  @override
  State<_BuildingView> createState() => _BuildingViewState();
}

class _BuildingViewState extends State<_BuildingView> {
  late MapFloor floor =
      widget.initial?.floor ??
      widget.building.floor(widget.building.defaultFloorId)!;
  late MapSpace? selected = widget.initial?.space;
  final zoom = TransformationController();

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  void selectFloor(MapFloor next) {
    if (identical(next, floor)) return;
    setState(() {
      floor = next;
      selected = null;
      zoom.value = Matrix4.identity();
    });
  }

  void tap(Offset canvas, Size size) {
    final point = FloorFrame(widget.building, size).toMetres(canvas);
    final room = floor.roomAt(point);
    setState(() => selected = identical(room, selected) ? null : room);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final building = widget.building;
    final gutter = NiuLayout.gutter(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: NiuAppBar(title: building.name),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, NiuSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 16,
                    color: colors.inkTertiary,
                  ),
                  const SizedBox(width: NiuSpacing.xs),
                  Text(building.levels, style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: NiuSpacing.md),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _plan(context)),
                    const SizedBox(width: NiuSpacing.sm),
                    Center(
                      child: _FloorRail(
                        floors: building.floors,
                        selected: floor,
                        onSelect: selectFloor,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: NiuMotion.duration(context),
                curve: NiuMotion.curve,
                alignment: Alignment.topCenter,
                child: selected == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: NiuSpacing.md),
                        child: _RoomCard(
                          space: selected!,
                          floor: floor,
                          onClose: () => setState(() => selected = null),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plan(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NiuRadius.card),
      child: ColoredBox(
        color: dark ? colors.surface : colors.fill,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return Stack(
              children: [
                InteractiveViewer(
                  transformationController: zoom,
                  minScale: 1,
                  maxScale: 6,
                  child: GestureDetector(
                    onTapUp: (d) => tap(d.localPosition, size),
                    child: Semantics(
                      label: '${widget.building.name}${floor.title}平面圖',
                      child: CustomPaint(
                        size: size,
                        painter: FloorMapPainter(
                          building: widget.building,
                          floor: floor,
                          colors: colors,
                          hues: (
                            restroom: NiuHue.teal.background(context),
                            restroomEdge: NiuHue.teal
                                .foreground(context)
                                .withValues(alpha: .25),
                            terrace: NiuHue.green.background(context),
                          ),
                          textStyle:
                              theme.textTheme.labelSmall ?? const TextStyle(),
                          selected: selected,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: NiuSpacing.md,
                  top: NiuSpacing.md,
                  child: _FloorBadge(floor: floor),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FloorBadge extends StatelessWidget {
  const _FloorBadge({required this.floor});
  final MapFloor floor;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NiuSpacing.md,
        vertical: NiuSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(NiuRadius.md),
        boxShadow: NiuShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(floor.id, style: theme.textTheme.titleLarge),
          Text('${floor.rooms.length} 個空間', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Floors top to bottom as in the building.
class _FloorRail extends StatelessWidget {
  const _FloorRail({
    required this.floors,
    required this.selected,
    required this.onSelect,
  });
  final List<MapFloor> floors;
  final MapFloor selected;
  final ValueChanged<MapFloor> onSelect;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Container(
      width: 52,
      padding: const EdgeInsets.all(NiuSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
        boxShadow: NiuShadow.card(context),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in floors.reversed)
              Semantics(
                button: true,
                selected: identical(f, selected),
                label: f.title,
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSelect(f),
                  child: AnimatedContainer(
                    duration: NiuMotion.duration(context),
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: identical(f, selected) ? colors.accent : null,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      f.id,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: identical(f, selected)
                            ? colors.onAccent
                            : colors.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.space,
    required this.floor,
    required this.onClose,
  });
  final MapSpace space;
  final MapFloor floor;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuCard(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.lg,
        NiuSpacing.md,
        NiuSpacing.xs,
        NiuSpacing.md,
      ),
      child: Row(
        children: [
          const NiuIconTile(
            icon: Icons.meeting_room_outlined,
            hue: NiuHue.blue,
          ),
          const SizedBox(width: NiuSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(space.code ?? '未編號空間', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  [floor.title, ?space.note].join('・'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          NiuIconButton(
            icon: NiuIcons.close,
            tooltip: '取消標示',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
