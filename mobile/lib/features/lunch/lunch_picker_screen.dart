import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/shared.dart';
import 'lunch_picker.dart';

/// 午餐吃什麼, as on iOS: draw 麵, 飯 or 其他, then a dish, then look for
/// a shop. iOS lists shops from Apple Maps; here the phone's map app
/// searches the dish around the chosen spot, so no search service is needed.
class LunchPickerScreen extends StatefulWidget {
  const LunchPickerScreen({super.key, this.launch});

  /// Opens a map search; tests replace it.
  final Future<bool> Function(Uri uri)? launch;

  @override
  State<LunchPickerScreen> createState() => _LunchPickerScreenState();
}

enum _Stage { category, dish }

class _LunchPickerScreenState extends State<LunchPickerScreen> {
  LunchCategory? _category;
  String? _dish;

  /// The stage spinning, and what it shows right now.
  _Stage? _rolling;
  String? _face;
  Timer? _timer;

  static const _hue = NiuHue.orange;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _rolling = null;
    _face = null;
  }

  void _roll(_Stage stage, List<String> faces, VoidCallback commit) {
    setState(_stop);
    void settle() {
      setState(() {
        _stop();
        commit();
      });
      HapticFeedback.mediumImpact();
      SemanticsService.sendAnnouncement(
        View.of(context),
        _announcement,
        Directionality.of(context),
      );
    }

    if (MediaQuery.disableAnimationsOf(context)) return settle();
    var frame = 0;
    String? last;
    void tick() {
      if (frame == lunchShuffleDelays.length) return settle();
      last = pickLunch(faces, avoiding: last);
      setState(() {
        _rolling = stage;
        _face = last;
      });
      _timer = Timer(Duration(milliseconds: lunchShuffleDelays[frame++]), tick);
    }

    tick();
  }

  void _rollCategory() {
    final result = pickLunch(LunchCategory.values, avoiding: _category)!;
    _roll(_Stage.category, [for (final c in LunchCategory.values) c.face], () {
      _category = result;
      _dish = null;
    });
  }

  void _rollDish() {
    final dishes = _category!.dishes;
    final result = pickLunch(dishes, avoiding: _dish)!;
    _roll(_Stage.dish, dishes, () => _dish = result);
  }

  void _choose(LunchCategory category) => setState(() {
    _stop();
    if (_category == category) return;
    _category = category;
    _dish = null;
  });

  void _reset() => setState(() {
    _stop();
    _category = null;
    _dish = null;
  });

  String get _announcement {
    if (_dish case final dish?) return '抽到$dish';
    if (_category case final category?) return '抽到${category.title}';
    return '';
  }

  Future<void> _search(LunchArea area) async {
    final dish = _dish!;
    final launch =
        widget.launch ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened =
          await launch(area.mapSearch(dish)) ||
          await launch(area.webSearch(dish));
    } catch (_) {}
    if (!opened && mounted) showNiuMessage(context, '無法開啟地圖');
  }

  @override
  Widget build(BuildContext context) {
    final category = _category, dish = _dish;
    return NiuScrollPage(
      title: '午餐吃什麼',
      actions: [
        if (category != null)
          TextButton(onPressed: _reset, child: const Text('重來')),
      ],
      children: [
        _StepCard(
          number: 1,
          title: '先決定吃麵、飯還是其他',
          children: [
            Row(
              children: [
                for (final c in LunchCategory.values) ...[
                  if (c != LunchCategory.values.first)
                    const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: _CategoryTile(
                      category: c,
                      selected: _rolling == _Stage.category
                          ? _face == c.face
                          : category == c,
                      onTap: () => _choose(c),
                    ),
                  ),
                ],
              ],
            ),
            _RollButton(
              label: category == null ? '隨機選類別' : '重抽類別',
              icon: Icons.casino_rounded,
              rolling: _rolling == _Stage.category,
              enabled: _rolling == null,
              onPressed: _rollCategory,
            ),
          ],
        ),
        if (category != null) ...[
          const SizedBox(height: NiuSpacing.md),
          _StepCard(
            number: 2,
            title: '從「${category.title}」裡挑一道',
            children: [
              _DishResult(
                text: _rolling == _Stage.dish ? _face : dish,
                settled: _rolling == null && dish != null,
              ),
              _RollButton(
                label: dish == null ? '抽一道${category.title}' : '換一道',
                icon: Icons.shuffle_rounded,
                rolling: _rolling == _Stage.dish,
                enabled: _rolling == null,
                onPressed: _rollDish,
              ),
              Text('候選清單', style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: NiuSpacing.sm,
                runSpacing: NiuSpacing.sm,
                children: [
                  for (final d in category.dishes)
                    _DishChip(
                      dish: d,
                      lit: _rolling == _Stage.dish ? _face == d : dish == d,
                    ),
                ],
              ),
            ],
          ),
        ],
        if (dish != null && _rolling == null) ...[
          const SizedBox(height: NiuSpacing.md),
          _StepCard(
            number: 3,
            title: '去哪裡吃$dish',
            children: [
              for (final area in LunchArea.values)
                OutlinedButton.icon(
                  onPressed: () => _search(area),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _hue.foreground(context),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.map_rounded),
                  label: Text('在地圖搜尋${area.title}的$dish'),
                ),
              Text(
                '會用手機的地圖 App 搜尋，營業時間與菜單請以店家公告為準。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.children,
  });
  final int number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hue = _LunchPickerScreenState._hue;
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: '步驟 $number，$title',
            excludeSemantics: true,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hue.foreground(context),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.surface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: NiuSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
          ),
          for (final child in children) ...[
            const SizedBox(height: NiuSpacing.md),
            child,
          ],
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final LunchCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hue = _LunchPickerScreenState._hue;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NiuRadius.lg),
      side: BorderSide(
        color: selected ? hue.foreground(context) : Colors.transparent,
        width: 2,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: category.title,
      hint: category.detail,
      excludeSemantics: true,
      child: Material(
        color: selected ? hue.background(context) : NiuColors.of(context).fill,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(category.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(height: NiuSpacing.xs),
                Text(
                  category.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DishResult extends StatelessWidget {
  const _DishResult({required this.text, required this.settled});
  final String? text;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Semantics(
      liveRegion: settled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text ?? '還沒決定',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: text == null ? colors.inkTertiary : null,
                ),
              ),
            ),
            if (settled) ...[
              const SizedBox(height: NiuSpacing.xs),
              Text('今天中午就吃$text吧！', style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _DishChip extends StatelessWidget {
  const _DishChip({required this.dish, required this.lit});
  final String dish;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final hue = _LunchPickerScreenState._hue;
    return AnimatedContainer(
      duration: NiuMotion.duration(context, const Duration(milliseconds: 80)),
      padding: const EdgeInsets.symmetric(
        horizontal: NiuSpacing.md,
        vertical: NiuSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: lit ? hue.foreground(context) : NiuColors.of(context).fill,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
      ),
      child: Text(
        dish,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: lit ? Theme.of(context).colorScheme.surface : null,
        ),
      ),
    );
  }
}

class _RollButton extends StatelessWidget {
  const _RollButton({
    required this.label,
    required this.icon,
    required this.rolling,
    required this.enabled,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool rolling, enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hue = _LunchPickerScreenState._hue;
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: hue.foreground(context),
        foregroundColor: Theme.of(context).colorScheme.surface,
        minimumSize: const Size.fromHeight(48),
      ),
      icon: Icon(icon),
      label: Text(rolling ? '抽籤中…' : label),
    );
  }
}
