import '../../core/demo/demo_data.dart';
import 'postal_models.dart';
import 'postal_service.dart';

class DemoPostalService extends PostalService {
  @override
  Future<PostalPage> search(PostalQuery query) async {
    final q = query.normalized;
    if (!q.canSearch) {
      throw const PostalException('請填寫收件人、手機號碼或郵件號碼其中一項。');
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return PostalPage(
      records: [
        for (final r in DemoData.postal)
          if (r['status'] == q.status.name)
            PostalRecord(
              sequence: r['sequence']!,
              receivedDate: r['receivedDate']!,
              trackingNumber: r['trackingNumber']!,
              unit: r['unit']!,
              recipient: q.name.isEmpty ? DemoData.studentName : q.name,
              category: r['category']!,
              quantity: r['quantity']!,
              signature: r['signature']!,
              completedDate: r['completedDate']!,
              note: '',
              status: q.status,
            ),
      ],
      query: q,
      pageIndex: 0,
      pageCount: 1,
    );
  }

  @override
  Future<PostalPage> nextPage(PostalPage page) async =>
      throw const PostalException('沒有更多結果');
}
