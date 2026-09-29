import 'attendance_repository.dart';

/// Single-flight boundary includes confirmation, camera pause and navigation.
class AttendanceOpenFlow {
  bool busy = false;
  Future<void> open(
    String raw, {
    required Future<void> Function() pause,
    required Future<bool> Function(Uri) confirm,
    required Future<void> Function(Uri) navigate,
    required Future<void> Function() resume,
  }) async {
    if (busy) return;
    final uri = attendanceQr(raw);
    if (uri == null) throw const FormatException('請掃描 M 園區點名 QR Code');
    busy = true;
    try {
      await pause();
      if (await confirm(uri)) await navigate(uri);
    } finally {
      busy = false;
      await resume();
    }
  }
}
