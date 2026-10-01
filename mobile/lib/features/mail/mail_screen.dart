import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import '../authentication/remember_school_login.dart';
import '../demo/demo_services.dart';
import 'mail_compose_screen.dart';
import 'mail_detail_screen.dart';
import 'mail_format.dart';
import 'mail_models.dart';
import 'mail_session.dart';
import 'mail_web_screen.dart';
import 'numail_client.dart';

enum _Phase { connecting, signIn, ready, failed }

/// 校園信箱: native NUMail — folders, reading, search and writing.
class MailScreen extends StatefulWidget {
  const MailScreen({
    super.key,
    this.session,
    this.service,
    this.mailSession,
    this.now,
    this.bodyBuilder,
  });
  final CampusSession? session;

  /// Skips sign-in; for tests.
  final MailService? service;
  final MailSession? mailSession;
  final DateTime Function()? now;
  final Widget Function(MailMessage message, bool remote)? bodyBuilder;
  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final mailSession = widget.mailSession ?? MailSession(session);
  _Phase phase = _Phase.connecting;
  MailService? service;
  String? error;
  int generation = 0;

  // Sign-in
  MailChallenge? challenge;
  final password = TextEditingController();
  final code = TextEditingController();
  bool signingIn = false, twoFactor = false;
  String? signInError;

  // Mailbox
  List<MailFolder> folders = const [];
  String box = MailFolder.inbox;
  final mails = <MailSummary>[];
  int total = 0, page = 0;
  bool loading = false;
  String query = '';
  Timer? searchDelay;
  final search = TextEditingController();
  final scroll = ScrollController();
  final selected = <int>{};
  bool acting = false;

  DateTime now() => widget.now?.call() ?? DateTime.now();
  String get me => '${session.account ?? ''}@${NumailClient.host}';
  MailFolder? get folder => folders.where((f) => f.name == box).firstOrNull;

  @override
  void initState() {
    super.initState();
    session.registerCleanup(_clear);
    connect();
  }

  @override
  void dispose() {
    generation++;
    session.unregisterCleanup(_clear);
    searchDelay?.cancel();
    service?.close();
    challenge?.client.close();
    password.dispose();
    code.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    generation++;
    service?.close();
    service = null;
    if (mounted) setState(() => phase = _Phase.signIn);
  }

  // ── Sign-in ───────────────────────────────────────────────────────────────

  Future<void> connect() async {
    final current = ++generation;
    setState(() {
      phase = _Phase.connecting;
      error = null;
    });
    try {
      MailService? next =
          widget.service ??
          (session.isDemo ? DemoMailService() : await mailSession.restore());
      if (next == null) {
        final saved = await RememberSchoolLogin.forSession(session).restore();
        if (saved != null && saved.account == session.account) {
          try {
            next = await mailSession.automatic(saved.password);
          } catch (_) {}
        }
      }
      if (!mounted || current != generation) return next?.close();
      if (next == null) {
        setState(() => phase = _Phase.signIn);
        await newChallenge();
        return;
      }
      await _ready(next, current);
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        phase = _Phase.failed;
        error = e is MailException ? e.message : '無法連線到學校信箱，請檢查網路後再試。';
      });
    }
  }

  Future<void> newChallenge() async {
    final current = generation;
    challenge?.client.close();
    setState(() {
      challenge = null;
      twoFactor = false;
      code.clear();
    });
    try {
      final next = await mailSession.challenge();
      if (!mounted || current != generation) return next.client.close();
      setState(() {
        challenge = next;
        code.text = next.guess ?? '';
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(
          () => signInError = e is MailException ? e.message : '無法取得驗證碼，請檢查網路。',
        );
      }
    }
  }

  Future<void> signIn() async {
    final c = challenge;
    if (c == null || signingIn) return;
    if (!twoFactor && password.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final current = generation;
    setState(() {
      signingIn = true;
      signInError = null;
    });
    try {
      final web = twoFactor
          ? await mailSession.twoFactor(c, code.text)
          : await mailSession.signIn(c, password.text, code.text);
      if (!mounted || current != generation) return;
      challenge = null;
      password.clear();
      code.clear();
      await _ready(web, current);
    } on MailTwoFactorRequired catch (e) {
      if (mounted) {
        setState(() {
          twoFactor = true;
          code.clear();
          signInError = e.message;
        });
      }
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(
        () => signInError = e is MailException ? e.message : '登入失敗，請再試一次。',
      );
      // A code is single-use; fetch another for the next try.
      if (!twoFactor) await newChallenge();
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }

  // ── Mailbox ───────────────────────────────────────────────────────────────

  Future<void> _ready(MailService next, int current) async {
    service?.close();
    service = next;
    final list = await next.folders();
    if (!mounted || current != generation) return;
    setState(() {
      folders = list;
      if (folder == null) box = list.first.name;
      phase = _Phase.ready;
    });
    await reload();
  }

  static const perPage = 20;
  int get pages => total == 0 ? 1 : (total + perPage - 1) ~/ perPage;

  /// Loads [toPage] (default: the page on screen) of the current folder.
  Future<void> reload({bool foldersToo = false, int? toPage}) async {
    final api = service;
    if (api == null) return;
    final current = generation;
    final target = (toPage ?? page).clamp(1, 1 << 20);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (foldersToo) {
        final list = await api.folders();
        if (mounted && current == generation) folders = list;
      }
      final result = await api.list(box, page: target, query: query);
      if (!mounted || current != generation) return;
      // A page emptied by deletions falls back to the new last page.
      if (result.mails.isEmpty && target > 1 && result.total > 0) {
        final last = (result.total + perPage - 1) ~/ perPage;
        if (last < target) return await reload(toPage: last);
      }
      setState(() {
        mails
          ..clear()
          ..addAll(result.mails);
        total = result.total;
        page = target;
        selected.clear();
      });
    } on MailSignInRequired {
      if (mounted && current == generation) {
        service?.close();
        service = null;
        setState(() => phase = _Phase.signIn);
        await newChallenge();
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e is MailException ? e.message : '無法讀取信件。');
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> goTo(int target) async {
    if (loading || target < 1 || target > pages || target == page) return;
    generation++;
    await reload(toPage: target);
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> pickPage() async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _PageDialog(page: page, pages: pages),
    );
    if (chosen != null) await goTo(chosen.clamp(1, pages));
  }

  void openFolder(String name) {
    if (name == box) return;
    generation++;
    setState(() {
      box = name;
      mails.clear();
      page = 0;
      total = 0;
      selected.clear();
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    reload(foldersToo: true, toPage: 1);
  }

  void searchChanged(String value) {
    searchDelay?.cancel();
    searchDelay = Timer(const Duration(milliseconds: 500), () {
      if (value.trim() == query) return;
      query = value.trim();
      generation++;
      reload(toPage: 1);
    });
  }

  Future<void> open(MailSummary m) async {
    final api = service;
    if (api == null || selected.isNotEmpty) return toggle(m);
    if (box == MailFolder.drafts) return openDraft(m);
    final outcome = await Navigator.of(context).push<MailOutcome>(
      MaterialPageRoute(
        builder: (_) => MailDetailScreen(
          service: api,
          summary: m,
          folders: folders,
          me: me,
          bodyBuilder: widget.bodyBuilder,
        ),
      ),
    );
    if (!mounted) return;
    final i = mails.indexWhere((x) => x.uid == m.uid);
    setState(() {
      if (outcome == MailOutcome.removed) {
        if (i >= 0) mails.removeAt(i);
        total = total > 0 ? total - 1 : 0;
      } else if (i >= 0) {
        final read = outcome != MailOutcome.unread;
        mails[i] = m.withFlags([
          ...m.flags.where((f) => !f.contains('Seen')),
          if (read) r'\Seen',
        ]);
      }
    });
    _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    try {
      final list = await service?.folders();
      if (list != null && mounted) setState(() => folders = list);
    } catch (_) {}
  }

  Future<void> openDraft(MailSummary m) async {
    final api = service!;
    try {
      final (draft, data) = await api.openDraft(m.uid);
      if (!mounted) return;
      await write(ComposeKind.draft, data, draft);
    } catch (e) {
      if (mounted) {
        showNiuMessage(context, e is MailException ? e.message : '無法開啟草稿');
      }
    }
  }

  Future<void> write([
    ComposeKind kind = ComposeKind.fresh,
    MailDraftData? data,
    MailDraft? draft,
  ]) async {
    final api = service;
    if (api == null) return;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailComposeScreen(
          service: api,
          kind: kind,
          initial: data ?? MailDraftData(),
          draft: draft,
        ),
      ),
    );
    if (!mounted) return;
    if (sent == true) showNiuMessage(context, '已寄出');
    if (box == MailFolder.drafts || box == MailFolder.sent) {
      reload(foldersToo: true);
    } else {
      _refreshCounts();
    }
  }

  void toggle(MailSummary m) => setState(() {
    if (!selected.remove(m.uid)) selected.add(m.uid);
  });

  Future<void> bulk(String action) async {
    final api = service;
    if (api == null || selected.isEmpty || acting) return;
    final uids = selected.toList();
    final permanent = box == MailFolder.trash || box == MailFolder.drafts;
    MailFolder? target;
    if (action == 'move') {
      target = await pickMailFolder(
        context,
        folders.where((f) => f.name != box).toList(),
      );
      if (target == null) return;
    }
    if (action == 'delete' &&
        permanent &&
        mounted &&
        !await confirmNiuAction(
          context,
          title: '永久刪除 ${uids.length} 封信？',
          message: '刪除後無法復原。',
          confirmLabel: '刪除',
          destructive: true,
        )) {
      return;
    }
    setState(() => acting = true);
    try {
      switch (action) {
        case 'read':
          await api.setSeen(box, uids, true);
        case 'unread':
          await api.setSeen(box, uids, false);
        case 'move':
          await api.move(box, uids, target!.name);
        case 'delete':
          await (permanent
              ? api.delete(box, uids)
              : api.move(box, uids, MailFolder.trash));
      }
      if (!mounted) return;
      showNiuMessage(context, switch (action) {
        'read' => '已標為已讀',
        'unread' => '已標為未讀',
        'move' => '已移到「${target!.label}」',
        _ => permanent ? '已永久刪除' : '已移到垃圾桶',
      });
      await reload(foldersToo: true);
    } catch (e) {
      if (mounted) {
        showNiuMessage(
          context,
          e is MailException ? e.message : '操作沒有成功，請再試一次。',
        );
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (phase != _Phase.ready) {
      return NiuScrollPage(
        title: '校園信箱',
        onRefresh: phase == _Phase.signIn ? newChallenge : connect,
        children: [
          switch (phase) {
            _Phase.connecting => const NiuLoading(message: '正在連線學校信箱'),
            _Phase.failed => NiuError(
              title: '無法開啟校園信箱',
              message: error ?? '請稍後再試。',
              onRetry: connect,
            ),
            _ => _signIn(context),
          },
        ],
      );
    }
    final selecting = selected.isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(selected.clear);
      },
      child: NiuScrollPage(
        title: selecting ? '已選 ${selected.length} 封' : '校園信箱',
        controller: scroll,
        onRefresh: () => reload(foldersToo: true),
        actions: selecting
            ? [
                NiuIconButton(
                  icon: Icons.mark_email_read_outlined,
                  tooltip: '標為已讀',
                  onPressed: acting ? null : () => bulk('read'),
                ),
                NiuIconButton(
                  icon: Icons.mark_email_unread_outlined,
                  tooltip: '標為未讀',
                  onPressed: acting ? null : () => bulk('unread'),
                ),
                NiuIconButton(
                  icon: Icons.drive_file_move_outline,
                  tooltip: '移到',
                  onPressed: acting ? null : () => bulk('move'),
                ),
                NiuIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '刪除',
                  onPressed: acting ? null : () => bulk('delete'),
                ),
              ]
            : [
                if (service?.cookies.isNotEmpty ?? false)
                  NiuIconButton(
                    icon: Icons.language_rounded,
                    tooltip: '學校信箱網頁',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MailWebScreen(cookies: service!.cookies),
                      ),
                    ),
                  ),
              ],
        floatingActionButton: selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: () => write(),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('寫信'),
              ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.gutter,
              NiuSpacing.xs,
              NiuSpacing.gutter,
              NiuSpacing.sm,
            ),
            sliver: SliverList.list(
              children: [
                NiuFilterBar<String>(
                  options: [
                    for (final f in folders)
                      (
                        f.name,
                        f.unseen > 0 && f.name != MailFolder.sent
                            ? '${f.label} ${f.unseen}'
                            : f.label,
                      ),
                  ],
                  value: box,
                  onChanged: openFolder,
                ),
                const SizedBox(height: NiuSpacing.md),
                NiuSearchField(
                  controller: search,
                  hint: '搜尋${folder?.label ?? '信件'}',
                  onChanged: searchChanged,
                ),
                if (error != null) ...[
                  const SizedBox(height: NiuSpacing.md),
                  NiuBanner(
                    tone: NiuTone.warning,
                    message: error!,
                    actionLabel: loading ? null : '再試一次',
                    onAction: loading ? null : reload,
                  ),
                ],
              ],
            ),
          ),
          if (mails.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(NiuSpacing.gutter),
                child: loading
                    ? const NiuLoading(message: '正在讀取信件')
                    : NiuEmpty(
                        icon: query.isEmpty
                            ? Icons.inbox_outlined
                            : NiuIcons.search,
                        title: query.isEmpty
                            ? '「${folder?.label ?? box}」沒有信件'
                            : '找不到符合「$query」的信件',
                      ),
              ),
            )
          else ...[
            SliverList.separated(
              itemCount: mails.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: NiuSpacing.gutter + 52,
                color: NiuColors.of(context).hairline,
              ),
              itemBuilder: (context, i) => _MailTile(
                mail: mails[i],
                sentBox: box == MailFolder.sent || box == MailFolder.drafts,
                now: now(),
                selected: selected.contains(mails[i].uid),
                onTap: () => open(mails[i]),
                onLongPress: () => toggle(mails[i]),
              ),
            ),
            SliverToBoxAdapter(
              child: _Pager(
                page: page,
                pages: pages,
                total: total,
                first: (page - 1) * perPage + 1,
                last: (page - 1) * perPage + mails.length,
                loading: loading,
                onPrevious: () => goTo(page - 1),
                onNext: () => goTo(page + 1),
                onPick: pages > 1 ? pickPage : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signIn(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final c = challenge;
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: NiuIconTile(icon: Icons.mail_rounded, hue: NiuHue.blue),
            ),
            const SizedBox(height: NiuSpacing.md),
            Text(
              twoFactor ? '二次驗證' : '登入校園信箱',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NiuSpacing.xs),
            Text(
              twoFactor ? '輸入驗證 App 或簡訊收到的驗證碼。' : '使用校務系統的帳號密碼，登入一次後會保持登入。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: NiuSpacing.xl),
            if (!twoFactor) ...[
              TextField(
                controller: TextEditingController(text: me),
                readOnly: true,
                enableInteractiveSelection: false,
                decoration: const InputDecoration(
                  labelText: '帳號',
                  prefixIcon: Icon(NiuIcons.account),
                ),
              ),
              const SizedBox(height: NiuSpacing.md),
              TextField(
                controller: password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '密碼',
                  prefixIcon: Icon(NiuIcons.lock),
                ),
              ),
              const SizedBox(height: NiuSpacing.md),
              if (c?.png != null || c == null)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(NiuRadius.md),
                          border: Border.all(color: colors.hairline),
                        ),
                        alignment: Alignment.center,
                        child: c?.png == null
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Image.memory(
                                c!.png!,
                                fit: BoxFit.contain,
                                semanticLabel: '驗證碼圖片',
                              ),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    NiuIconButton(
                      icon: NiuIcons.refresh,
                      tooltip: '換一張驗證碼',
                      onPressed: signingIn ? null : newChallenge,
                    ),
                  ],
                ),
            ],
            if (twoFactor || c?.png != null) ...[
              const SizedBox(height: NiuSpacing.md),
              TextField(
                controller: code,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => signIn(),
                onChanged: (_) => setState(() {}),
                autofillHints: twoFactor
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                decoration: InputDecoration(
                  labelText: twoFactor ? '二次驗證碼' : '驗證碼',
                  helperText: !twoFactor && c?.guess != null
                      ? '已自動辨識，若不正確請修改'
                      : null,
                  prefixIcon: const Icon(Icons.password_rounded),
                ),
              ),
            ],
            if (signInError != null) ...[
              const SizedBox(height: NiuSpacing.md),
              NiuBanner(tone: NiuTone.error, message: signInError!),
            ],
            const SizedBox(height: NiuSpacing.lg),
            FilledButton(
              onPressed:
                  signingIn ||
                      c == null ||
                      (!twoFactor && password.text.isEmpty) ||
                      ((twoFactor || c.png != null) && code.text.trim().isEmpty)
                  ? null
                  : signIn,
              child: Text(signingIn ? '登入中' : (twoFactor ? '驗證' : '登入')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MailTile extends StatelessWidget {
  const _MailTile({
    required this.mail,
    required this.sentBox,
    required this.now,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final MailSummary mail;
  final bool sentBox, selected;
  final DateTime now;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final people = sentBox ? mail.to : mail.from;
    final who = people.isEmpty
        ? '（無）'
        : '${sentBox ? '寄給 ' : ''}${people.first.display}'
              '${people.length > 1 ? ' 等 ${people.length} 人' : ''}';
    final unread = !mail.seen && !sentBox;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    return Semantics(
      selected: selected,
      label:
          '${unread ? '未讀，' : ''}$who，${mail.subject.isEmpty ? '無主旨' : mail.subject}'
          '${mail.hasAttachment ? '，有附件' : ''}'
          '${mail.date == null ? '' : '，${formatMailDateLong(mail.date!)}'}',
      excludeSemantics: true,
      button: true,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.gutter,
              vertical: NiuSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                selected
                    ? CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.accent,
                        child: Icon(
                          Icons.check_rounded,
                          color: colors.onAccent,
                        ),
                      )
                    : MailAvatar(
                        name: people.isEmpty ? '?' : people.first.display,
                      ),
                const SizedBox(width: NiuSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (mail.hasAttachment)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: NiuSpacing.xs,
                              ),
                              child: Icon(
                                NiuIcons.attach,
                                size: 16,
                                color: colors.inkTertiary,
                              ),
                            ),
                          if (mail.date != null) ...[
                            const SizedBox(width: NiuSpacing.sm),
                            Text(
                              formatMailDateShort(mail.date!, now),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: unread ? colors.accent : null,
                                fontWeight: unread ? FontWeight.w700 : null,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              mail.subject.isEmpty ? '（無主旨）' : mail.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: weight,
                                color: colors.ink,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(
                                left: NiuSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (mail.preview.isNotEmpty)
                        Text(
                          mail.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 上一頁 · 第 x / y 頁 · 下一頁, plus which messages are shown.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.total,
    required this.first,
    required this.last,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });
  final int page, pages, total, first, last;
  final bool loading;
  final VoidCallback onPrevious, onNext;
  final VoidCallback? onPick;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.md,
        NiuSpacing.gutter,
        NiuSpacing.huge + NiuSpacing.xl,
      ),
      child: Column(
        children: [
          if (pages > 1)
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '上一頁',
                  onPressed: loading || page <= 1 ? null : onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: loading ? null : onPick,
                      child: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '第 $page / $pages 頁',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                            ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '下一頁',
                  onPressed: loading || page >= pages ? null : onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            total == 0 ? '' : '第 $first–$last 封，共 $total 封',
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a page number; owns its field so closing never outlives it.
class _PageDialog extends StatefulWidget {
  const _PageDialog({required this.page, required this.pages});
  final int page, pages;
  @override
  State<_PageDialog> createState() => _PageDialogState();
}

class _PageDialogState extends State<_PageDialog> {
  late final field = TextEditingController(text: '${widget.page}');

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, int.tryParse(field.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳到第幾頁'),
    content: TextField(
      controller: field,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(helperText: '共 ${widget.pages} 頁'),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: submit, child: const Text('前往')),
    ],
  );
}
