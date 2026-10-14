import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// M 園區's login code: five digits in one flat colour over filled shapes,
/// hairlines and dots. Glyph strokes are 2–3 px, so the digit colour is the
/// one with plenty of 2×2 blocks but no solid 4×4 block; the shapes have
/// both and the lines neither. Everything runs on the device.
///
/// Returns a width×height mask (true = ink), or null when no colour fits.
List<bool>? captchaDigitMask(Uint8List rgba, int width, int height) {
  int at(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
  }

  final counts = <int, int>{};
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      counts.update(at(x, y), (n) => n + 1, ifAbsent: () => 1);
    }
  }
  if (counts.isEmpty) return null;
  final background = counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;

  bool solid(int x, int y, int size, int color) {
    for (var dy = 0; dy < size; dy++) {
      for (var dx = 0; dx < size; dx++) {
        if (at(x + dx, y + dy) != color) return false;
      }
    }
    return true;
  }

  int? best;
  var bestBlocks = 0;
  for (final MapEntry(key: color, value: n) in counts.entries) {
    if (color == background || n < 60) continue;
    var blocks = 0, thick = false;
    for (var y = 0; y + 1 < height && !thick; y++) {
      for (var x = 0; x + 1 < width; x++) {
        if (at(x, y) != color || !solid(x, y, 2, color)) continue;
        blocks++;
        if (x + 3 < width && y + 3 < height && solid(x, y, 4, color)) {
          thick = true;
          break;
        }
      }
    }
    if (!thick && blocks >= 40 && blocks > bestBlocks) {
      best = color;
      bestBlocks = blocks;
    }
  }
  if (best == null) return null;
  final ink = [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) at(x, y) == best,
  ];
  // Stray dots share the colour; a glyph pixel always has inked neighbours.
  return [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++)
        ink[y * width + x] && _neighbours(ink, width, height, x, y) >= 2,
  ];
}

int _neighbours(List<bool> ink, int width, int height, int x, int y) {
  var n = 0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      final nx = x + dx, ny = y + dy;
      if (nx >= 0 && ny >= 0 && nx < width && ny < height) {
        if (ink[ny * width + nx]) n++;
      }
    }
  }
  return n;
}

/// Five digits from OCR text, mapping the usual look-alikes; null otherwise.
String? captchaDigits(String text) {
  const alike = {
    'O': '0', 'o': '0', 'D': '0', 'Q': '0', //
    'I': '1', 'l': '1', 'i': '1', '|': '1', '/': '1', //
    'Z': '2', 'z': '2', 'S': '5', 's': '5', 'G': '6', 'b': '6', //
    'T': '7', 'B': '8', 'g': '9', 'q': '9',
  };
  final digits = [
    for (final c in text.split(''))
      if (RegExp(r'\d').hasMatch(c)) c else ?alike[c],
  ].join();
  return digits.length == 5 ? digits : null;
}

/// Reads text from a PNG; injectable for tests.
typedef CaptchaTextReader = Future<String> Function(Uint8List png);

/// Reads M 園區's login code from the page's PNG, or null when unsure:
/// two renderings must agree, or the only complete one is used.
Future<String?> readMoodleCaptcha(
  Uint8List png, {
  CaptchaTextReader read = recognizeCaptchaText,
}) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final width = image.width, height = image.height;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  codec.dispose();
  if (data == null) return null;
  final mask = captchaDigitMask(data.buffer.asUint8List(), width, height);
  if (mask == null) return null;
  final votes = <String>[];
  for (final bold in const [false, true]) {
    final text = await read(await _render(mask, width, height, bold: bold));
    final code = captchaDigits(text);
    if (code != null) {
      if (votes.contains(code)) return code;
      votes.add(code);
    }
  }
  return votes.length == 1 ? votes.single : null;
}

/// Black digits on white, 4× and padded, optionally thickened by a pixel.
Future<Uint8List> _render(
  List<bool> mask,
  int width,
  int height, {
  required bool bold,
}) async {
  const scale = 4, pad = 12;
  final w = width * scale + pad * 2, h = height * scale + pad * 2;
  final out = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  bool inked(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return mask[y * width + x];
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final on =
          inked(x, y) ||
          bold && (inked(x - 1, y) || inked(x + 1, y) || inked(x, y - 1));
      if (!on) continue;
      for (var sy = 0; sy < scale; sy++) {
        for (var sx = 0; sx < scale; sx++) {
          final i = ((pad + y * scale + sy) * w + pad + x * scale + sx) * 4;
          out[i] = out[i + 1] = out[i + 2] = 0;
        }
      }
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(out);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return bytes!.buffer.asUint8List();
}

/// On-device ML Kit; characters joined left to right whatever their line.
Future<String> recognizeCaptchaText(Uint8List png) async {
  final dir = await Directory(
    '${(await getTemporaryDirectory()).path}/moodle-captcha',
  ).create(recursive: true);
  final file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.png');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    await file.writeAsBytes(png, flush: true);
    final result = await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    );
    final symbols = [
      for (final block in result.blocks)
        for (final line in block.lines)
          for (final element in line.elements)
            if (element.symbols.isEmpty)
              (element.boundingBox.left, element.text)
            else
              for (final s in element.symbols) (s.boundingBox.left, s.text),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return symbols.map((s) => s.$2).join();
  } catch (_) {
    return '';
  } finally {
    await recognizer.close();
    if (await file.exists()) await file.delete();
  }
}
