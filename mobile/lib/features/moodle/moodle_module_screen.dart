import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';
import 'moodle_links.dart';

class MoodleModuleScreen extends StatelessWidget {
  const MoodleModuleScreen({
    super.key,
    required this.repository,
    required this.module,
  });
  final MoodleRepository repository;
  final Json module;
  @override
  Widget build(BuildContext context) {
    final contents = objects(module['contents'] ?? []);
    final description = plain(module['description']);
    return NiuScrollPage(
      title: plain(module['name']),
      bottomBar: module['url'] is String
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(NiuSize.buttonHeight),
              ),
              icon: const Icon(NiuIcons.external, size: 18),
              onPressed: () => openMoodleUrl(
                context,
                repository,
                '${module['url']}',
                plain(module['name']),
              ),
              label: const Text('在 M 園區開啟'),
            )
          : null,
      children: [
        if (description.isNotEmpty) ...[
          NiuCard(child: SelectableText(description)),
          const SizedBox(height: NiuSpacing.lg),
        ],
        if (contents.isNotEmpty)
          NiuGroup(
            children: [
              for (final content in contents)
                NiuRow(
                  icon: content['type'] == 'url'
                      ? NiuIcons.link
                      : NiuIcons.file,
                  hue: content['type'] == 'url' ? NiuHue.cyan : NiuHue.blue,
                  title: plain(content['filename'] ?? '開啟資源'),
                  subtitle: content['filesize'] == null
                      ? null
                      : _fileSize(content['filesize']),
                  onTap: content['fileurl'] is String
                      ? () => openMoodleUrl(
                          context,
                          repository,
                          '${content['fileurl']}',
                          plain(module['name']),
                          file: content['type'] == 'file',
                        )
                      : null,
                ),
            ],
          ),
        if (contents.isEmpty && description.isEmpty)
          const NiuEmpty(
            icon: NiuIcons.file,
            title: '這裡沒有可預覽的內容',
            message: '點下方按鈕在 M 園區查看完整內容。',
          ),
      ],
    );
  }
}

String _fileSize(Object? raw) {
  final size = num.tryParse('$raw');
  if (size == null || size <= 0) return '';
  return size >= 1048576
      ? '${(size / 1048576).toStringAsFixed(1)} MB'
      : '${(size / 1024).ceil()} KB';
}
