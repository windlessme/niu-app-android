import 'package:flutter/material.dart';
import '../../core/web/academic_portal_screen.dart';
import 'graduation_dashboard.dart';

class GraduationData {
  GraduationData.fromJson(Map<String, dynamic> json)
    : hours = normalizeHours(
        (json['diverseHours'] as List? ?? []).map((v) => v.toString()).toList(),
      ),
      english = json['englishAbility']?.toString() ?? '',
      fitness = json['physicalFitness']?.toString() ?? '',
      credits = (json['creditRequired'] as List? ?? [])
          .map((v) => v.toString())
          .toList(),
      program = json['creditCourse']?.toString() ?? '';
  final List<String> hours, credits;
  final String english, fitness, program;
  static List<String> normalizeHours(List<String> values) =>
      values.length == 4 ? values.expand((v) => [v, '不計入']).toList() : values;
}

const graduationExtractScript = r'''
(() => {
  const docs = [];
  function collect(w) {
    try { docs.push(w.document); for (let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {}
  }
  collect(window);
  const doc = docs.find(d => d.getElementById('div_B'));
  if (!doc) return null;
  const diverse = doc.getElementById('div_B');
  if (!diverse) return null;
  const ability = label => doc.querySelector('span[ml="' + label + '"]')?.closest('tr')?.querySelector('div')?.innerText || '';
  const credits = [];
  doc.querySelectorAll('tr.tdWhite').forEach(r => {
    if (r.cells[0]?.innerText.trim() === '畢業最低學分數') {
      credits.push(r.cells[1]?.innerText.trim() || '', r.cells[2]?.innerText.trim() || '');
    }
  });
  return JSON.stringify({diverseHours: diverse.innerText.match(/\d+/g) || [],
    englishAbility: ability('PL_外語能力'), physicalFitness: ability('PL_體適能'),
    creditRequired: credits, creditCourse: doc.getElementById('CRS_PROG')?.innerText || ''});
})()
''';

class GraduationScreen extends StatelessWidget {
  const GraduationScreen({super.key});
  @override
  Widget build(BuildContext context) => AcademicPortalScreen(
    title: '畢業門檻',
    referer: Uri.parse(
      'https://acade.niu.edu.tw/NIU/Application/ENR/ENRG0/ENRG010_03.aspx',
    ),
    target: Uri.parse(
      'https://acade.niu.edu.tw/NIU/Application/ENR/ENRG0/ENRG010_01.aspx',
    ),
    extractScript: graduationExtractScript,
    snapshotBuilder: (context, value) {
      final data = GraduationData.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      return GraduationDashboard(data: data);
    },
  );
}
