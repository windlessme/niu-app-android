import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/demo/demo_data.dart';
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
        showNiuMessage(context, '在學證明已儲存');
      }
    } catch (_) {
      if (mounted && epoch == session.coordinator.epoch) {
        showNiuMessage(
          context,
          save ? '下載失敗，請確認登入狀態後再試一次' : '無法開啟，請確認登入狀態，以及手機有 PDF 閱讀 App',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AcademicPortalScreen(
    title: '在學證明',
    session: session,
    target: Uri.parse(
      'https://acade.niu.edu.tw/NIU/Application/ENR/ENR50/ENR5020_01.aspx',
    ),
    extractScript: registrationExtractScript,
    demoSnapshot: () => DemoData.registration(session.account ?? ''),
    snapshotBuilder: (context, value) {
      final data = RegistrationData.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (!data.belongsTo(session.account)) {
        return const Center(
          child: SingleChildScrollView(
            child: NiuEmpty(
              icon: NiuIcons.registration,
              title: '找不到你的註冊資料',
              message: '無法確認這份資料屬於你本人。請重新整理，或查看學校網頁。',
            ),
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

  static const _details = [
    '註冊日期',
    '學雜費',
    '前學期學分費',
    '就學貸款',
    '請註冊假應註冊日期',
    '欠書欠款',
    '超商繳費收據',
    '收據上傳日期',
    '備註',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.sm,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: [
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const NiuIconTile(
                    icon: NiuIcons.document,
                    hue: NiuHue.cyan,
                    size: NiuSize.iconTileLarge,
                  ),
                  const SizedBox(width: NiuSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('在學證明', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '學校核發的 PDF，可以直接開啟或存到手機',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NiuSpacing.xl),
              if (!data.printable)
                const NiuBanner(tone: NiuTone.neutral, message: '目前沒有可以列印的在學證明')
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onView,
                        icon: const Icon(NiuIcons.document, size: 18),
                        label: const Text('瀏覽 PDF'),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onSave,
                        icon: const Icon(NiuIcons.download, size: 18),
                        label: const Text('下載 PDF'),
                      ),
                    ),
                  ],
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: NiuSpacing.md),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        for (final row in data.rows)
          NiuSection(
            title: '${RegistrationData.display(row['註冊學年期'])} 學期註冊',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: NiuStat(
                          label: '在學狀態',
                          value: RegistrationData.display(row['在學狀態']),
                        ),
                      ),
                      Expanded(
                        child: NiuStat(
                          label: '註冊狀態',
                          value: RegistrationData.display(row['註冊狀態']),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  const Divider(),
                  const SizedBox(height: NiuSpacing.md),
                  for (final label in _details)
                    NiuKeyValue(
                      label: label,
                      value: RegistrationData.display(row[label]),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
