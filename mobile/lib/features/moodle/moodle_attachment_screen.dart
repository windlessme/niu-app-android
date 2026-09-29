import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';

class MoodleAttachmentScreen extends StatefulWidget {
  const MoodleAttachmentScreen({
    super.key,
    required this.repository,
    required this.url,
    required this.name,
  });
  final MoodleRepository repository;
  final String url, name;
  @override
  State<MoodleAttachmentScreen> createState() => _MoodleAttachmentScreenState();
}

class _MoodleAttachmentScreenState extends State<MoodleAttachmentScreen> {
  late final Future<Uint8List> bytes = widget.repository.download(widget.url);
  Directory? directory;
  Future<void>? writing;
  bool cleared = false, sharing = false;
  @override
  void initState() {
    super.initState();
    CampusSession.instance.registerCleanup(clear);
  }

  Future<void> clear() async {
    cleared = true;
    try {
      await writing;
    } catch (_) {}
    final dir = directory;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> share(Uint8List data) async {
    if (sharing || cleared) return;
    setState(() => sharing = true);
    try {
      widget.repository.requireCurrent();
      File? file;
      writing = () async {
        final root = await getTemporaryDirectory();
        if (cleared) return;
        directory ??= await Directory('${root.path}/moodle-').createTemp();
        final rawName =
            Uri.tryParse(widget.url)?.pathSegments.lastOrNull ?? widget.name;
        final name = rawName.replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]'), '_');
        file = File('${directory!.path}/${name.isEmpty ? 'attachment' : name}');
        await file!.writeAsBytes(data, flush: true);
      }();
      await writing;
      widget.repository.requireCurrent();
      if (cleared || file == null || !mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file!.path)], title: widget.name),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法分享附件，請重新下載。')));
      }
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  void dispose() {
    clear().whenComplete(() => CampusSession.instance.unregisterCleanup(clear));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: IosPageHeader(title: widget.name),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('無法下載附件，請返回後重試或重新登入。'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final path = Uri.parse(widget.url).path.toLowerCase();
          final image = RegExp(r'\.(png|jpg|jpeg|gif|webp)$').hasMatch(path);
          final text = RegExp(r'\.(txt|csv|md|log)$').hasMatch(path);
          return Column(
            children: [
              Expanded(
                child: image
                    ? InteractiveViewer(
                        child: Image.memory(
                          data,
                          semanticLabel: widget.name,
                          errorBuilder: (_, error, stack) =>
                              const Center(child: Text('無法預覽此圖片，仍可分享檔案。')),
                        ),
                      )
                    : text
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(NiuSpacing.xl),
                        child: SelectableText(
                          utf8.decode(data, allowMalformed: true),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(NiuSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                size: 64,
                              ),
                              const SizedBox(height: NiuSpacing.xl),
                              Text(
                                widget.name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: NiuSpacing.sm),
                              Text(
                                '${(data.length / 1024).toStringAsFixed(1)} KB',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: NiuSpacing.md),
                              const Text('附件已下載，可分享至支援此格式的 App 檢視。'),
                            ],
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(NiuSpacing.xl),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: sharing ? null : () => share(data),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('分享／儲存附件'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
