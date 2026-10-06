import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Downloaded attachments that can be handed to another app. Files must live
/// under [directory]; Android only opens files from there.
class DownloadedFiles {
  const DownloadedFiles._();
  static const channel = MethodChannel('niulife/files');

  /// A fresh private folder for one download, deleted by its owner.
  static Future<Directory> folder(String prefix) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/attachments',
    );
    await root.create(recursive: true);
    return root.createTemp(prefix);
  }

  /// Opens [file] in an app that can view it. False when none is installed.
  static Future<bool> open(File file) async =>
      await channel.invokeMethod<bool>('open', {'path': file.path}) ?? false;
}
