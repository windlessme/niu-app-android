import 'dart:convert';
import 'dart:typed_data';

import 'demo_account.dart';

/// A one-page PDF saying it is sample content, for certificates and files.
Uint8List demoPdf(String title) {
  final text = title.replaceAll(RegExp(r'[^\x20-\x7e]'), '');
  final stream =
      'BT /F1 22 Tf 72 720 Td (NIU-Life demo) Tj 0 -36 Td /F1 14 Tf '
      '($text) Tj 0 -24 Td (Sample content. Not an official document.) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, body) in objects.indexed) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n$body\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

/// Demo result text; store screenshots show what a student would see.
String demoNote(String text) => storeScreenshots ? text : '$text（示範模式，未送出到學校）';
