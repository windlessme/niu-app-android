import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../../core/session/campus_session.dart';
import 'registration_data.dart';

bool isCertificatePdf(int? status, String? contentType, List<int> bytes) =>
    status == 200 &&
    contentType?.split(';').first.trim().toLowerCase() == 'application/pdf' &&
    bytes.length >= 5 &&
    bytes.length <= 20 * 1024 * 1024 &&
    bytes[0] == 37 &&
    bytes[1] == 80 &&
    bytes[2] == 68 &&
    bytes[3] == 70 &&
    bytes[4] == 45;

class CertificateService {
  CertificateService(this.session, {Dio? client})
    : client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 40),
              followRedirects: false,
              responseType: ResponseType.bytes,
            ),
          ) {
    session.registerCleanup(clear);
  }

  final CampusSession session;
  final Dio client;
  static const channel = MethodChannel('niulife/registration');
  CancelToken? _request;
  bool _disposed = false;

  Future<bool> open(RegistrationData data, {required bool save}) async {
    final epoch = session.coordinator.epoch;
    final owner = session.account;
    void check() {
      session.coordinator.requireCurrent(epoch);
      if (_disposed ||
          !session.isSignedIn ||
          session.account != owner ||
          !data.belongsTo(owner) ||
          !data.printable) {
        throw StateError('無法確認目前登入身分或列印資格');
      }
    }

    check();
    _request?.cancel();
    final token = CancelToken();
    _request = token;
    // A separate client intentionally carries no acade cookies to ccsys.
    final response = await client.get<List<int>>(
      Uri.https(
        'ccsys.niu.edu.tw',
        '/MvcTeam/AcadeExport/StudyProved/${data.student}',
      ).toString(),
      cancelToken: token,
      options: Options(
        followRedirects: false,
        responseType: ResponseType.bytes,
      ),
    );
    check();
    final bytes = response.data ?? const <int>[];
    if (!isCertificatePdf(
      response.statusCode,
      response.headers.value('content-type'),
      bytes,
    )) {
      throw StateError('校方未回傳有效的 PDF');
    }
    final result = await channel.invokeMethod<bool>(
      save ? 'savePdf' : 'viewPdf',
      {'bytes': Uint8List.fromList(bytes)},
    );
    check();
    return result ?? false;
  }

  Future<void> clear() async {
    _request?.cancel();
    await channel.invokeMethod<void>('clear');
  }

  Future<void> dispose() async {
    _disposed = true;
    session.unregisterCleanup(clear);
    client.close(force: true);
    try {
      await clear();
    } catch (_) {}
  }
}
