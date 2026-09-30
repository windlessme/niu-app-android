import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_icons.dart';
import 'relative_update_text.dart';

enum NiuTone { neutral, accent, success, warning, error }

extension NiuToneColors on NiuTone {
  Color foreground(BuildContext context) {
    final c = NiuColors.of(context);
    return switch (this) {
      NiuTone.neutral => c.inkSecondary,
      NiuTone.accent => c.accent,
      NiuTone.success => c.success,
      NiuTone.warning => c.warning,
      NiuTone.error => c.error,
    };
  }

  Color background(BuildContext context) {
    final c = NiuColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      NiuTone.neutral => c.fill,
      NiuTone.accent => c.accentSoft,
      _ => foreground(context).withValues(alpha: dark ? .16 : .1),
    };
  }

  IconData get icon => switch (this) {
    NiuTone.neutral => NiuIcons.info,
    NiuTone.accent => NiuIcons.info,
    NiuTone.success => NiuIcons.success,
    NiuTone.warning => NiuIcons.warning,
    NiuTone.error => NiuIcons.error,
  };
}

/// Centered progress with a short, specific message.
class NiuLoading extends StatelessWidget {
  const NiuLoading({super.key, this.message = '載入中', this.compact = false});
  final String message;
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    excludeSemantics: true,
    child: Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? NiuSpacing.lg : NiuSpacing.huge,
        horizontal: NiuSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: NiuColors.of(context).inkSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Empty, first-run and error states share one composition:
/// tinted glyph, headline, one supporting sentence, optional action.
class NiuEmpty extends StatelessWidget {
  const NiuEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = NiuIcons.info,
    this.tone = NiuTone.neutral,
    this.action,
    this.secondaryAction,
    this.padding = const EdgeInsets.symmetric(
      vertical: NiuSpacing.huge,
      horizontal: NiuSpacing.xxl,
    ),
  });
  final String title;
  final String? message;
  final IconData icon;
  final NiuTone tone;
  final Widget? action;
  final Widget? secondaryAction;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tone.background(context),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: tone.foreground(context)),
            ),
          ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: NiuSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: NiuColors.of(context).inkSecondary,
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: NiuSpacing.xl),
            action!,
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: NiuSpacing.xs),
            secondaryAction!,
          ],
        ],
      ),
    );
  }
}

class NiuError extends StatelessWidget {
  const NiuError({
    super.key,
    this.title = '暫時無法載入',
    this.message = '檢查網路連線後再試一次。',
    this.onRetry,
    this.secondaryAction,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final Widget? secondaryAction;
  @override
  Widget build(BuildContext context) => NiuEmpty(
    title: title,
    message: message,
    icon: NiuIcons.offline,
    tone: NiuTone.warning,
    action: onRetry == null
        ? null
        : FilledButton.tonal(onPressed: onRetry, child: const Text('再試一次')),
    secondaryAction: secondaryAction,
  );
}

/// Inline notice for page-level conditions (offline, expired login, stale data).
class NiuBanner extends StatelessWidget {
  const NiuBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = NiuTone.accent,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
  final String? title;
  final String message;
  final NiuTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = tone.foreground(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: tone.background(context),
          borderRadius: BorderRadius.circular(NiuRadius.lg),
        ),
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.lg,
          NiuSpacing.md,
          NiuSpacing.sm,
          NiuSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon ?? tone.icon, size: 20, color: fg),
            ),
            const SizedBox(width: NiuSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: NiuSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: NiuColors.of(context).ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NiuColors.of(context).ink.withValues(alpha: .8),
                      ),
                    ),
                    if (actionLabel != null && onAction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: NiuSpacing.xs),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: fg,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.padded,
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer describing freshness of device-cached school data.
class NiuSyncStatus extends StatelessWidget {
  const NiuSyncStatus({
    super.key,
    required this.updatedAt,
    this.refreshing = false,
    this.failed = false,
    this.offline = false,
    this.onRetry,
  });
  final DateTime? updatedAt;
  final bool refreshing, failed, offline;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final (icon, text, color) = refreshing
        ? (NiuIcons.refresh, '正在更新', colors.inkSecondary)
        : failed
        ? (NiuIcons.warning, '更新失敗，顯示上次的資料', colors.warning)
        : offline
        ? (NiuIcons.offline, '離線中，顯示上次的資料', colors.inkSecondary)
        : (
            NiuIcons.history,
            formatRelativeUpdate(updatedAt),
            colors.inkTertiary,
          );
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (refreshing)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
          if (failed && onRetry != null && !refreshing) ...[
            const SizedBox(width: NiuSpacing.xs),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.sm),
                textStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: onRetry,
              child: const Text('重試'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder block for skeleton layouts.
class NiuSkeleton extends StatelessWidget {
  const NiuSkeleton({super.key, this.height = 16, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: NiuColors.of(context).fill,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}
