import 'package:flutter/services.dart';

import '../../core/network/school_clients.dart';
import 'library_repository.dart';

class DemoLibraryRepository extends LibraryRepository {
  DemoLibraryRepository() : super(schoolClient('https://sso.niu.edu.tw'));

  @override
  Future<Uint8List> image(String account, LibraryCodeKind kind) async {
    final data = await rootBundle.load(
      kind == LibraryCodeKind.entrance
          ? 'assets/demo/qr_entrance.png'
          : 'assets/demo/qr_borrow.png',
    );
    return data.buffer.asUint8List();
  }
}
