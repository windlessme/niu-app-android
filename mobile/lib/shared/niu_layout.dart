import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'niu_colors.dart';

/// Phone and tablet layout. Pages keep one readable column on wide screens:
/// the side gutters grow so lines never stretch across a tablet, while the
/// whole width still scrolls and the app bar stays full width.
abstract final class NiuLayout {
  /// From here the tabs move to a side rail and the home tab splits in two.
  static const double wide = 600;

  /// Widest a page's content gets, gutters excluded.
  static const double readable = 720;

  /// Width the page is laid out in; the tab rail is already taken off.
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isWide(BuildContext context) => width(context) >= wide;

  /// Two-column pages and the week grid, which need more room.
  static const double spacious = 1040;

  /// The page's side gutter: [NiuSpacing.gutter] on phones, more on tablets
  /// so the content is at most [maxWidth] wide.
  static double gutter(BuildContext context, {double maxWidth = readable}) =>
      math.max(NiuSpacing.gutter, (width(context) - maxWidth) / 2);

  /// Page padding with the adaptive gutter.
  static EdgeInsets page(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
    double maxWidth = readable,
  }) {
    final side = gutter(context, maxWidth: maxWidth);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}
