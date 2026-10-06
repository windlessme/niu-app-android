import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hides the student's full name on the home screen, like iOS: 王小明 shows
/// as 王同學. The choice is kept on the device.
class NameMask {
  const NameMask._();
  static const key = 'home.isNameMasked';

  /// Null until the saved choice is read; treated as hidden meanwhile so a
  /// cold start never flashes the full name.
  static final masked = ValueNotifier<bool?>(null);

  static Future<void> load() async {
    try {
      masked.value =
          (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      masked.value ??= false;
    }
  }

  static Future<void> toggle() async {
    final next = !(masked.value ?? true);
    masked.value = next;
    try {
      await (await SharedPreferences.getInstance()).setBool(key, next);
    } catch (_) {}
  }

  static const _compound = [
    '歐陽', '司馬', '上官', '諸葛', '司徒', '司空', '夏侯', '皇甫', //
    '尉遲', '公孫', '慕容', '令狐', '宇文', '長孫', '獨孤', '東方', '南宮',
  ];

  /// 王小明 → 王同學, 歐陽娜娜 → 歐陽同學.
  static String hide(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '同學';
    final surname =
        _compound
            .where((s) => trimmed.startsWith(s) && trimmed.length > s.length)
            .firstOrNull ??
        trimmed.characters.first;
    return '$surname同學';
  }

  static String display(String name) =>
      masked.value == false ? name : hide(name);
}

/// [name] after the mask, briefly scrambled when the mask changes (unless
/// the system asks for less motion).
class MaskedName extends StatefulWidget {
  const MaskedName({
    super.key,
    required this.name,
    this.prefix = '',
    this.style,
    this.maxLines,
  });
  final String name, prefix;
  final TextStyle? style;
  final int? maxLines;
  @override
  State<MaskedName> createState() => _MaskedNameState();
}

class _MaskedNameState extends State<MaskedName> {
  static const _glyphs = '０１２３４５６７８９ＡＢＣＤＥＦ＃＊＋／＝';
  final _random = Random();
  bool? _shown;
  String? _scrambled;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _shown = NameMask.masked.value;
    NameMask.masked.addListener(_changed);
  }

  void _changed() {
    final previous = _shown;
    _shown = NameMask.masked.value;
    // Loading the saved choice is not a toggle; only a press animates.
    if (previous == null || !mounted) return setState(() {});
    _timer?.cancel();
    if (MediaQuery.of(context).disableAnimations) {
      return setState(() => _scrambled = null);
    }
    final target = NameMask.display(widget.name);
    var frame = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 45), (timer) {
      if (!mounted) return timer.cancel();
      if (++frame >= 12) {
        timer.cancel();
        return setState(() => _scrambled = null);
      }
      final revealed = max(0, (frame - 3) * target.length ~/ 8);
      setState(() {
        _scrambled = String.fromCharCodes([
          for (final (i, unit) in target.runes.indexed)
            i < revealed
                ? unit
                : _glyphs.runes.elementAt(_random.nextInt(_glyphs.length)),
        ]);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    NameMask.masked.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = NameMask.display(widget.name);
    return Semantics(
      label: '${widget.prefix}$shown',
      excludeSemantics: true,
      child: Text(
        '${widget.prefix}${_scrambled ?? shown}',
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}

/// The eye beside the greeting that hides or shows the full name.
class NameMaskButton extends StatelessWidget {
  const NameMaskButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
    valueListenable: NameMask.masked,
    builder: (context, masked, _) {
      final hidden = masked ?? true;
      return IconButton(
        onPressed: NameMask.toggle,
        tooltip: hidden ? '顯示完整姓名' : '隱藏完整姓名',
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 22,
        ),
      );
    },
  );
}
