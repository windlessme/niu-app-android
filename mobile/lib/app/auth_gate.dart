import 'package:flutter/material.dart';
import '../core/session/campus_session.dart';
import '../features/authentication/login_screen.dart';
import '../shared/shared.dart';

/// Restore once before routing; no extra unlock/confirmation screen.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.title,
    required this.child,
    this.allowOffline = false,
    this.allowLocalAccount = false,
  });
  final bool allowOffline;
  final bool allowLocalAccount;
  final String title;
  final Widget child;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final restoration = CampusSession.instance.restore();
  bool completingLogin = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: restoration,
    builder: (context, result) => ListenableBuilder(
      listenable: CampusSession.instance,
      builder: (context, _) {
        final session = CampusSession.instance;
        if (!completingLogin &&
            (session.isSignedIn ||
                (session.hasLocalAccount &&
                    (widget.allowLocalAccount ||
                        (widget.allowOffline && session.isOffline))))) {
          return widget.child;
        }
        if (result.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: AppLoadingState(message: '恢復登入中…')),
          );
        }
        completingLogin = true;
        return LoginScreen(
          onSignedIn: () {
            if (mounted) setState(() => completingLogin = false);
          },
        );
      },
    ),
  );
}
