import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';
import '../attendance/attendance_result_screen.dart';
import '../attendance/attendance_repository.dart' show attendanceQr;
import 'moodle_repository.dart';
import 'moodle_web_screen.dart';
import 'moodle_attachment_screen.dart';

void pushMoodle(BuildContext context, Widget screen) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => screen));

Future<void> openMoodleUrl(
  BuildContext context,
  MoodleRepository repository,
  String raw,
  String title, {
  bool file = false,
}) async {
  try {
    final uri = Uri.parse(raw);
    if (file || uri.path.contains('/pluginfile.php/')) {
      pushMoodle(
        context,
        MoodleAttachmentScreen(repository: repository, url: raw, name: title),
      );
    } else if (uri.host == 'euni.niu.edu.tw') {
      if (attendanceQr(raw) != null) {
        final confirmed = await confirmNiuAction(
          context,
          title: '要開啟點名嗎？',
          message: '開啟這個頁面可能會直接記錄出席。',
          confirmLabel: '開啟並點名',
        );
        if (!confirmed || !context.mounted) return;
        pushMoodle(
          context,
          AttendanceResultScreen(
            repository: repository,
            target: attendanceQr(raw)!,
          ),
        );
        return;
      }
      pushMoodle(
        context,
        MoodleWebScreen(repository: repository, target: uri, title: title),
      );
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.userInfo.isEmpty) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException();
      }
    } else {
      throw const FormatException();
    }
  } catch (_) {
    if (context.mounted) {
      showNiuMessage(context, '無法開啟這個連結');
    }
  }
}

class MoodleAttachmentButton extends StatelessWidget {
  const MoodleAttachmentButton({super.key, required this.name, this.onPressed});
  final String name;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NiuSpacing.sm),
    child: Material(
      color: NiuColors.of(context).fill,
      borderRadius: BorderRadius.circular(NiuRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(NiuRadius.md),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.md,
              vertical: NiuSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  NiuIcons.attach,
                  size: 18,
                  color: NiuColors.of(context).accent,
                ),
                const SizedBox(width: NiuSpacing.sm),
                Expanded(
                  child: Text(
                    name.isEmpty ? '附件' : name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: NiuColors.of(context).accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
