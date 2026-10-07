import 'package:flutter/material.dart';

import '../../shared/shared.dart';

const _lessonHues = [
  NiuHue.blue,
  NiuHue.purple,
  NiuHue.teal,
  NiuHue.orange,
  NiuHue.indigo,
  NiuHue.green,
  NiuHue.pink,
  NiuHue.cyan,
];

/// Stable per-course colour, so a course looks the same on every day. The
/// widgets (`WidgetSupport.kt`) use the same hash and palette.
NiuHue lessonHue(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _lessonHues[hash % _lessonHues.length];
}

/// A course colour for light and dark themes.
class LessonTint {
  const LessonTint(this.light, this.dark);
  LessonTint.hue(NiuHue hue) : this(hue.light, hue.dark);
  final Color light, dark;

  Color foreground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color background(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return foreground(context).withValues(alpha: dark ? .18 : .11);
  }

  @override
  bool operator ==(Object other) =>
      other is LessonTint && other.light == light && other.dark == dark;
  @override
  int get hashCode => Object.hash(light, dark);
}

/// Preset colours for custom courses. The names are stored, the same ones
/// iOS uses, so a stored value means the same colour on both.
enum CustomCourseColor {
  red('紅色', NiuHue.red),
  orange('橘色', NiuHue.orange),
  yellow('黃色', NiuHue.amber),
  green('綠色', NiuHue.green),
  mint('薄荷綠', null, Color(0xff0b8a6a), Color(0xff5fe3bb)),
  teal('藍綠色', NiuHue.teal),
  cyan('青色', NiuHue.cyan),
  blue('藍色', NiuHue.blue),
  indigo('靛色', NiuHue.indigo),
  purple('紫色', NiuHue.purple),
  pink('粉紅色', NiuHue.pink),
  brown('棕色', null, Color(0xff8a5a32), Color(0xffd6aa7e));

  const CustomCourseColor(this.title, this._hue, [this._light, this._dark]);
  final String title;
  final NiuHue? _hue;
  final Color? _light, _dark;

  LessonTint get tint =>
      _hue == null ? LessonTint(_light!, _dark!) : LessonTint.hue(_hue);
}

/// The tint for a stored custom course colour: a preset name or a picked
/// `#RRGGBB`. Null for 「自動」 and for values this version doesn't know,
/// which then keep the name-based colour.
LessonTint? customCourseTint(String? id) {
  if (id == null) return null;
  for (final preset in CustomCourseColor.values) {
    if (preset.name == id) return preset.tint;
  }
  final colour = colourFromHex(id);
  // A picked colour stays as chosen in both themes, as on iOS.
  return colour == null ? null : LessonTint(colour, colour);
}

Color? colourFromHex(String id) {
  if (id.length != 7 || !id.startsWith('#')) return null;
  final value = int.tryParse(id.substring(1), radix: 16);
  return value == null ? null : Color(0xff000000 | value);
}

String hexFromColour(Color colour) =>
    '#${(colour.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The colour a lesson shows in: its custom colour, else by name.
LessonTint lessonTint(String name, [String? colorId]) =>
    customCourseTint(colorId) ?? LessonTint.hue(lessonHue(name));
