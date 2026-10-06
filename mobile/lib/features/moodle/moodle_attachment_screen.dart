import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/platform/downloaded_files.dart';
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
  bool cleared = false, busy = false;
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

  /// Writes the download once; opening and sharing reuse the same file.
  Future<File?> _file(Uint8List data) async {
    File? file;
    writing = () async {
      if (cleared) return;
      directory ??= await DownloadedFiles.folder('moodle-');
      final rawName =
          Uri.tryParse(widget.url)?.pathSegments.lastOrNull ?? widget.name;
      final name = rawName.replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]'), '_');
      file = File('${directory!.path}/${name.isEmpty ? 'attachment' : name}');
      if (!await file!.exists()) await file!.writeAsBytes(data, flush: true);
    }();
    await writing;
    widget.repository.requireCurrent();
    return cleared || !mounted ? null : file;
  }

  Future<void> open(Uint8List data) async {
    if (busy || cleared) return;
    setState(() => busy = true);
    try {
      final file = await _file(data);
      if (file == null) return;
      if (!await DownloadedFiles.open(file) && mounted) {
        showNiuMessage(context, '手機上沒有可以開啟這種檔案的 App，可以用「分享或儲存」');
      }
    } catch (_) {
      if (mounted) showNiuMessage(context, '無法開啟檔案，請重新下載後再試');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share(Uint8List data) async {
    if (busy || cleared) return;
    setState(() => busy = true);
    try {
      final file = await _file(data);
      if (file == null) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], title: widget.name),
      );
    } catch (_) {
      if (mounted) {
        showNiuMessage(context, '無法分享，請重新下載後再試');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    clear().whenComplete(() => CampusSession.instance.unregisterCleanup(clear));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(title: widget.name),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: SingleChildScrollView(
                child: NiuError(
                  title: '無法下載檔案',
                  message: '返回後再試一次；如果仍然失敗，請重新登入 M 園區。',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: NiuLoading(message: '正在下載檔案'));
          }
          final data = snapshot.data!;
          final path = Uri.parse(widget.url).path.toLowerCase();
          final image = RegExp(r'\.(png|jpg|jpeg|gif|webp)$').hasMatch(path);
          final text = RegExp(r'\.(txt|csv|md|log)$').hasMatch(path);
          final extension = path.contains('.')
              ? path.split('.').last.toUpperCase()
              : '檔案';
          return Column(
            children: [
              Expanded(
                child: image
                    ? InteractiveViewer(
                        child: Image.memory(
                          data,
                          semanticLabel: widget.name,
                          errorBuilder: (_, error, stack) => const Center(
                            child: NiuEmpty(
                              icon: Icons.broken_image_outlined,
                              title: '無法預覽這張圖片',
                              message: '仍然可以分享或儲存檔案。',
                            ),
                          ),
                        ),
                      )
                    : text
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(NiuSpacing.gutter),
                        child: NiuCard(
                          child: SelectableText(
                            utf8.decode(data, allowMalformed: true),
                          ),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          child: NiuEmpty(
                            icon: NiuIcons.file,
                            tone: NiuTone.accent,
                            title: widget.name,
                            message:
                                '$extension · ${(data.length / 1024).toStringAsFixed(1)} KB\n已下載完成，按「開啟」用手機上的 App 查看。',
                          ),
                        ),
                      ),
              ),
              NiuBottomBar(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            NiuSize.buttonHeight,
                          ),
                        ),
                        onPressed: busy ? null : () => share(data),
                        icon: const Icon(NiuIcons.share),
                        label: const Text('分享或儲存'),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            NiuSize.buttonHeight,
                          ),
                        ),
                        onPressed: busy ? null : () => open(data),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('開啟'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
