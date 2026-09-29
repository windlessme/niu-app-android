import 'package:flutter/material.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import '../authentication/login_screen.dart';
import 'graduation_dashboard.dart';

class GraduationData {
  GraduationData.fromJson(Map<String, dynamic> json)
    : hours = normalizeHours(
        (json['diverseHours'] as List? ?? []).map((v) => v.toString()).toList(),
      ),
      english = json['englishAbility']?.toString() ?? '',
      fitness = json['physicalFitness']?.toString() ?? '',
      credits = (json['creditRequired'] as List? ?? [])
          .map((v) => v.toString())
          .toList(),
      program = json['creditCourse']?.toString() ?? '';
  final List<String> hours, credits;
  final String english, fitness, program;
  static List<String> normalizeHours(List<String> values) =>
      values.length == 4 ? values.expand((v) => [v, '不計入']).toList() : values;
}

const graduationExtractScript = r'''
(() => {
  const docs = [];
  function collect(w) {
    try { docs.push(w.document); for (let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {}
  }
  collect(window);
  const doc = docs.find(d => d.getElementById('div_B'));
  if (!doc) return null;
  const diverse = doc.getElementById('div_B');
  if (!diverse) return null;
  const ability = label => doc.querySelector('span[ml="' + label + '"]')?.closest('tr')?.querySelector('div')?.innerText || '';
  const credits = [];
  doc.querySelectorAll('tr.tdWhite').forEach(r => {
    if (r.cells[0]?.innerText.trim() === '畢業最低學分數') {
      credits.push(r.cells[1]?.innerText.trim() || '', r.cells[2]?.innerText.trim() || '');
    }
  });
  return JSON.stringify({diverseHours: diverse.innerText.match(/\d+/g) || [],
    englishAbility: ability('PL_外語能力'), physicalFitness: ability('PL_體適能'),
    creditRequired: credits, creditCourse: doc.getElementById('CRS_PROG')?.innerText || ''});
})()
''';

class GraduationScreen extends StatefulWidget {
  const GraduationScreen({super.key, this.session, this.webViewBuilder});
  final CampusSession? session;
  final Widget Function(Widget Function() create)? webViewBuilder;

  @override
  State<GraduationScreen> createState() => _GraduationScreenState();
}

class _GraduationScreenState extends State<GraduationScreen> {
  late final session = widget.session ?? CampusSession.instance;
  bool refreshing = false;

  Future<void> refresh() async {
    if (refreshing || !session.hasLocalAccount) return;
    final owner = session.account;
    final epoch = session.coordinator.epoch;
    setState(() => refreshing = true);
    try {
      if (!session.isSignedIn) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => LoginScreen(session: session)),
        );
      }
      if (!mounted ||
          session.account != owner ||
          session.coordinator.epoch != epoch ||
          !session.isSignedIn) {
        return;
      }
      if (session.cachedGraduation?.account != owner) return;
      // Keep the cached dashboard below this route, including on failure/back.
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => portal(context, refreshing: true),
        ),
      );
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Widget portal(BuildContext context, {bool refreshing = false}) {
    final owner = session.account;
    return AcademicPortalScreen(
      key: ValueKey((owner, session.coordinator.epoch)),
      title: '畢業門檻',
      session: session,
      webViewBuilder: widget.webViewBuilder,
      referer: Uri.parse(
        'https://acade.niu.edu.tw/NIU/Application/ENR/ENRG0/ENRG010_03.aspx',
      ),
      target: Uri.parse(
        'https://acade.niu.edu.tw/NIU/Application/ENR/ENRG0/ENRG010_01.aspx',
      ),
      extractScript: graduationExtractScript,
      onSnapshot: (value, epoch) async {
        if (owner == null) return;
        await session.cacheGraduationData(
          Map<String, dynamic>.from(value as Map),
          epoch: epoch,
          owner: owner,
        );
        if (refreshing &&
            context.mounted &&
            ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      },
      snapshotBuilder: (_, value) => GraduationDashboard(
        data: GraduationData.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (!session.hasLocalAccount) {
        return const Scaffold(
          appBar: IosPageHeader(title: '畢業門檻'),
          body: SafeArea(child: Center(child: Text('請先登入校務帳號'))),
        );
      }
      final cached = session.cachedGraduation;
      if (cached == null || cached.account != session.account) {
        if (session.isSignedIn && !refreshing) return portal(context);
        return Scaffold(
          appBar: const IosPageHeader(title: '畢業門檻'),
          body: SafeArea(
            child: SingleChildScrollView(
              child: NiuEmptyState(
                title: '尚未儲存畢業門檻',
                message: '連接校務系統讀取一次後，即可離線查看。',
                action: TextButton(
                  onPressed: refreshing ? null : refresh,
                  child: const Text('登入並讀取資料'),
                ),
              ),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: IosPageHeader(
          title: '畢業門檻',
          actions: [
            CircleIconButton(
              icon: Icons.refresh,
              tooltip: '更新畢業門檻',
              onPressed: refreshing ? null : refresh,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: GraduationDashboard(
            data: GraduationData.fromJson(cached.data),
            updatedAt: cached.fetchedAt,
            offline: session.isOffline,
            needsReauthentication: session.ssoNeedsReauthentication,
          ),
        ),
      );
    },
  );
}
