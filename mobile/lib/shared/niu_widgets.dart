import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'app_cards.dart';

class NiuCard extends StatelessWidget {
  const NiuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => AppCard(padding: padding, child: child);
}

class NiuEmptyState extends StatelessWidget {
  const NiuEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = CupertinoIcons.info_circle,
    this.action,
  });
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => NiuCard(
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message),
          ?action,
        ],
      ),
    ),
  );
}

Future<void> openPublicUrl(BuildContext context, Uri url) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    return;
  }
  try {
    await InAppBrowser.openWithSystemBrowser(url: WebUri.uri(url));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟連結，請稍後再試。')));
    }
  }
}
