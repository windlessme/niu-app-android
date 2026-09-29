import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import 'certificate_service.dart';
import 'registration_data.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, this.session});
  final CampusSession? session;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final certificate = CertificateService(session);
  bool busy = false;

  @override
  void initState() {
    super.initState();
    // Register cleanup even before the first download.
    certificate;
  }

  @override
  void dispose() {
    unawaited(certificate.dispose());
    super.dispose();
  }

  Future<void> open(RegistrationData data, bool save) async {
    if (busy) return;
    final epoch = session.coordinator.epoch;
    setState(() => busy = true);
    try {
      final completed = await certificate.open(data, save: save);
      if (mounted && completed && save && epoch == session.coordinator.epoch) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('在學證明已儲存')));
      }
    } catch (_) {
      if (mounted && epoch == session.coordinator.epoch) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              save ? '無法下載在學證明，請確認登入狀態後重試。' : '無法開啟在學證明，請確認登入狀態及已安裝 PDF 閱讀程式。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AcademicPortalScreen(
    title: '註冊資訊',
    session: session,
    target: Uri.parse(
      'https://acade.niu.edu.tw/NIU/Application/ENR/ENR50/ENR5020_01.aspx',
    ),
    extractScript: registrationExtractScript,
    snapshotBuilder: (context, value) {
      final data = RegistrationData.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (!data.belongsTo(session.account)) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('查無可確認為本人的註冊資料，請重新整理或查看校方資料來源。'),
          ),
        );
      }
      return RegistrationDashboard(
        data: data,
        busy: busy,
        onView: data.printable ? () => open(data, false) : null,
        onSave: data.printable ? () => open(data, true) : null,
      );
    },
  );
}

class RegistrationDashboard extends StatelessWidget {
  const RegistrationDashboard({
    super.key,
    required this.data,
    this.busy = false,
    this.onView,
    this.onSave,
  });
  final RegistrationData data;
  final bool busy;
  final VoidCallback? onView, onSave;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: [
      const SectionHeader(title: '在學證明'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onView,
                  icon: const Icon(CupertinoIcons.doc_text),
                  label: const Text('瀏覽 PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onSave,
                  icon: const Icon(CupertinoIcons.arrow_down_doc),
                  label: const Text('下載 PDF'),
                ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    CupertinoActivityIndicator(),
                    SizedBox(width: 8),
                    Expanded(child: Text('正在取得在學證明…')),
                  ],
                ),
              ),
            if (!data.printable) const Text('暫無可用證明'),
          ],
        ),
      ),
      for (final row in data.rows) ...[
        SectionHeader(title: '註冊學年期 ${RegistrationData.display(row['註冊學年期'])}'),
        AppCard(
          child: Column(
            children: [
              for (final label in [
                '在學狀態',
                '註冊狀態',
                '註冊日期',
                '學雜費',
                '前學期學分費',
                '就學貸款',
                '請註冊假應註冊日期',
                '欠書欠款',
                '超商繳費收據',
                '收據上傳日期',
                '備註',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(label)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          RegistrationData.display(row[label]),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}
