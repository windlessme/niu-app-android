import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';
import '../authentication/login_screen.dart';
import 'moodle_repository.dart';
import 'moodle_session_store.dart';
import 'moodle_login_service.dart';
import 'moodle_courses_screen.dart';

class MoodleScreen extends StatefulWidget {
  const MoodleScreen({
    super.key,
    this.account,
    this.password,
    this.repository,
    this.onAuthenticated,
  });
  final String? account, password;
  final MoodleRepository? repository;
  final ValueChanged<MoodleRepository>? onAuthenticated;
  @override
  State<MoodleScreen> createState() => _MoodleScreenState();
}

class _MoodleScreenState extends State<MoodleScreen> {
  late final account = TextEditingController(text: widget.account);
  late final password = TextEditingController(text: widget.password);
  MoodleRepository? repository;
  String? error;
  bool busy = false;
  int loginGeneration = 0;
  late final sessionStore = MoodleSessionStore(CampusSession.instance);
  @override
  void initState() {
    super.initState();
    repository = widget.repository;
    if (CampusSession.instance.hasLocalAccount) {
      repository?.bindSession(CampusSession.instance);
    }
    CampusSession.instance.registerCleanup(clearSession);
    if (repository == null &&
        widget.account != null &&
        widget.password != null) {
      restoreOrLogin();
    } else if (repository == null) {
      restoreOrLogin();
    }
  }

  Future<void> restoreOrLogin() async {
    final generation = ++loginGeneration;
    setState(() => busy = true);
    try {
      final restored = await sessionStore.restore(
        MoodleApiClient(schoolClient('https://euni.niu.edu.tw')),
      );
      if (!mounted || generation != loginGeneration) return;
      if (restored != null) {
        setState(() => repository = restored);
        widget.onAuthenticated?.call(restored);
      }
    } catch (_) {
      if (mounted && generation == loginGeneration) {
        setState(() => error = '目前無法恢復 M 園區登入。檢查網路後再試一次，或重新登入。');
      }
    }
    if (!mounted || generation != loginGeneration) return;
    setState(() => busy = false);
    if (repository == null && password.text.isNotEmpty) await login();
  }

  Future<void> login() async {
    if (busy) return;
    final generation = ++loginGeneration;
    final epoch = CampusSession.instance.coordinator.epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await MoodleLoginService(CampusSession.instance).establish(
        account: account.text.trim(),
        password: password.text,
        epoch: epoch,
      );
      if (!mounted || generation != loginGeneration) return;
      CampusSession.instance.coordinator.requireCurrent(epoch);
      if (!mounted || generation != loginGeneration) return;
      password.clear();
      setState(() => repository = result);
      widget.onAuthenticated?.call(result);
    } catch (_) {
      if (mounted && generation == loginGeneration) {
        setState(() => error = 'M 園區登入失敗，請確認帳號密碼與網路連線。');
      }
    } finally {
      if (mounted && generation == loginGeneration) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant MoodleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account ||
        oldWidget.repository != widget.repository) {
      loginGeneration++;
      busy = false;
      repository = widget.repository;
      account.text = widget.account ?? '';
      password.text = widget.password ?? '';
      error = null;
      if (repository == null && !busy) {
        restoreOrLogin();
      }
    }
  }

  @override
  void dispose() {
    sessionStore.dispose();
    CampusSession.instance.unregisterCleanup(clearSession);
    account.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> clearSession() async {
    loginGeneration++;
    await repository?.invalidate();
    if (!mounted) return;
    setState(() {
      repository = null;
      busy = false;
      password.clear();
      account.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    if (repo != null) {
      return MoodleCoursesScreen(key: ValueKey(repo.session), repository: repo);
    }
    return NiuScrollPage(
      title: 'M 園區',
      large: true,
      showBack: false,
      children: [
        if (busy)
          const NiuLoading(message: '正在連接 M 園區')
        else
          NiuEmpty(
            icon: NiuIcons.moodle,
            tone: NiuTone.accent,
            title: '連接 M 園區',
            message: error ?? '用學校帳號登入一次，就能在這裡看課程、公告、作業和成績。',
            action: FilledButton(
              onPressed: () async {
                await Navigator.of(context, rootNavigator: true).push<bool>(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                if (mounted) await restoreOrLogin();
              },
              child: const Text('登入'),
            ),
            secondaryAction: TextButton(
              onPressed: restoreOrLogin,
              child: const Text('重新連線'),
            ),
          ),
      ],
    );
  }
}
