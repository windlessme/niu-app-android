import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'campus_map_data.dart';
import 'floor_map_painter.dart';
import 'map_controls.dart';

/// One building, a floor at a time: the plan fills the screen, controls
/// float over it, and a drawer at the bottom holds the floor's rooms.
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
      final data = snapshot.data;
      final building = data?.building(buildingId);
      if (data == null || building == null) {
        return Scaffold(
          appBar: const NiuAppBar(title: '校園地圖'),
          body: snapshot.connectionState == ConnectionState.done
              ? const NiuEmpty(title: '找不到這棟大樓')
              : const SizedBox.shrink(),
        );
      }
      final found = room == null ? null : data.locate(room!);
      return _BuildingView(
        map: data,
        building: building,
        initial: found?.building == building ? found : null,
      );
    },
  );
}

class _BuildingView extends StatefulWidget {
  const _BuildingView({
    required this.map,
    required this.building,
    this.initial,
  });
  final CampusMap map;
  final MapBuilding building;
  final RoomLocation? initial;
  @override
  State<_BuildingView> createState() => _BuildingViewState();
}

class _BuildingViewState extends State<_BuildingView>
    with SingleTickerProviderStateMixin {
  late MapFloor floor =
      widget.initial?.floor ??
      widget.building.floor(widget.building.defaultFloorId)!;
  late MapSpace? selected = widget.initial?.space;
  final zoom = TransformationController();
  final sheet = DraggableScrollableController();
  late final flight = AnimationController(
    vsync: this,
    duration: NiuMotion.standard,
  );
  Animation<Matrix4>? _flight;
  FloorFrame? frame;

  /// The room the view was last flown to, and the plan size it was aimed
  /// for; a later size change (rotation, insets) re-aims at it.
  MapSpace? _aimed;
  Size? _aimedSize;

  /// Drawer height when collapsed, and the top bar's, safe areas excluded.
  static const _peek = 112.0, _top = 64.0;

  @override
  void initState() {
    super.initState();
    flight.addListener(() {
      final a = _flight;
      if (a != null) zoom.value = a.value;
    });
    if (selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focus(selected!));
    }
  }

  @override
  void dispose() {
    flight.dispose();
    zoom.dispose();
    sheet.dispose();
    super.dispose();
  }

  // viewPadding, not padding: the keyboard must not move the plan's frame.
  double get _peekPixels => _peek + MediaQuery.viewPaddingOf(context).bottom;

  /// Animates the view to [target], or jumps when motion is reduced.
  void fly(Matrix4 target, {MapSpace? aim}) {
    if (!mounted) return;
    _aimed = aim;
    _aimedSize = aim == null ? null : frame?.size;
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

  /// Centres [space] in the clear area at a readable zoom.
  void focus(MapSpace space) {
    final f = frame;
    if (f == null) return;
    final area = f.padding.deflateRect(Offset.zero & f.size);
    final at = f.toCanvas(space.bounds.center);
    const scale = 2.4;
    fly(
      Matrix4.identity()
        ..translateByDouble(
          area.center.dx - at.dx * scale,
          area.center.dy - at.dy * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
      aim: space,
    );
  }

  /// Plan height; the drawer's sizes are fractions of it.
  double _height = 1;

  double get _minSheet => _peekPixels / _height;
  static const _maxSheet = .6;

  void _sheetTo(double size) {
    if (!sheet.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      sheet.jumpTo(size);
    } else {
      sheet.animateTo(
        size,
        duration: NiuMotion.standard,
        curve: NiuMotion.curve,
      );
    }
  }

  /// The drawer's header follows the finger whatever the list's scroll.
  void dragSheet(double dy) {
    if (!sheet.isAttached) return;
    sheet.jumpTo((sheet.size - dy / _height).clamp(_minSheet, _maxSheet));
  }

  /// Settles a header drag open or closed: a flick decides, else the
  /// nearer end.
  void settleSheet(double velocity) {
    if (!sheet.isAttached) return;
    final open = velocity.abs() > 300
        ? velocity < 0
        : sheet.size > (_minSheet + _maxSheet) / 2;
    _sheetTo(open ? _maxSheet : _minSheet);
  }

  void toggleSheet() {
    if (!sheet.isAttached) return;
    _sheetTo(sheet.size > _minSheet + .01 ? _minSheet : _maxSheet);
  }

  void collapseSheet() {
    _sheetTo(_minSheet);
  }

  void selectFloor(MapFloor next, {MapSpace? room}) {
    setState(() {
      floor = next;
      selected = room;
    });
    if (room == null) {
      fly(Matrix4.identity());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => focus(room));
    }
  }

  void selectRoom(MapSpace? room, {bool focusOn = false}) {
    setState(() => selected = room);
    if (room != null && focusOn) focus(room);
  }

  void tap(Offset canvas) {
    final f = frame;
    if (f == null) return;
    final room = floor.roomAt(f.toMetres(canvas));
    selectRoom(identical(room, selected) ? null : room);
  }

  Future<void> search() async {
    final found = await showModalBottomSheet<RoomLocation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _RoomSearchSheet(map: widget.map, building: widget.building),
    );
    if (found == null || !mounted) return;
    collapseSheet();
    selectFloor(found.floor, room: found.space);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final media = MediaQuery.of(context);
    final top = media.viewPadding.top + NiuSpacing.sm;
    final padding = EdgeInsets.fromLTRB(
      NiuSpacing.lg,
      top + _top,
      NiuSpacing.lg,
      _peekPixels + NiuSpacing.lg,
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      // A closing keyboard would resize the plan under a zoom already aimed
      // at a room; the plan keeps the whole screen instead.
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          _height = size.height;
          frame = FloorFrame(widget.building, size, padding: padding);
          final aimed = _aimed;
          if (aimed != null && _aimedSize != null && _aimedSize != size) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (identical(aimed, _aimed)) focus(aimed);
            });
          }
          return Stack(
            children: [
              Positioned.fill(child: _plan(context, size, padding)),
              Positioned(
                left: NiuSpacing.md,
                right: NiuSpacing.md,
                top: top,
                child: _TopBar(building: widget.building, onSearch: search),
              ),
              Positioned(
                right: NiuSpacing.md,
                top: top + _top,
                child: _FloorPicker(
                  floors: widget.building.floors,
                  selected: floor,
                  onSelect: (f) {
                    if (!identical(f, floor)) selectFloor(f);
                  },
                ),
              ),
              Positioned(
                right: NiuSpacing.md,
                bottom: _peekPixels + NiuSpacing.md,
                child: MapFloating(
                  child: NiuIconButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: '顯示整層',
                    onPressed: () => fly(Matrix4.identity()),
                  ),
                ),
              ),
              DraggableScrollableSheet(
                controller: sheet,
                initialChildSize: _minSheet,
                minChildSize: _minSheet,
                maxChildSize: _maxSheet,
                snap: true,
                builder: (context, scroll) => _FloorSheet(
                  scroll: scroll,
                  onDrag: dragSheet,
                  onDragEnd: settleSheet,
                  onToggle: toggleSheet,
                  floor: floor,
                  selected: selected,
                  onClear: () => selectRoom(null),
                  onPick: (room) {
                    collapseSheet();
                    selectRoom(room, focusOn: true);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _plan(BuildContext context, Size size, EdgeInsets padding) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return InteractiveViewer(
      transformationController: zoom,
      minScale: 1,
      maxScale: 6,
      onInteractionStart: (_) {
        flight.stop();
        _aimed = null;
      },
      child: GestureDetector(
        onTapUp: (d) => tap(d.localPosition),
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
                link: NiuHue.indigo.foreground(context),
                linkFill: NiuHue.indigo.background(context),
              ),
              textStyle: theme.textTheme.labelSmall ?? const TextStyle(),
              padding: padding,
              selected: selected,
              zoom: zoom,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.building, required this.onSearch});
  final MapBuilding building;
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const MapFloating(child: NiuBackButton()),
        const SizedBox(width: NiuSpacing.sm),
        Expanded(
          child: MapFloating(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiuSpacing.lg,
                vertical: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      building.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(building.levels, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: NiuSpacing.sm),
        MapFloating(
          child: NiuIconButton(
            icon: NiuIcons.search,
            tooltip: '搜尋教室',
            onPressed: onSearch,
          ),
        ),
      ],
    );
  }
}

/// Shows only the current floor until tapped; then every floor, top floor
/// first, closing again after a pick or a tap elsewhere.
class _FloorPicker extends StatefulWidget {
  const _FloorPicker({
    required this.floors,
    required this.selected,
    required this.onSelect,
  });
  final List<MapFloor> floors;
  final MapFloor selected;
  final ValueChanged<MapFloor> onSelect;
  @override
  State<_FloorPicker> createState() => _FloorPickerState();
}

class _FloorPickerState extends State<_FloorPicker> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    Widget item(MapFloor f) {
      final on = identical(f, widget.selected);
      return Semantics(
        button: true,
        selected: on,
        label: f.title,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            setState(() => open = false);
            widget.onSelect(f);
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? colors.accent : null,
              shape: BoxShape.circle,
            ),
            child: Text(
              f.id,
              style: theme.textTheme.titleSmall?.copyWith(
                color: on ? colors.onAccent : colors.inkSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return TapRegion(
      onTapOutside: (_) {
        if (open) setState(() => open = false);
      },
      child: MapFloating(
        radius: NiuRadius.xl,
        child: AnimatedSize(
          duration: NiuMotion.duration(context),
          curve: NiuMotion.curve,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.all(NiuSpacing.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final f in widget.floors.reversed) item(f)],
                  ),
                )
              : Semantics(
                  button: true,
                  expanded: false,
                  label: '樓層，目前${widget.selected.title}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() => open = true),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.selected.id,
                            style: theme.textTheme.titleMedium,
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            color: colors.inkSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The drawer: the marked room or the floor at a glance, and the floor's
/// numbered rooms when pulled up.
class _FloorSheet extends StatelessWidget {
  const _FloorSheet({
    required this.scroll,
    required this.floor,
    required this.selected,
    required this.onClear,
    required this.onPick,
    required this.onDrag,
    required this.onDragEnd,
    required this.onToggle,
  });
  final ScrollController scroll;

  /// The header resizes the drawer directly, so a list scrolled to a room
  /// never pins it.
  final ValueChanged<double> onDrag, onDragEnd;
  final VoidCallback onToggle;
  final MapFloor floor;
  final MapSpace? selected;
  final VoidCallback onClear;
  final ValueChanged<MapSpace> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final numbered = [
      for (final r in floor.rooms)
        if (r.label != null) r,
    ]..sort((a, b) => a.label!.compareTo(b.label!));
    final room = selected;
    final summary = room == null
        ? _SheetHeader(
            icon: Icons.layers_rounded,
            hue: NiuHue.indigo,
            title: floor.title,
            subtitle: floor.unit,
          )
        : _SheetHeader(
            icon: Icons.meeting_room_outlined,
            hue: NiuHue.blue,
            title: room.label ?? '未編號空間',
            subtitle: [floor.title, ...room.details].join('・'),
            trailing: NiuIconButton(
              icon: NiuIcons.close,
              tooltip: '取消標示',
              onPressed: onClear,
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NiuRadius.sheet),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
            onVerticalDragEnd: (d) => onDragEnd(d.velocity.pixelsPerSecond.dy),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiuSpacing.gutter,
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: NiuSpacing.sm),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.fillStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  summary,
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(
                NiuSpacing.gutter,
                NiuSpacing.xl,
                NiuSpacing.gutter,
                MediaQuery.viewPaddingOf(context).bottom + NiuSpacing.lg,
              ),
              children: [
                const NiuEyebrow('本層教室'),
                const SizedBox(height: NiuSpacing.sm),
                if (numbered.isEmpty)
                  Text('這一層還沒有教室編號。', style: theme.textTheme.bodySmall)
                else
                  NiuGroup(
                    insetDividers: NiuSpacing.lg,
                    children: [
                      for (final r in numbered)
                        NiuRow(
                          title: r.label!,
                          subtitle: r.details.isEmpty
                              ? null
                              : r.details.join('・'),
                          chevron: false,
                          trailing: identical(r, room)
                              ? Icon(Icons.place_rounded, color: colors.accent)
                              : null,
                          onTap: () => onPick(r),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.hue,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final NiuHue hue;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          NiuIconTile(icon: icon, hue: hue),
          const SizedBox(width: NiuSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Classroom search within the building; returns the picked room.
class _RoomSearchSheet extends StatefulWidget {
  const _RoomSearchSheet({required this.map, required this.building});
  final CampusMap map;
  final MapBuilding building;
  @override
  State<_RoomSearchSheet> createState() => _RoomSearchSheetState();
}

class _RoomSearchSheetState extends State<_RoomSearchSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final results = [
      for (final r in widget.map.search(query))
        if (identical(r.building, widget.building)) r,
    ];
    // Fixed height with the field on top: it stays clear of the keyboard
    // and of the system's navigation buttons, whatever the results.
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
                hint: '搜尋${widget.building.name}的教室',
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
                  if (query.trim().isNotEmpty && results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: NiuSpacing.lg),
                      child: Text('找不到符合的教室。'),
                    ),
                  for (final r in results.take(30))
                    NiuRow(
                      icon: Icons.meeting_room_outlined,
                      title: r.space.label!,
                      subtitle: [r.floor.title, ...r.space.details].join('・'),
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(context, r);
                      },
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
