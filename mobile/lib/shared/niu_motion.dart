import 'package:flutter/widgets.dart';

abstract final class NiuMotion {
  static const fast = Duration(milliseconds: 250);
  static const standard = Duration(milliseconds: 350);
  static const slow = Duration(milliseconds: 500);
  static const curve = Curves.easeOut;
  static Duration duration(BuildContext context, [Duration value = fast]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}
