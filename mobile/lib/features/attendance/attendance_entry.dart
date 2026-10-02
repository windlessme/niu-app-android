import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import '../moodle/moodle_repository.dart';
import 'attendance_screen.dart';

/// The way into the scanner from shortcuts, widgets and links, which mostly
/// start the app cold: wait for the saved M 園區 sign-in, then scan. Only a
/// missing sign-in shows the M 園區 login.
class AttendanceEntry extends StatefulWidget {
  const AttendanceEntry({
    super.key,
    required this.restore,
    required this.signIn,
  });
  final Future<MoodleRepository?> Function() restore;
  final WidgetBuilder signIn;
  @override
  State<AttendanceEntry> createState() => _AttendanceEntryState();
}

class _AttendanceEntryState extends State<AttendanceEntry> {
  late final Future<MoodleRepository?> repository = widget.restore().then(
    (value) => value,
    onError: (Object _) => null,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<MoodleRepository?>(
    future: repository,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          appBar: NiuAppBar(title: '快速點名'),
          body: Center(child: NiuLoading(message: '正在連接 M 園區')),
        );
      }
      final value = snapshot.data;
      return value == null
          ? widget.signIn(context)
          : AttendanceScannerScreen(repository: value);
    },
  );
}
