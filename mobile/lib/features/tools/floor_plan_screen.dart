import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../shared/shared.dart';
import 'floor_plan_data.dart';

/// Classroom positions per building and floor, drawn as a relative grid from
/// the academic office's PDFs. Opening with [room] jumps to and marks it.
class FloorPlanScreen extends StatefulWidget {
  const FloorPlanScreen({super.key, this.room});
  final String? room;
  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen> {
  static final buildings = CampusBuildingCatalog.buildings;
  late CampusBuilding building;
  late String floorId;
  String? marked;

  @override
  void initState() {
    super.initState();
    final found = widget.room == null
        ? null
        : CampusBuildingCatalog.locate(widget.room!);
    building = found?.building ?? buildings.first;
    floorId = found?.floor.id ?? building.defaultFloorId;
    marked = found?.space.id;
  }

  BuildingFloor get floor => building.floor(floorId)!;

  void selectBuilding(CampusBuilding next) {
    if (next.id == building.id) return;
    setState(() {
      building = next;
      floorId = next.defaultFloorId;
      marked = null;
    });
  }

  void selectFloor(String id) {
    if (id == floorId) return;
    setState(() {
      floorId = id;
      marked = null;
    });
  }

  void toggle(FloorSpace space) {
    if (!space.isRoom) return;
    setState(() => marked = marked == space.id ? null : space.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final floor = this.floor;
    final source = building.source;
    return NiuScrollPage(
      title: '大樓平面圖',
      children: [
        NiuSegmented<CampusBuilding>(
          segments: [for (final b in buildings) (b, b.name)],
          value: building,
          onChanged: selectBuilding,
        ),
        const SizedBox(height: NiuSpacing.sm),
        NiuSegmented<String>(
          segments: [for (final f in building.floors) (f.id, f.id)],
          value: floorId,
          onChanged: selectFloor,
        ),
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(
          padding: const EdgeInsets.symmetric(vertical: NiuSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '${building.name} ${floor.title}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        '可左右滑動',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.inkTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NiuSpacing.md),
              _FloorGrid(
                key: ValueKey('${building.id}/${floor.id}'),
                floor: floor,
                marked: marked,
                onSelect: toggle,
              ),
              const SizedBox(height: NiuSpacing.md),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: NiuSpacing.lg),
                child: _Legend(),
              ),
            ],
          ),
        ),
        NiuSection(
          title: '本層教室與場館',
          child: floor.rooms.isEmpty
              ? const NiuCard(child: Text('這一層沒有編號教室。'))
              : NiuGroup(
                  insetDividers: NiuSpacing.lg,
                  children: [
                    for (final space in floor.rooms)
                      Semantics(
                        selected: marked == space.id,
                        hint: marked == space.id ? '取消標示' : '在平面圖上標示',
                        child: NiuRow(
                          title: space.name,
                          subtitle: space.note,
                          chevron: false,
                          onTap: () => toggle(space),
                          trailing: marked == space.id
                              ? Icon(Icons.place_rounded, color: colors.accent)
                              : null,
                        ),
                      ),
                  ],
                ),
        ),
        NiuSection(
          title: '校方原圖',
          child: NiuGroup(
            children: [
              NiuRow(
                icon: NiuIcons.file,
                hue: NiuHue.indigo,
                title: '${building.name}教室位置圖',
                value: source.revisedOn,
                onTap: () => openPublicUrl(context, source.pdf),
              ),
              NiuRow(
                icon: NiuIcons.link,
                hue: NiuHue.gray,
                title: '教務處教室平面圖頁',
                onTap: () => openPublicUrl(context, source.page),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One floor as rows of cells; scrolls sideways and brings the marked room
/// into view.
class _FloorGrid extends StatefulWidget {
  const _FloorGrid({
    super.key,
    required this.floor,
    required this.marked,
    required this.onSelect,
  });
  final BuildingFloor floor;
  final String? marked;
  final ValueChanged<FloorSpace> onSelect;
  @override
  State<_FloorGrid> createState() => _FloorGridState();
}

class _FloorGridState extends State<_FloorGrid> {
  static const gap = 4.0;
  final keys = <String, GlobalKey>{};
  final scroll = ScrollController();

  GlobalKey keyFor(String id) => keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    if (widget.marked != null) reveal(animate: false);
  }

  @override
  void didUpdateWidget(_FloorGrid old) {
    super.didUpdateWidget(old);
    if (widget.marked != null && widget.marked != old.marked) reveal();
  }

  /// Centres the marked room sideways only, so tapping the room list
  /// doesn't jump the page.
  void reveal({bool animate = true}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = keys[widget.marked]?.currentContext?.findRenderObject();
        if (box == null || !scroll.hasClients) return;
        final position = scroll.position;
        final offset = RenderAbstractViewport.of(box)
            .getOffsetToReveal(box, .5)
            .offset
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (!animate || !mounted || MediaQuery.disableAnimationsOf(context)) {
          scroll.jumpTo(offset);
        } else {
          scroll.animateTo(
            offset,
            duration: NiuMotion.standard,
            curve: NiuMotion.curve,
          );
        }
      });

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final unit = scaler.scale(60).clamp(60, 96).toDouble();
    final height = scaler.scale(52).clamp(52, 84).toDouble();
    return SingleChildScrollView(
      controller: scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, row) in widget.floor.rows.indexed) ...[
            if (i > 0) const SizedBox(height: gap),
            Row(
              children: [
                for (final (j, space) in row.indexed) ...[
                  if (j > 0) const SizedBox(width: gap),
                  SizedBox(
                    key: space.isRoom ? keyFor(space.id) : null,
                    width: unit * space.span + gap * (space.span - 1),
                    height: row.every(_isOpen) ? height * .45 : height,
                    child: _cell(space),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  static bool _isOpen(FloorSpace s) =>
      s.kind == FloorSpaceKind.gap || s.kind == FloorSpaceKind.passage;

  Widget _cell(FloorSpace space) {
    if (space.kind == FloorSpaceKind.gap) return const SizedBox.shrink();
    if (!space.isRoom) {
      return Semantics(
        label: space.kind == FloorSpaceKind.external
            ? '相鄰建物，${space.name}'
            : space.name,
        excludeSemantics: true,
        child: _SpaceTile(space: space, marked: false),
      );
    }
    final marked = widget.marked == space.id;
    final kind = space.kind == FloorSpaceKind.classroom ? '教室' : '場館';
    return Semantics(
      button: true,
      selected: marked,
      label: [space.name, '${widget.floor.title}$kind', ?space.note].join('，'),
      hint: marked ? '取消標示' : '標示這個位置',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => widget.onSelect(space),
        child: _SpaceTile(space: space, marked: marked),
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({required this.space, required this.marked});
  final FloorSpace space;
  final bool marked;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final style = _SpaceStyle.of(context, space.kind, marked: marked);
    final room = space.isRoom;
    return AnimatedContainer(
      duration: NiuMotion.duration(context),
      curve: NiuMotion.curve,
      foregroundDecoration: style.dashed
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(NiuRadius.xs),
              border: style.stroke == null
                  ? null
                  : Border.all(color: style.stroke!, width: marked ? 2 : 1),
            ),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(NiuRadius.xs),
      ),
      child: CustomPaint(
        painter: style.dashed ? _DashedBorder(style.stroke!) : null,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  space.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (room
                              ? theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )
                              : theme.textTheme.labelSmall)
                          ?.copyWith(
                            color: marked
                                ? colors.onAccent
                                : room
                                ? colors.ink
                                : colors.inkSecondary,
                          ),
                ),
              ),
            ),
            if (space.note != null)
              Positioned(
                top: 5,
                right: 5,
                child: _Dot(
                  color: marked
                      ? colors.onAccent
                      : NiuHue.orange.foreground(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fill and outline per kind; shared by the grid and its legend.
class _SpaceStyle {
  const _SpaceStyle(this.fill, this.stroke, {this.dashed = false});
  final Color? fill;
  final Color? stroke;
  final bool dashed;

  static _SpaceStyle of(
    BuildContext context,
    FloorSpaceKind kind, {
    bool marked = false,
  }) {
    final colors = NiuColors.of(context);
    if (marked) return _SpaceStyle(colors.accent, colors.accent);
    final venue = NiuHue.indigo.foreground(context);
    return switch (kind) {
      FloorSpaceKind.classroom => _SpaceStyle(
        colors.accentSoft,
        colors.accent.withValues(alpha: .4),
      ),
      FloorSpaceKind.venue => _SpaceStyle(
        NiuHue.indigo.background(context),
        venue.withValues(alpha: .35),
      ),
      FloorSpaceKind.utility => _SpaceStyle(colors.fillStrong, null),
      FloorSpaceKind.passage || FloorSpaceKind.external => _SpaceStyle(
        null,
        colors.hairline,
        dashed: true,
      ),
      FloorSpaceKind.gap => const _SpaceStyle(null, null),
    };
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color, {this.dash = 3});
  final Color color;
  final double dash;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          const Radius.circular(NiuRadius.xs),
        ),
      );
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash * 2) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.dash != dash;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget swatch(String label, FloorSpaceKind kind) {
      final style = _SpaceStyle.of(context, kind);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.fill,
                borderRadius: BorderRadius.circular(3),
                border: style.stroke == null || style.dashed
                    ? null
                    : Border.all(color: style.stroke!),
              ),
              child: style.dashed
                  ? CustomPaint(painter: _DashedBorder(style.stroke!, dash: 2))
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      );
    }

    return MergeSemantics(
      child: Wrap(
        spacing: NiuSpacing.md,
        runSpacing: NiuSpacing.xs,
        children: [
          swatch('教室', FloorSpaceKind.classroom),
          swatch('場館', FloorSpaceKind.venue),
          swatch('樓梯・廁所', FloorSpaceKind.utility),
          swatch('通道・相鄰建物', FloorSpaceKind.passage),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: NiuHue.orange.foreground(context)),
              const SizedBox(width: 4),
              Text('有使用備註', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
