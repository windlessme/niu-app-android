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
    this.session,
  });
  final bool allowOffline;
  final bool allowLocalAccount;
  final String title;
  final Widget child;

  /// Test seam; the app's session otherwise.
  final CampusSession? session;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final session = widget.session ?? CampusSession.instance;
  late final restoration = session.restore();

  /// This gate's own login screen is finishing a sign-in (M 園區, library,
  /// mail…); keep it until it is done. A sign-in made elsewhere (the home
  /// tab, another gate) shows the content right away: preloaded tabs are
  /// built while signed out and their login screens never complete.
  bool completingLogin = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: restoration,
    builder: (context, result) => ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!completingLogin &&
            (session.isSignedIn ||
                (session.hasLocalAccount &&
                    (widget.allowLocalAccount ||
                        (widget.allowOffline && session.isOffline))))) {
          return widget.child;
        }
        if (result.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: NiuLoading(message: '正在恢復登入')),
          );
        }
        return LoginScreen(
          session: widget.session,
          onCompleting: (busy) {
            if (mounted) setState(() => completingLogin = busy);
          },
          onSignedIn: () {
            if (mounted) setState(() => completingLogin = false);
          },
        );
      },
    ),
  );
}
