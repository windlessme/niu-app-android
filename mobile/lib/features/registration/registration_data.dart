class RegistrationData {
  RegistrationData.fromJson(Map<String, dynamic> json)
    : student = json['student']?.toString().trim() ?? '',
      printable = json['printable'] == true,
      rows = (json['rows'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  final String student;
  final bool printable;
  final List<Map<String, dynamic>> rows;

  bool belongsTo(String? account) =>
      account != null &&
      student.isNotEmpty &&
      student.toLowerCase() == account.trim().toLowerCase() &&
      rows.isNotEmpty &&
      rows.every(
        (r) =>
            r['學號']?.toString().trim().toLowerCase() == student.toLowerCase(),
      );

  static String display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? '校方未提供' : text;
  }
}

// Verified ENR5020_01 DOM: #Q_STNO, #DataGrid and its actual TH labels.
// PAY1..PAY5 occur only in columnCodeAry1 on the inspected student page;
// that array describes a different grid layout and is NOT row data.
const registrationExtractScript = r'''
(() => {
  const docs = [];
  function collect(w) { try { docs.push(w.document); for(let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {} }
  collect(window);
  const doc = docs.find(d => d.location.hostname === 'acade.niu.edu.tw' &&
    d.location.pathname.toLowerCase().endsWith('/enr50/enr5020_01.aspx') && d.getElementById('DataGrid'));
  if (!doc) return null;
  const clean = v => String(v ?? '').replace(/\s+/g, ' ').trim();
  const grid = doc.getElementById('DataGrid');
  const header = [...grid.rows].find(r => r.querySelector('th'));
  if (!header) return null;
  const headings = [...header.cells].map(c => clean(c.textContent));
  if (!['學號','註冊學年期','註冊狀態','註冊日期'].every(h => headings.includes(h))) return null;
  const allowed = ['註冊學年期','學號','在學狀態','註冊狀態','註冊日期','超商繳費收據','收據上傳日期','備註',
    '學雜費','前學期學分費','就學貸款','請註冊假應註冊日期','欠書欠款','本學期註冊日期'];
  const rows = [...grid.rows].filter(r => r !== header && r.cells.length === headings.length && !r.querySelector('th'))
    .map(r => Object.fromEntries(headings.map((h,i) => [h, clean(r.cells[i].textContent) || null]).filter(([h]) => allowed.includes(h))));
  const button = doc.getElementById('GoToPrint');
  let valid = false;
  try { valid = typeof doc.defaultView.valideMessage === 'function' && doc.defaultView.valideMessage('Q_') === true; } catch (_) {}
  return JSON.stringify({student: clean(doc.getElementById('Q_STNO')?.value), rows,
    printable: !!button && !button.disabled && valid});
})()
''';
