import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'mail_models.dart';

/// NUMail's sign-in code is an svg-captcha: one filled path per character
/// plus stroke-only noise lines. Only that subset is parsed — no scripts,
/// links or entities — and drawn locally; nothing leaves the device.
class CaptchaShape {
  CaptchaShape(this.width, this.height, this.glyphs);
  final double width, height;
  final List<ui.Path> glyphs;

  static CaptchaShape parse(String svg) {
    if (svg.length > 256000 ||
        svg.contains('<!DOCTYPE') ||
        svg.contains('<!ENTITY') ||
        svg.contains('<script')) {
      throw const MailException('驗證碼格式無法辨識');
    }
    final box = RegExp(r'viewBox="([^"]+)"').firstMatch(svg)?[1];
    final numbers = [
      for (final n in (box ?? '').split(RegExp(r'[\s,]+'))) ?double.tryParse(n),
    ];
    if (numbers.length != 4 ||
        numbers[2] <= 0 ||
        numbers[3] <= 0 ||
        numbers[2] > 512 ||
        numbers[3] > 256) {
      throw const MailException('驗證碼格式無法辨識');
    }
    final glyphs = <ui.Path>[];
    for (final tag in RegExp(r'<path\b([^>]*)/?>').allMatches(svg)) {
      final attrs = tag[1]!;
      // Stroke-only paths are the noise lines across the code.
      if (RegExp(r'fill="none"').hasMatch(attrs)) continue;
      final d = RegExp(r'\bd="([^"]*)"').firstMatch(attrs)?[1];
      final path = d == null ? null : _path(d);
      if (path == null) throw const MailException('驗證碼格式無法辨識');
      glyphs.add(path);
    }
    if (glyphs.isEmpty || glyphs.length > 8) {
      throw const MailException('驗證碼格式無法辨識');
    }
    return CaptchaShape(numbers[2], numbers[3], glyphs);
  }

  static ui.Path? _path(String d) {
    final tokens = RegExp(
      r'[MLQCZmlqcz]|-?\d*\.?\d+(?:e-?\d+)?',
    ).allMatches(d).map((m) => m[0]!).toList();
    final path = ui.Path();
    var i = 0, command = '', started = false, steps = 0;
    double? next() {
      if (i >= tokens.length) return null;
      final v = double.tryParse(tokens[i]);
      if (v == null || !v.isFinite || v.abs() > 10000) return null;
      i++;
      return v;
    }

    while (i < tokens.length) {
      if (++steps > 10000) return null;
      if (RegExp(r'^[A-Za-z]$').hasMatch(tokens[i])) command = tokens[i++];
      switch (command) {
        case 'M':
          final x = next(), y = next();
          if (x == null || y == null) return null;
          path.moveTo(x, y);
          started = true;
          command = 'L';
        case 'L':
          final x = next(), y = next();
          if (!started || x == null || y == null) return null;
          path.lineTo(x, y);
        case 'Q':
          final a = next(), b = next(), x = next(), y = next();
          if (!started || [a, b, x, y].contains(null)) return null;
          path.quadraticBezierTo(a!, b!, x!, y!);
        case 'C':
          final a = next(), b = next(), c = next(), e = next();
          final x = next(), y = next();
          if (!started || [a, b, c, e, x, y].contains(null)) return null;
          path.cubicTo(a!, b!, c!, e!, x!, y!);
        case 'Z' || 'z':
          if (!started) return null;
          path.close();
          command = '';
        default:
          return null;
      }
    }
    return started ? path : null;
  }

  /// Black glyphs on white, [scale]× the SVG size, as PNG.
  Future<Uint8List> png({double scale = 4}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width * scale, height * scale),
      ui.Paint()..color = const ui.Color(0xffffffff),
    );
    canvas.scale(scale);
    final ink = ui.Paint()..color = const ui.Color(0xff000000);
    for (final glyph in glyphs) {
      canvas.drawPath(glyph, ink);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * scale).round(),
      (height * scale).round(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

/// Six letters or digits, or null.
String? captchaCandidate(String text) {
  final compact = text.replaceAll(RegExp(r'\s'), '');
  return RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(compact) ? compact : null;
}

/// Reads a rendered code; null when unsure.
typedef CaptchaReader = Future<String?> Function(Uint8List png);

/// On-device ML Kit recognition of a rendered code.
Future<String?> readCaptcha(Uint8List png) async {
  final dir = await Directory(
    '${(await getTemporaryDirectory()).path}/numail-captcha',
  ).create(recursive: true);
  final file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.png');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    await file.writeAsBytes(png, flush: true);
    final result = await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    );
    final lines = [
      for (final block in result.blocks)
        for (final line in block.lines) line,
    ]..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    return captchaCandidate(lines.map((l) => l.text).join());
  } catch (_) {
    return null;
  } finally {
    await recognizer.close();
    if (await file.exists()) await file.delete();
  }
}
