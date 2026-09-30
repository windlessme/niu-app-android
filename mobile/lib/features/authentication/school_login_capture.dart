/// Origin checks for the school SSO login page.
bool isSchoolLoginOrigin(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.host == 'ccsys1.niu.edu.tw' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty;

bool isSchoolLoginPage(Uri? uri) =>
    isSchoolLoginOrigin(uri) && uri!.path == '/SSO/login';

class SubmittedSchoolCredentials {
  const SubmittedSchoolCredentials(this.account, this.password);
  final String account;
  final String password;

  static SubmittedSchoolCredentials? fromMessage(
    Object? message, {
    required Uri? page,
    required String capability,
  }) {
    if (!isSchoolLoginOrigin(page) || message is! Map) return null;
    if (message['capability'] != capability) return null;
    final account = message['account'];
    final password = message['password'];
    if (account is! String ||
        password is! String ||
        account.trim().isEmpty ||
        password.isEmpty ||
        account.length > 256 ||
        password.length > 4096) {
      return null;
    }
    return SubmittedSchoolCredentials(account.trim().toLowerCase(), password);
  }
}
