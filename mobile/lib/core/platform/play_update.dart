import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../demo/demo_account.dart';

/// Google Play flexible in-app update. Play shows its own consent sheet once
/// per new version; the download runs in the background and a snackbar offers
/// the restart. Only Play-installed release builds get answers from Play, so
/// sideloaded previews and debug builds skip it.
class PlayUpdate {
  PlayUpdate(this.messenger);
  final GlobalKey<ScaffoldMessengerState> messenger;

  static const _promptedKey = 'playUpdatePromptedVersion';

  Future<void> check() async {
    if (!kReleaseMode || storeScreenshots || !Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        _offerRestart();
        return;
      }
      final version = info.availableVersionCode;
      if (info.updateAvailability != UpdateAvailability.updateAvailable ||
          !info.flexibleUpdateAllowed ||
          version == null) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_promptedKey) == version) return;
      await prefs.setInt(_promptedKey, version);
      // Completes once the download has finished.
      if (await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success) {
        _offerRestart();
      }
    } catch (_) {
      /* Not installed from Play, offline, or Play unavailable. */
    }
  }

  void _offerRestart() {
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('新版本已下載完成'),
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: '重新啟動',
            onPressed: () =>
                InAppUpdate.completeFlexibleUpdate().catchError((Object _) {}),
          ),
        ),
      );
  }
}
