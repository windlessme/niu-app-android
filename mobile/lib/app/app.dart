import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../core/platform/play_update.dart';
import '../core/session/cached_schedule.dart';
import '../core/session/campus_session.dart';
import '../features/academic_calendar/calendar_screen.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/remember_school_login.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/events/events_screen.dart';
import '../features/grades/grades_screen.dart';
import '../features/graduation/graduation_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/today_courses.dart';
import '../features/library/library_screen.dart';
import '../features/library/library_space_screen.dart';
import '../features/moodle/course_matcher.dart';
import '../features/moodle/course_presentation.dart';
import '../features/moodle/moodle_login_service.dart';
import '../features/moodle/moodle_repository.dart';
import '../features/moodle/moodle_screen.dart';
import '../features/notifications/campus_notifications.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/postal/postal_screen.dart';
import '../features/registration/registration_screen.dart';
import '../features/leave/leave_screen.dart';
import '../features/settings/credits_repository.dart';
import '../shared/niu_theme.dart';
import 'auth_gate.dart';
import 'campus_shell.dart';
import 'deep_links.dart';
import 'providers.dart';

class NiuApp extends StatefulWidget {
  const NiuApp({super.key});
  @override
  State<NiuApp> createState() => _NiuAppState();
}

class _NiuAppState extends State<NiuApp> {
  final session = CampusSession.instance;
  MoodleRepository? moodle;
  final appearance = ValueNotifier<ThemeMode>(ThemeMode.system);
  ThemeMode get mode => appearance.value;
  CreditsRepository? credits;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  late final notifications = CampusNotifications(
    session: session,
    moodle: _restoreMoodle,
    calendar: AppCalendarRepository(),
  );
  late final GoRouter router = GoRouter(
    observers: [libraryRouteObserver],
    redirect: (_, state) => campusDeepLink(state.uri),
    routes: [
      ShellRoute(
        builder: (_, state, child) =>
            CampusShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ListenableBuilder(
              listenable: session,
              builder: (_, _) => CampusHomeScreen(
                name: session.hasLocalAccount ? session.displayName : null,
                department: session.profile['facultyName']?.toString(),
                courses: _todayCourses(),
                onRefresh: session.retryRestore,
                offline: session.isOffline,
                ssoNeedsReauthentication: session.ssoNeedsReauthentication,
                hasSchedule: session.cachedSchedule != null,
                onOpenCourse: _openCourse,
                demo: session.isDemo,
              ),
            ),
          ),
          GoRoute(
            path: '/schedule',
            builder: (_, _) => AuthGate(
              title: '課表',
              allowLocalAccount: true,
              child: ScheduleScreen(onOpenCourse: _openCourse),
            ),
          ),
          GoRoute(
            path: '/moodle',
            builder: (_, _) => AuthGate(
              title: 'M 園區',
              allowLocalAccount: true,
              child: ListenableBuilder(
                listenable: session,
                builder: (_, _) => _moodleScreen(),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, _) => LoginScreen(
          onSignedIn: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/postal', builder: (_, _) => const PostalScreen()),
      GoRoute(
        path: '/leave',
        builder: (_, _) => const AuthGate(
          title: '請假',
          allowLocalAccount: true,
          child: LeaveScreen(),
        ),
      ),
      GoRoute(
        path: '/registration',
        builder: (_, _) =>
            const AuthGate(title: '在學證明', child: RegistrationScreen()),
      ),
      GoRoute(
        path: '/grades',
        builder: (_, _) => const AuthGate(title: '成績', child: GradesScreen()),
      ),
      GoRoute(
        path: '/graduation',
        builder: (_, _) => const AuthGate(
          title: '畢業門檻',
          allowLocalAccount: true,
          child: GraduationScreen(),
        ),
      ),
      GoRoute(
        path: '/events',
        builder: (_, _) => const AuthGate(
          title: '活動報名',
          allowLocalAccount: true,
          child: EventsScreen(),
        ),
      ),
      GoRoute(
        path: '/library',
        builder: (_, _) => AuthGate(
          title: '圖書館',
          allowLocalAccount: true,
          child: ListenableBuilder(
            listenable: session,
            builder: (_, _) => LibraryScreen(account: session.account ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/library/spaces',
        builder: (_, _) => const AuthGate(
          title: '空間預約',
          allowLocalAccount: true,
          child: LibrarySpaceScreen(),
        ),
      ),
      GoRoute(
        path: '/attendance',
        builder: (_, _) => AuthGate(
          title: '點名',
          allowLocalAccount: true,
          child: ListenableBuilder(
            listenable: session,
            builder: (_, _) => moodle == null
                ? _moodleScreen(forAttendance: true)
                : AttendanceScannerScreen(repository: moodle!),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => ListenableBuilder(
          listenable: session,
          builder: (_, _) => ValueListenableBuilder<ThemeMode>(
            valueListenable: appearance,
            builder: (_, selectedMode, _) => SettingsScreen(
              name: session.hasLocalAccount ? session.displayName : null,
              username: session.hasLocalAccount ? session.account : null,
              offline: session.isOffline,
              ssoNeedsReauthentication: session.ssoNeedsReauthentication,
              onReconnect: session.hasLocalAccount
                  ? () => router.push('/login')
                  : null,
              department: session.profile['facultyName']?.toString(),
              grade: session.profile['grade']?.toString(),
              themeMode: selectedMode,
              creditsRepository: credits,
              notifications: notifications,
              onThemeModeChanged: _setTheme,
              onForgetSchoolLogin: RememberSchoolLogin.forSession(
                session,
              ).forget,
              onLogout: session.account != null || session.cleanupPending
                  ? session.logout
                  : null,
              onRefreshProfile: session.hasLocalAccount
                  ? () async {
                      await session.retryRestore();
                      if (!session.isSignedIn) {
                        throw StateError('校務連線尚未恢復');
                      }
                    }
                  : null,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _moodleScreen({bool forAttendance = false}) => MoodleScreen(
    account: session.account,
    repository: moodle,
    onAuthenticated: (value) {
      moodle = value;
      if (mounted) setState(() {});
      if (forAttendance) router.pushReplacement('/attendance');
    },
  );

  Future<List<CoursePresentation>>? _courses;
  MoodleRepository? _coursesOwner;
  bool _openingCourse = false;

  /// Timetable entry → its M 園區 course. Falls back to the M 園區 tab when
  /// there is no M 園區 login or no matching course.
  Future<void> _openCourse(String name) async {
    if (_openingCourse) return;
    _openingCourse = true;
    try {
      var repo = moodle;
      if (repo == null && session.hasLocalAccount) {
        try {
          repo = await MoodleLoginService(session).restore();
        } catch (_) {}
        if (repo != null && mounted) setState(() => moodle = repo);
      }
      if (repo == null) {
        router.go('/moodle');
        return;
      }
      if (!identical(_coursesOwner, repo)) {
        _coursesOwner = repo;
        _courses = null;
      }
      final load = _courses ??= repo.courses().then(
        (list) => list.map(CoursePresentation.new).toList(),
      );
      List<CoursePresentation> courses;
      try {
        courses = await load;
      } catch (_) {
        _courses = null;
        router.go('/moodle');
        return;
      }
      final match = matchMoodleCourse(courses, name);
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (match == null || context == null || !context.mounted) {
        router.go('/moodle');
        return;
      }
      pushMoodle(
        context,
        MoodleCourseScreen(repository: repo, course: match.source),
      );
    } finally {
      _openingCourse = false;
    }
  }

  Future<MoodleRepository?> _restoreMoodle() async {
    if (moodle != null || !session.hasLocalAccount) return moodle;
    final repo = await MoodleLoginService(session).restore();
    if (repo != null && mounted) setState(() => moodle = repo);
    return repo;
  }

  String? _notifiedAccount;
  CachedSchedule? _notifiedSchedule;

  /// Reschedules after sign-in, restore and timetable updates, as on iOS.
  void _syncNotifications() {
    final account = session.hasLocalAccount ? session.account : null;
    final schedule = session.cachedSchedule;
    if (account == _notifiedAccount && identical(schedule, _notifiedSchedule)) {
      return;
    }
    _notifiedAccount = account;
    _notifiedSchedule = schedule;
    if (account != null) notifications.refresh().catchError((Object _) {});
  }

  List<HomeCourse> _todayCourses() {
    return todayCourses(session.cachedSchedule, now: DateTime.now());
  }

  Future<void> _clearMoodle() async {
    router.go('/');
    await moodle?.invalidate();
    moodle = null;
    _courses = null;
    _coursesOwner = null;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    session.registerCleanup(_clearMoodle);
    session.addListener(_syncNotifications);
    _restorePreferences();
    session.restore().catchError((Object _) {});
    PlayUpdate(messenger).check();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final support = await getApplicationSupportDirectory();
      credits = CreditsRepository(
        cacheDirectory: Directory('${support.path}/public_credits'),
      );
    } catch (_) {
      /* Public credits remain available without persistent cache. */
    }
    final name = prefs.getString('appearance');
    if (mounted) {
      setState(
        () => appearance.value = ThemeMode.values.firstWhere(
          (value) => value.name == name,
          orElse: () => ThemeMode.system,
        ),
      );
    }
  }

  Future<void> _setTheme(ThemeMode value) async {
    setState(() => appearance.value = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', value.name);
  }

  @override
  void dispose() {
    session.unregisterCleanup(_clearMoodle);
    session.removeListener(_syncNotifications);
    router.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'NIU-Life',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: messenger,
    locale: const Locale('zh', 'TW'),
    supportedLocales: const [Locale('zh', 'TW')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: NiuTheme.light,
    darkTheme: NiuTheme.dark,
    themeMode: mode,
    themeAnimationDuration:
        MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : const Duration(milliseconds: 200),
    builder: (context, child) {
      final brightness = Theme.of(context).brightness;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: NiuTheme.overlay(
          brightness,
          Colors.transparent,
        ).copyWith(systemNavigationBarContrastEnforced: false),
        child: child ?? const SizedBox.shrink(),
      );
    },
    routerConfig: router,
  );
}
