import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'niu_widgets.dart';

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message = '載入中…'});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.title = '暫時無法載入',
    this.message = '請稍後再試。',
    this.onRetry,
  });
  final String title, message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => NiuEmptyState(
    title: title,
    message: message,
    icon: CupertinoIcons.exclamationmark_circle,
    action: onRetry == null
        ? null
        : TextButton(onPressed: onRetry, child: const Text('重試')),
  );
}
