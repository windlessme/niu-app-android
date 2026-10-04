import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'credits_repository.dart';

class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key, this.repository});
  final CreditsRepository? repository;
  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  late final repository = widget.repository ?? CreditsRepository();
  CreditsSnapshot? snapshot;
  bool loading = true;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (snapshot == null) {
        final local = await repository.local();
        if (!mounted || request != generation) return;
        setState(() => snapshot = local);
      }
      final latest = await repository.refresh();
      if (!mounted || request != generation) return;
      setState(() => snapshot = latest);
    } catch (_) {
      if (!mounted || request != generation) return;
      setState(() => error = '名單更新失敗，稍後再試一次。');
    } finally {
      if (mounted && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '特別感謝',
      onRefresh: _load,
      children: [
        if (snapshot != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.xs),
            child: Text(
              snapshot!.document.introduction,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: NiuSpacing.lg),
          if (snapshot!.document.entries.isNotEmpty)
            NiuGroup(
              children: [
                for (final entry in snapshot!.document.entries)
                  NiuRow(
                    icon: NiuIcons.person,
                    hue: NiuHue.pink,
                    title: entry['name'] as String,
                    subtitle:
                        '${entry['description']}\n${entry['projectName']}',
                    maxSubtitleLines: 4,
                    onTap: () => openPublicUrl(
                      context,
                      Uri.parse(entry['url'] as String),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            '${snapshot!.source} · 修訂 ${snapshot!.document.revision}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
          if (snapshot!.message != null)
            Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.md),
              child: NiuBanner(
                tone: NiuTone.neutral,
                message: snapshot!.message!,
              ),
            ),
        ],
        if (loading) const NiuLoading(message: '正在更新名單', compact: true),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuBanner(
            tone: NiuTone.warning,
            message: error!,
            actionLabel: loading ? null : '重新整理',
            onAction: loading ? null : _load,
          ),
        ],
      ],
    );
  }
}
