import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../demo/demo_account.dart';
import '../session/campus_session.dart';

/// Anonymous usage statistics through Google Analytics for Firebase.
///
/// Only fixed names leave the device: which screen, which action and its
/// outcome, which kind of error. Never accounts, names, grades, mail, course
/// titles or any other school content. Off in debug builds, store-screenshot
/// builds, the review demo, builds without a Firebase config, and for anyone
/// who turned it off before 1.0.24, when settings still had a switch for it.
class AppAnalytics {
  AppAnalytics._();
  static final instance = AppAnalytics._();
  static const preferenceKey = 'analyticsEnabled';

  FirebaseAnalytics? _analytics;
  bool _started = false;
  // Events from the first frames, sent once Firebase is up.
  final _pending = <(String, Map<String, Object>?)>[];

  /// On unless turned off with the former settings switch; that choice is
  /// kept, though it can no longer be changed.
  bool enabled = true;

  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(preferenceKey) ?? true;
    } catch (_) {}
    if (kDebugMode || storeScreenshots) {
      _started = true;
      _pending.clear();
      return;
    }
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      // The manifest starts with collection off, so nothing is sent before
      // the saved choice is known.
      await _analytics!.setAnalyticsCollectionEnabled(enabled);
    } catch (_) {
      _analytics = null; // Built without google-services.json.
    }
    _started = true;
    for (final (name, parameters) in List.of(_pending)) {
      event(name, parameters);
    }
    _pending.clear();
  }

  bool get _active =>
      _analytics != null && enabled && !CampusSession.instance.isDemo;

  /// [name] is one of a fixed set of English screen names, e.g. `grades`.
  void screen(String name) =>
      event('screen_view', {'screen_name': name, 'screen_class': name});

  /// [name] and [parameters] are fixed identifiers chosen in code, never
  /// text that came from the school or the student.
  void event(String name, [Map<String, Object>? parameters]) {
    if (!_started) {
      if (_pending.length < 10) _pending.add((name, parameters));
      return;
    }
    if (!_active) return;
    unawaited(
      _analytics!
          .logEvent(name: name, parameters: parameters)
          .catchError((_) {}),
    );
  }

  /// `success` or `failure` for an action's outcome.
  void result(String name, bool ok, [Map<String, Object>? parameters]) =>
      event(name, {...?parameters, 'result': ok ? 'success' : 'failure'});

  /// A school page or service that did not answer, by kind only.
  void error(String page, String reason) =>
      event('load_error', {'page': page, 'reason': reason});
}

/// Screen views for routes opened by path (e.g. `/grades` → `grades`).
/// Returning to a page is not a new view.
class AnalyticsRouteObserver extends NavigatorObserver {
  static String? screenFor(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || !name.startsWith('/')) return null;
    final path = Uri.tryParse(name)?.path ?? name;
    if (path == '/') return 'home';
    return path.substring(1).replaceAll('/', '_');
  }

  void _report(Route<dynamic>? route) {
    final screen = route == null ? null : screenFor(route);
    if (screen != null) AppAnalytics.instance.screen(screen);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}
