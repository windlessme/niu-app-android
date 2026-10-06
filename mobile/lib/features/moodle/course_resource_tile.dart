import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';

/// One course material inside a week's grouped list.
class CourseResourceTile extends StatelessWidget {
  const CourseResourceTile({
    super.key,
    required this.module,
    required this.onTap,
  });
  final Json module;
  final VoidCallback onTap;

  static (IconData, NiuHue) glyph(Json module) {
    final files = module['contents'] is List
        ? (module['contents'] as List).whereType<Map>().toList()
        : <Map>[];
    final mime = files.length == 1 ? '${files.first['mimetype']}' : '';
    return switch ('${module['modname']}') {
      'folder' => (NiuIcons.folder, NiuHue.amber),
      'url' => (NiuIcons.link, NiuHue.cyan),
      'assign' => (NiuIcons.assignment, NiuHue.orange),
      'forum' => (NiuIcons.forum, NiuHue.purple),
      'page' => (Icons.article_outlined, NiuHue.green),
      'attendance' => (NiuIcons.attendance, NiuHue.cyan),
      'quiz' => (Icons.quiz_outlined, NiuHue.pink),
      _ when mime == 'application/pdf' => (
        Icons.picture_as_pdf_outlined,
        NiuHue.red,
      ),
      _ => (NiuIcons.file, NiuHue.blue),
    };
  }

  @override
  Widget build(BuildContext context) {
    final files = module['contents'] is List
        ? (module['contents'] as List).whereType<Map>().toList()
        : <Map>[];
    final metadata = <String>[];
    final kind = '${module['modname']}';
    final label = const {
      'page': '頁面',
      'forum': '討論區',
      'assign': '作業',
      'url': '連結',
      'attendance': '出席紀錄',
      'quiz': '測驗',
    }[kind];
    if (label != null) {
      metadata.add(label);
    } else if (files.length == 1) {
      final mime = files.first['mimetype'];
      if (mime == 'application/pdf') metadata.add('PDF');
      final size = num.tryParse('${files.first['filesize']}');
      if (size != null && size > 0) {
        metadata.add(
          size >= 1048576
              ? '${(size / 1048576).toStringAsFixed(1)} MB'
              : '${(size / 1024).ceil()} KB',
        );
      }
    } else if (files.length > 1) {
      metadata.add('${files.length} 個檔案');
    }
    final (icon, hue) = glyph(module);
    return NiuRow(
      icon: icon,
      hue: hue,
      title: plain(module['name']),
      subtitle: metadata.join(' · '),
      onTap: onTap,
    );
  }
}
