import 'package:flutter/material.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'event_actions.dart';
import 'event_models.dart';

/// Whether one selected event may be sent in a batch, judged only from a
/// fresh read of the school's lists. Unknown is never treated as allowed.
class EventEligibility {
  const EventEligibility.eligible(this.reason) : canSubmit = true;
  const EventEligibility.excluded(this.reason) : canSubmit = false;
  final bool canSubmit;
  final String reason;

  static EventEligibility evaluate(
    CampusEvent event, {
    required Set<String> appliedIds,
    required Set<String> uncertainIds,
    required DateTime now,
  }) {
    final id = event.id;
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      return const EventEligibility.excluded('無法判定：活動編號不完整。');
    }
    if (appliedIds.contains(id)) {
      return const EventEligibility.excluded('已報名：學校的我的報名已有這個活動。');
    }
    if (uncertainIds.contains(id)) {
      return const EventEligibility.excluded('結果不明：這次登入曾送出，請先查看「我的報名」，不要立刻重送。');
    }
    final state = event.status;
    if (['截止', '結束', '停止報名'].any(state.contains)) {
      return EventEligibility.excluded('已截止：$state');
    }
    if (['未開放', '尚未開放', '尚未開始報名'].any(state.contains)) {
      return EventEligibility.excluded('未開放：$state');
    }
    if (['額滿', '已滿'].any(state.contains) || explicitlyFull(event.people)) {
      return const EventEligibility.excluded('額滿：學校的狀態或名額顯示已滿。');
    }
    final dates = registrationDates(event.registration);
    if (dates.isNotEmpty && now.isBefore(dates.first.start)) {
      return const EventEligibility.excluded('未開放：還沒到學校列出的報名日期。');
    }
    // Compare at the precision published; never invent a 23:59:59 deadline.
    if (dates.length == 2 && !now.isBefore(dates.last.end)) {
      return const EventEligibility.excluded('已截止：已超過學校列出的報名時間。');
    }
    if (!state.contains('報名中') && !state.contains('開放報名')) {
      return EventEligibility.excluded(
        '無法判定：學校沒有明確顯示可報名（${state.isEmpty ? '狀態空白' : state}）。',
      );
    }
    return EventEligibility.eligible(
      dates.length == 2
          ? '學校顯示可報名；送出時仍由學校確認資格與名額。'
          : '學校顯示報名中，日期不完整；送出時由學校表單再次判定。',
    );
  }

  /// Only numbers whose meaning the text states: 「正取：7 / 27，備取：0 / 5」
  /// or 「名額 30」 with 「已報名 30」. A full regular quota with standby
  /// places left is still worth asking the school.
  static bool explicitlyFull(String text) {
    if (text.contains('額滿')) return true;
    (int, int)? quota(String label) {
      final m = RegExp(
        '$label\\s*[:：]\\s*(\\d+)\\s*/\\s*(\\d+)',
      ).firstMatch(text);
      return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
    }

    final regular = quota('正取');
    if (regular != null && regular.$2 > 0 && regular.$1 >= regular.$2) {
      final standby = quota('備取');
      return standby == null || standby.$1 >= standby.$2;
    }
    int? number(String pattern) {
      final m = RegExp(pattern).firstMatch(text);
      return m == null ? null : int.parse(m[1]!);
    }

    final capacity = number(r'(?:限額|名額|上限)\s*[:：]?\s*(\d+)');
    final registered = number(r'(?:已報名|報名人數)\s*[:：]?\s*(\d+)');
    return capacity != null &&
        capacity > 0 &&
        registered != null &&
        registered >= capacity;
  }

  /// The two dates of 「2026/10/04 12:00 ~ 2026/10/10」, each as the span its
  /// precision covers (a day, a minute or a second), in Taipei time. The
  /// school may drop the space before the time. Anything else is unknown.
  static List<({DateTime start, DateTime end})> registrationDates(String text) {
    final matches = RegExp(
      r'(?<![0-9])([0-9]{4})[/-]([0-9]{1,2})[/-]([0-9]{2}|[0-9])(?:\s*(上午|下午|AM|PM)?\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?)?(?![0-9])',
    ).allMatches(text).toList();
    if (matches.length != 2) return const [];
    final result = <({DateTime start, DateTime end})>[];
    for (final m in matches) {
      final year = int.parse(m[1]!), month = int.parse(m[2]!);
      final day = int.parse(m[3]!);
      var hour = m[5] == null ? 0 : int.parse(m[5]!);
      final minute = m[6] == null ? 0 : int.parse(m[6]!);
      final second = m[7] == null ? 0 : int.parse(m[7]!);
      if (m[4] case final meridiem?) {
        if (hour < 1 || hour > 12) return const [];
        hour = hour % 12 + (meridiem == '下午' || meridiem == 'PM' ? 12 : 0);
      }
      // Taipei is UTC+8 all year.
      final start = DateTime.utc(year, month, day, hour - 8, minute, second);
      final local = start.add(const Duration(hours: 8));
      if (local.year != year ||
          local.month != month ||
          local.day != day ||
          local.hour != hour ||
          local.minute != minute) {
        return const [];
      }
      final span = m[7] != null
          ? const Duration(seconds: 1)
          : m[5] != null
          ? const Duration(minutes: 1)
          : const Duration(days: 1);
      result.add((start: start, end: start.add(span)));
    }
    if (result[1].start.isBefore(result[0].start)) return const [];
    return result;
  }
}

/// Events whose registration may have reached the school without a reply,
/// for this login only. They are never sent again automatically.
abstract final class EventSubmissions {
  static String? _owner;
  static final _uncertain = <String>{};

  static Set<String> uncertain(CampusSession session) {
    _sync(session);
    return Set.unmodifiable(_uncertain);
  }

  static void markUncertain(CampusSession session, String id) {
    _sync(session);
    _uncertain.add(id);
  }

  /// A fresh 「我的報名」 settles every listed event.
  static void reconcile(CampusSession session, Iterable<String> applied) {
    _sync(session);
    _uncertain.removeAll(applied);
  }

  static void _sync(CampusSession session) {
    final owner = '${session.account}:${session.coordinator.epoch}';
    if (_owner != owner) {
      _owner = owner;
      _uncertain.clear();
    }
  }
}

enum EventBatchStatus {
  pending,
  sending,
  confirmed,
  rejected,
  uncertain,
  notSent,
}

class EventBatchItem {
  EventBatchItem(this.event, this.eligibility)
    : status = eligibility.canSubmit
          ? EventBatchStatus.pending
          : EventBatchStatus.notSent,
      reason = eligibility.canSubmit ? null : eligibility.reason;
  final CampusEvent event;
  final EventEligibility eligibility;
  EventBatchStatus status;
  String? reason;
}

/// 批次報名: a fresh check of both school lists, a confirmation, then one
/// registration at a time. Nothing is sent before the explicit confirm, and
/// nothing failed or uncertain is resent.
class EventBatchScreen extends StatefulWidget {
  const EventBatchScreen({
    super.key,
    required this.events,
    required this.actions,
    this.session,
    this.clock,
  });
  final List<CampusEvent> events;
  final EventActions actions;
  final CampusSession? session;
  final DateTime Function()? clock;
  @override
  State<EventBatchScreen> createState() => _EventBatchScreenState();
}

enum _Phase { checking, failed, ready, submitting, finished, sessionChanged }

class _EventBatchScreenState extends State<EventBatchScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final owner = session.account;
  late final epoch = session.coordinator.epoch;
  var phase = _Phase.checking;
  var items = <EventBatchItem>[];
  var stopRequested = false;
  var sentAny = false;
  String? failure;

  bool get current =>
      mounted && session.account == owner && session.coordinator.epoch == epoch;
  int get eligible => items.where((i) => i.eligibility.canSubmit).length;
  int get processed => items
      .where(
        (i) =>
            i.eligibility.canSubmit &&
            i.status != EventBatchStatus.pending &&
            i.status != EventBatchStatus.sending,
      )
      .length;

  @override
  void initState() {
    super.initState();
    check();
  }

  /// Reads both lists again; no school mutation happens here.
  Future<void> check() async {
    setState(() {
      phase = _Phase.checking;
      failure = null;
    });
    try {
      final available = await widget.actions.available();
      if (!current) return;
      final applied = await widget.actions.registrations();
      if (!current) return _sessionChanged();
      final appliedIds = {
        for (final e in applied)
          if (e.id.isNotEmpty) e.id,
      };
      EventSubmissions.reconcile(session, appliedIds);
      final uncertain = EventSubmissions.uncertain(session);
      final now = (widget.clock ?? DateTime.now)();
      final seen = <String>{};
      setState(() {
        items = [
          for (final selected in widget.events)
            if (seen.add(selected.id))
              () {
                // Duplicate school IDs are ambiguous: never pick one.
                final fresh = available.where((e) => e.id == selected.id);
                final eligibility = appliedIds.contains(selected.id)
                    ? const EventEligibility.excluded('已報名：學校的我的報名已有這個活動。')
                    : fresh.length == 1
                    ? EventEligibility.evaluate(
                        fresh.single,
                        appliedIds: appliedIds,
                        uncertainIds: uncertain,
                        now: now,
                      )
                    : const EventEligibility.excluded(
                        '無法判定：學校的可報名活動沒有唯一、完整的這個活動。',
                      );
                return EventBatchItem(
                  fresh.length == 1 ? fresh.single : selected,
                  eligibility,
                );
              }(),
        ];
        phase = _Phase.ready;
      });
    } catch (_) {
      if (current) {
        setState(() {
          phase = _Phase.failed;
          failure = '無法核對學校的活動清單，沒有送出任何報名。';
        });
      }
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      stopRequested = true;
      items = [];
      phase = _Phase.sessionChanged;
    });
  }

  /// Only from the explicit confirm button.
  Future<void> confirm() async {
    if (phase != _Phase.ready || eligible == 0 || !current) return;
    setState(() {
      phase = _Phase.submitting;
      stopRequested = false;
    });
    for (final item in items) {
      if (!item.eligibility.canSubmit) continue;
      if (!current) return _sessionChanged();
      if (stopRequested) {
        setState(() {
          item.status = EventBatchStatus.notSent;
          item.reason = '已停止，沒有送出這個活動。';
        });
        continue;
      }
      if (EventSubmissions.uncertain(session).contains(item.event.id)) {
        setState(() {
          item.status = EventBatchStatus.notSent;
          item.reason = '這個活動已送出但結果不明，請查看「我的報名」。';
        });
        continue;
      }
      setState(() => item.status = EventBatchStatus.sending);
      EventActionResult result;
      try {
        result = await widget.actions.register(item.event);
      } catch (_) {
        result = const EventActionResult(
          false,
          '無法確認是否完成，請查看「我的報名」，不要立刻重送。',
          uncertain: true,
        );
      }
      if (!current) return _sessionChanged();
      final status = result.success
          ? EventBatchStatus.confirmed
          : result.uncertain
          ? EventBatchStatus.uncertain
          : result.needsWeb
          ? EventBatchStatus.notSent
          : EventBatchStatus.rejected;
      if (status == EventBatchStatus.uncertain) {
        EventSubmissions.markUncertain(session, item.event.id);
      }
      if (status != EventBatchStatus.notSent) sentAny = true;
      AppAnalytics.instance.event('event_register', {
        'result': switch (status) {
          EventBatchStatus.confirmed => 'success',
          EventBatchStatus.uncertain => 'unconfirmed',
          _ => 'failure',
        },
        'batch': 'yes',
      });
      setState(() {
        item.status = status;
        item.reason = result.message;
      });
    }
    if (current) setState(() => phase = _Phase.finished);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submitting = phase == _Phase.submitting;
    return PopScope<bool>(
      // Leaving mid-request would lose its result; stop the rest instead.
      canPop: !submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && submitting) setState(() => stopRequested = true);
      },
      child: Scaffold(
        appBar: NiuAppBar(title: '批次報名', showBack: !submitting),
        bottomNavigationBar: bar(context),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            NiuSpacing.md,
            NiuSpacing.gutter,
            NiuSpacing.huge,
          ),
          children: [
            ...switch (phase) {
              _Phase.checking => [
                const NiuLoading(message: '正在核對學校的可報名與已報名清單'),
              ],
              _Phase.failed => [
                NiuEmpty(
                  icon: NiuIcons.warning,
                  tone: NiuTone.warning,
                  title: '無法完成核對',
                  message: failure,
                  action: FilledButton.tonal(
                    onPressed: check,
                    child: const Text('重新核對'),
                  ),
                ),
              ],
              _Phase.sessionChanged => [
                const NiuEmpty(
                  icon: NiuIcons.logout,
                  tone: NiuTone.warning,
                  title: '登入狀態已變更',
                  message: '已停止後續報名。已送出的活動請用原帳號登入後查看「我的報名」。',
                ),
              ],
              _ => [
                Text(
                  phase == _Phase.ready
                      ? '可送出 $eligible 個，排除 ${items.length - eligible} 個。確認後 App 會逐一送出報名；資格與名額以學校當下的回應為準。'
                      : phase == _Phase.submitting
                      ? '已處理 $processed／$eligible 個。停止只會略過還沒送出的活動。'
                      : '請查看每個活動的結果。失敗、未送出與結果不明的活動不會自動重送。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: NiuSpacing.lg),
                NiuGroup(
                  children: [for (final item in items) row(context, item)],
                ),
              ],
            },
          ],
        ),
      ),
    );
  }

  Widget row(BuildContext context, EventBatchItem item) {
    final (label, tone) = switch (item.status) {
      EventBatchStatus.pending => ('可送出', NiuTone.accent),
      EventBatchStatus.sending => ('送出中', NiuTone.neutral),
      EventBatchStatus.confirmed => ('成功', NiuTone.success),
      EventBatchStatus.rejected => ('失敗', NiuTone.error),
      EventBatchStatus.uncertain => ('結果不明', NiuTone.warning),
      EventBatchStatus.notSent => ('未送出', NiuTone.neutral),
    };
    return NiuRow(
      title: item.event.name.isEmpty ? '編號 ${item.event.id}' : item.event.name,
      subtitle: item.reason ?? item.eligibility.reason,
      chevron: false,
      trailing: item.status == EventBatchStatus.sending
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : NiuBadge(label: label, tone: tone),
    );
  }

  Widget? bar(BuildContext context) => switch (phase) {
    _Phase.ready => NiuBottomBar(
      child: FilledButton(
        onPressed: eligible > 0 ? confirm : null,
        child: Text(eligible > 0 ? '確認報名 $eligible 個活動' : '沒有可送出的活動'),
      ),
    ),
    _Phase.submitting => NiuBottomBar(
      child: OutlinedButton(
        onPressed: stopRequested
            ? null
            : () => setState(() => stopRequested = true),
        child: Text(stopRequested ? '已要求停止' : '停止後續報名'),
      ),
    ),
    _Phase.finished || _Phase.sessionChanged => NiuBottomBar(
      child: FilledButton(
        onPressed: () => Navigator.pop(context, sentAny),
        child: const Text('完成'),
      ),
    ),
    _ => null,
  };
}
