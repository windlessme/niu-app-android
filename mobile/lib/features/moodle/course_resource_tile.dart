import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';

class CourseResourceTile extends StatelessWidget {
  const CourseResourceTile({
    super.key,
    required this.module,
    required this.onTap,
  });
  final Json module;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final files = module['contents'] is List
        ? (module['contents'] as List).whereType<Map>().toList()
        : <Map>[];
    final metadata = <String>[];
    if (files.length == 1) {
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
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              module['modname'] == 'folder'
                  ? CupertinoIcons.folder
                  : CupertinoIcons.doc_text,
              color: NiuColors.of(context).accent,
            ),
            const SizedBox(width: NiuSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plain(module['name']),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (metadata.isNotEmpty)
                    Text(
                      metadata.join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: NiuSpacing.sm),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: NiuColors.of(context).secondary,
            ),
          ],
        ),
      ),
    );
  }
}
