import 'dart:convert';

import '../../core/demo/demo_documents.dart';
import 'moodle_question_screen.dart';

/// The review demo's quiz: its entry page, one attempt and the review.
/// Nothing reaches M 園區.
class DemoQuestionDriver implements MoodleQuestionDriver {
  var _step = 'view';
  var _answers = <String, List<String>>{};
  var _count = 0;

  void restart() {
    _step = 'view';
    _answers = {};
  }

  Map<String, Object?> get _page => switch (_step) {
    'attempt' => {
      'title': '隨堂小考',
      'text': '第 1 頁，共 1 頁',
      'fields': [
        {
          'id': 'q1',
          'kind': 'single',
          'label': '1. 堆疊（stack）的存取順序是？',
          'values': _answers['q1'] ?? [],
          'options': [
            {'id': 'q1a', 'label': '先進先出（FIFO）', 'disabled': false},
            {'id': 'q1b', 'label': '後進先出（LIFO）', 'disabled': false},
          ],
          'required': false,
          'disabled': false,
        },
        {
          'id': 'q2',
          'kind': 'multiple',
          'label': '2. 下列哪些是線性資料結構？',
          'values': _answers['q2'] ?? [],
          'options': [
            {'id': 'q2a', 'label': '陣列', 'disabled': false},
            {'id': 'q2b', 'label': '鏈結串列', 'disabled': false},
            {'id': 'q2c', 'label': '二元樹', 'disabled': false},
          ],
          'required': false,
          'disabled': false,
        },
      ],
      'actions': [
        {
          'id': 'finish',
          'label': '結束作答並送出',
          'disabled': false,
          'fieldIDs': ['q1', 'q2'],
        },
      ],
    },
    'review' => {
      'title': '隨堂小考',
      'text': '',
      'fields': [],
      'actions': [
        {
          'id': 'done',
          'label': '完成複習',
          'disabled': false,
          'fieldIDs': [],
          'isNavigation': true,
        },
      ],
      'result': {
        'grade': _correct == 2 ? '10.00 / 10.00' : '${_correct * 5}.00 / 10.00',
        'gradeLabel': '最後成績',
        'information': [
          {'id': 'i1', 'label': '狀態', 'value': '已完成'},
        ],
        'attempts': [],
        'notices': [demoNote('已模擬送出')],
      },
      'reviewQuestions': [
        {
          'id': 'r1',
          'title': '題目 1',
          'text': '堆疊（stack）的存取順序是？',
          'prompt': '',
          'status': '已完成',
          'verdict': _answers['q1']?.contains('q1b') == true
              ? 'correct'
              : 'incorrect',
          'mark': '得分 ${_answers['q1']?.contains('q1b') == true ? 5 : 0} / 5',
          'choices': [
            {
              'id': 'c1',
              'text': '先進先出（FIFO）',
              'selected': _answers['q1']?.contains('q1a') == true,
              'verdict': null,
              'feedback': '',
            },
            {
              'id': 'c2',
              'text': '後進先出（LIFO）',
              'selected': _answers['q1']?.contains('q1b') == true,
              'verdict': 'correct',
              'feedback': '',
            },
          ],
          'responses': [],
          'correctAnswer': '正確答案：後進先出（LIFO）',
          'feedback': '',
          'generalFeedback': '堆疊最後放入的元素最先取出。',
          'comment': '',
        },
      ],
    },
    _ => {
      'title': '隨堂小考',
      'text': '本測驗共 2 題，限作答 1 次。\n作答時間 10 分鐘。',
      'fields': [],
      'actions': [
        {'id': 'start', 'label': '開始作答', 'disabled': false, 'fieldIDs': []},
      ],
    },
  };

  int get _correct =>
      (_answers['q1']?.contains('q1b') == true ? 1 : 0) +
      (_answers['q2']?.toSet().containsAll({'q2a', 'q2b'}) == true &&
              _answers['q2']?.contains('q2c') != true
          ? 1
          : 0);

  String get _revision => '$_step:$_count';

  @override
  Future<String?> snapshot() async =>
      jsonEncode({'revision': _revision, 'webReason': null, ..._page});

  @override
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  ) async {
    if (revision != _revision) return 'changed';
    _answers = {..._answers, ...answers};
    _step = switch (actionId) {
      'start' => 'attempt',
      'finish' => 'review',
      _ => 'view',
    };
    _count++;
    return 'invoked';
  }

  @override
  Future<String?> stage(
    String revision,
    Map<String, List<String>> answers,
  ) async => 'staged';

  @override
  Future<void> focus(String questionId) async {}
}
