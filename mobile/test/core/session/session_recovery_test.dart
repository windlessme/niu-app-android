import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/cached_schedule.dart';
import 'package:niu_mobile/features/grades/grade_statistics.dart';
import 'package:niu_mobile/features/grades/grades_models.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'persisted owner prevents bypassing account-switch cleanup before restore',
    () async {
      final vault = MemoryVault();
      vault.values['ssoAccount'] = 'old-owner';
      final api = FixtureSso();
      final session = CampusSession(
        vault: vault,
        sso: api,
        platformCleanup: [],
      );
      await expectLater(
        session.acceptToken('token', 'new-owner'),
        throwsStateError,
      );
      expect(api.requested.isCompleted, false);
    },
  );
  test(
    'all cleanups run despite failure and restart retries durable marker',
    () async {
      final vault = MemoryVault();
      vault.values['ssoToken'] = 'old';
      var cookiesCleared = false;
      var featureCleared = false;
      final session = CampusSession(
        vault: vault,
        platformCleanup: [
          () async => throw StateError('native unavailable'),
          () async {
            cookiesCleared = true;
          },
        ],
      );
      session.registerCleanup(() async {
        featureCleared = true;
      });
      await expectLater(session.logout(), throwsStateError);
      expect(cookiesCleared && featureCleared, true);
      expect(vault.values['ssoToken'], isNull);
      expect(vault.values['pendingCleanup'], 'true');
      var recovered = false;
      final restarted = CampusSession(
        vault: vault,
        platformCleanup: [
          () async {
            recovered = true;
          },
        ],
      );
      await restarted.restore();
      expect(recovered, true);
      expect(vault.values['pendingCleanup'], 'false');
      expect(restarted.isSignedIn, false);
    },
  );

  test(
    'network failure restores explicit offline cache without native clear',
    () async {
      final vault = MemoryVault();
      final api = FixtureSso();
      final session = CampusSession(
        vault: vault,
        sso: api,
        platformCleanup: [],
      );
      api.result.complete({'acnt': 'b123'});
      await session.acceptToken('token', 'b123');
      await session.cacheScheduleRows(
        [
          ['節次時間', '星期一'],
          ['第1節\n08:10~09:00', '微積分'],
        ],
        epoch: session.coordinator.epoch,
        owner: 'b123',
      );
      final failingApi = FixtureSso();
      var cleared = false;
      final restored = CampusSession(
        vault: vault,
        sso: failingApi,
        platformCleanup: [
          () async {
            cleared = true;
          },
        ],
      );
      final restoring = restored.restore();
      await failingApi.requested.future;
      failingApi.result.completeError(StateError('offline'));
      await restoring;
      expect(restored.isOffline, true);
      expect(restored.isSignedIn, false);
      expect(restored.cachedSchedule!.account, 'b123');
      expect(
        restored.cachedSchedule!
            .today(now: DateTime.utc(2026, 9, 27, 16))
            .single
            .course,
        '微積分',
      );
      expect(cleared, false);
      await restored.logout();
      expect(restored.cachedSchedule, isNull);
      expect(vault.values['scheduleCache'], isNull);
    },
  );

  test(
    'Taipei midnight and absent days are mapped without device timezone',
    () {
      final cache = CachedSchedule(
        account: 'a',
        fetchedAt: DateTime.utc(2026),
        rows: [
          ['節次', '時間', '星期一', '星期六'],
          ['1', '08:10~09:00', '數學', '專題'],
        ],
      );
      expect(cache.today(now: DateTime.utc(2026, 9, 27, 15, 59)), isEmpty);
      expect(
        cache.today(now: DateTime.utc(2026, 9, 27, 16)).single.time,
        '08:10~09:00',
      );
      expect(cache.coursesForWeekday(6).single.course, '專題');
    },
  );

  test(
    'weighted GPA excludes textual outcomes and includes failed credits',
    () {
      final stats = GradeStatistics([
        const GradeCourse(
          semester: '1141',
          name: 'A',
          type: '必修',
          score: '90',
          credits: 3,
        ),
        const GradeCourse(
          semester: '1141',
          name: 'B',
          type: '必修',
          score: '59',
          credits: 1,
        ),
        const GradeCourse(
          semester: '1141',
          name: 'C',
          type: '必修',
          score: '通過',
          credits: 9,
        ),
      ]);
      expect(stats.credits, 4);
      expect(stats.earnedCredits, 12);
      expect(stats.attemptedCredits, 13);
      expect(stats.gpa, closeTo(3.225, 0.0001));
      expect(GradeStatistics.points(77), 3.3);
      expect(GradeStatistics.points(60), 1.7);
    },
  );
}
