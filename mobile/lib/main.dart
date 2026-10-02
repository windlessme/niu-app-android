import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/analytics/app_analytics.dart';
import 'core/demo/demo_account.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'NIU-Life',
    ], await rootBundle.loadString('assets/LICENSE'));
  });
  // Store screenshots show only the app: no clock, signal or navigation bar.
  if (storeScreenshots) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // Analytics starts alongside the app; nothing waits on it.
  AppAnalytics.instance.start();
  runApp(const ProviderScope(child: NiuApp()));
}
