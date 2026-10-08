import 'dart:convert';

import '../../core/demo/demo_documents.dart';
import 'moodle_question_screen.dart';

/// The review demo's quiz: its entry page, a timed two-page attempt, the
/// summary, Moodle's submit confirmation and the review. Nothing reaches
/// M 園區.
class DemoQuestionDriver implements MoodleQuestionDriver {
  DemoQuestionDriver({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  var _step = 'view';
  var _page = 1;
  var _answers = <String, List<String>>{};
  var _count = 0;
  DateTime? _started;

  static const _limit = Duration(minutes: 10);
  static const _defaultOrder = ['o1', 'o2', 'o3'];

  void restart() {
    _step = 'view';
    _page = 1;
    _answers = {};
    _started = null;
  }

  static Map<String, Object?> _option(String id, String label) => {
    'id': id,
    'label': label,
    'disabled': false,
  };

  static Map<String, Object?> _blank(String id) => {
    ..._option(id, '選擇...'),
    'blank': true,
  };

  Map<String, Object?> _field(
    String id,
    String kind,
    String question,
    List<Map<String, Object?>> options, {
    String? label,
    String? part,
    String? context,
    List<String> values = const [],
  }) => {
    'id': id,
    'kind': kind,
    'label': label ?? part ?? '作答',
    'values': _answers[id] ?? values,
    'options': options,
    'required': false,
    'disabled': false,
    'context': context,
    'questionID': question,
    'part': part,
  };

  bool _answered(int number) => switch (number) {
    1 => _answers['q1']?.isNotEmpty == true,
    2 => _answers['q2']?.isNotEmpty == true,
    3 => [
      'q3a',
      'q3b',
    ].every((id) => _answers[id]?.any((v) => !v.endsWith('0')) == true),
    // Moodle's default order only counts once moved.
    _ => (_answers['q4'] ?? _defaultOrder).join() != _defaultOrder.join(),
  };

  bool _correct(int number) => switch (number) {
    1 => _answers['q1']?.contains('q1b') == true,
    2 =>
      _answers['q2']?.toSet().containsAll({'q2a', 'q2b'}) == true &&
          _answers['q2']?.contains('q2c') != true,
    3 =>
      _answers['q3a']?.contains('q3a1') == true &&
          _answers['q3b']?.contains('q3b2') == true,
    _ => _answers['q4']?.join() == 'o2o3o1',
  };

  int get _score => [1, 2, 3, 4].where(_correct).length;

  int? get _timeLeft {
    final started = _started;
    if (started == null) return null;
    final left = _limit - _clock().difference(started);
    return left.isNegative ? 0 : left.inSeconds;
  }

  List<Map<String, Object?>> get _navigation => [
    for (final n in [1, 2, 3, 4])
      {
        'id': 'nav$n',
        'number': '$n',
        'state': _answered(n) ? 'answered' : 'unanswered',
        'status': _answered(n) ? '已經儲存答案' : '尚未作答',
        'flagged': false,
        'current': _step == 'attempt' && (n <= 2 ? 1 : 2) == _page,
      },
  ];

  Map<String, Object?> get _attempt {
    final first = _page == 1;
    final fields = first
        ? [
            _field('q1', 'single', 'que1', [
              _option('q1a', 'a. 先進先出（FIFO）'),
              _option('q1b', 'b. 後進先出（LIFO）'),
            ]),
            _field('q2', 'multiple', 'que2', [
              _option('q2a', 'a. 陣列'),
              _option('q2b', 'b. 鏈結串列'),
              _option('q2c', 'c. 二元樹'),
            ]),
          ]
        : [
            _field(
              'q3a',
              'single',
              'que3',
              [
                _blank('q3a0'),
                _option('q3a1', '先進先出'),
                _option('q3a2', '後進先出'),
              ],
              part: '佇列（queue）',
              context: '將資料結構與存取方式配對。',
            ),
            _field('q3b', 'single', 'que3', [
              _blank('q3b0'),
              _option('q3b1', '先進先出'),
              _option('q3b2', '後進先出'),
            ], part: '堆疊（stack）'),
            _field(
              'q4',
              'order',
              'que4',
              [
                _option('o1', 'O(n log n)'),
                _option('o2', 'O(1)'),
                _option('o3', 'O(n)'),
              ],
              part: '排序',
              context: '依時間複雜度由小到大排列。',
              values: _defaultOrder,
            ),
          ];
    final ids = [for (final f in fields) f['id']];
    return {
      'stage': 'attempt',
      'title': '隨堂小考',
      'text': '',
      'timer': '剩餘時間 ${_timeLeft ?? 0}',
      'timerSeconds': _timeLeft,
      'navigation': _navigation,
      'questions': first
          ? [
              {
                'id': 'que1',
                'number': '1',
                'text': '堆疊（stack）的存取順序是？',
                'state': _answered(1) ? '已經儲存答案' : '尚未作答',
              },
              {
                'id': 'que2',
                'number': '2',
                'text': '下列哪些是線性資料結構？',
                'state': _answered(2) ? '已經儲存答案' : '尚未作答',
              },
            ]
          : [
              {
                'id': 'que3',
                'number': '3',
                'text': '',
                'state': _answered(3) ? '已經儲存答案' : '尚未作答',
              },
              {
                'id': 'que4',
                'number': '4',
                'text': '',
                'state': _answered(4) ? '已經儲存答案' : '尚未作答',
              },
            ],
      'fields': fields,
      'actions': [
        if (!first)
          {
            'id': 'previous',
            'label': '上一頁',
            'disabled': false,
            'fieldIDs': ids,
            'isNavigation': true,
            'role': 'previous',
          },
        {
          'id': first ? 'next' : 'finish',
          'label': first ? '下一頁' : '完成作答...',
          'disabled': false,
          'fieldIDs': ids,
          'isNavigation': true,
          'role': first ? 'next' : 'finish',
        },
      ],
    };
  }

  Map<String, Object?> _review(int number, String text, String answer) => {
    'id': 'r$number',
    'title': '試題 $number',
    'text': text,
    'prompt': '',
    'status': _correct(number) ? '正確' : '不正確',
    'verdict': _correct(number) ? 'correct' : 'incorrect',
    'mark': '得分 ${_correct(number) ? '2.50' : '0.00'} / 2.50',
    'choices': [],
    'responses': [],
    'correctAnswer': '正確答案：$answer',
    'feedback': '',
    'generalFeedback': '',
    'comment': '',
  };

  Map<String, Object?> get _current => switch (_step) {
    'attempt' => _attempt,
    'summary' => {
      'stage': 'summary',
      'title': '隨堂小考',
      'text': '這次作答必須在 10 分鐘內完成。',
      'timer': '剩餘時間 ${_timeLeft ?? 0}',
      'timerSeconds': _timeLeft,
      'navigation': _navigation,
      'fields': [],
      'actions': [
        {
          'id': 'resume',
          'label': '回到作答',
          'disabled': false,
          'fieldIDs': [],
          'isNavigation': true,
          'role': 'resume',
        },
        {
          'id': 'submit',
          'label': '全部提交並結束',
          'disabled': false,
          'fieldIDs': [],
          'role': 'submit',
        },
      ],
    },
    'confirm' => {
      'stage': 'confirm',
      'title': '確認',
      'text': [
        '確認',
        '一旦提交，你將不能再更改這次作答的答案。',
        if ([1, 2, 3, 4].where((n) => !_answered(n)).length case final open
            when open > 0)
          '尚未作答的題目：$open',
      ].join('\n'),
      'fields': [],
      'actions': [
        {
          'id': 'cancel',
          'label': '取消',
          'disabled': false,
          'fieldIDs': [],
          'role': 'cancel',
        },
        {
          'id': 'confirm',
          'label': '全部提交並結束',
          'disabled': false,
          'fieldIDs': [],
          'role': 'confirm',
        },
      ],
    },
    'review' => {
      'stage': 'review',
      'title': '隨堂小考',
      'text': '',
      'fields': [],
      'actions': [
        {
          'id': 'done',
          'label': '完成檢閱',
          'disabled': false,
          'fieldIDs': [],
          'isNavigation': true,
          'role': 'done',
        },
      ],
      'result': {
        'grade': '${(_score * 2.5).toStringAsFixed(2)} / 10.00',
        'gradeLabel': '最後成績',
        'information': [],
        'attempts': [
          {
            'id': 'a1',
            'title': '作答記錄 1',
            'details': [
              {'id': 'd1', 'label': '作答狀態', 'value': '已經完成'},
              {
                'id': 'd2',
                'label': '成績',
                'value':
                    '得 ${(_score * 2.5).toStringAsFixed(2)} 分 (滿分為 10.00 分)',
              },
            ],
          },
        ],
        'notices': [demoNote('已模擬送出')],
      },
      'reviewQuestions': [
        _review(1, '堆疊（stack）的存取順序是？', '後進先出（LIFO）'),
        _review(2, '下列哪些是線性資料結構？', '陣列、鏈結串列'),
        _review(3, '將資料結構與存取方式配對。', '佇列 → 先進先出；堆疊 → 後進先出'),
        _review(4, '依時間複雜度由小到大排列。', 'O(1)、O(n)、O(n log n)'),
      ],
    },
    _ => {
      'stage': 'overview',
      'title': '隨堂小考',
      'text': '本測驗共 4 題，限作答 1 次。\n作答時間 10 分鐘，時間到會自動交卷。',
      'fields': [],
      'actions': [
        {
          'id': 'start',
          'label': '開始作答',
          'disabled': false,
          'fieldIDs': [],
          'role': 'start',
        },
      ],
    },
  };

  String get _revision => '$_step:$_page:$_count';

  @override
  Future<String?> snapshot() async =>
      jsonEncode({'revision': _revision, 'webReason': null, ..._current});

  @override
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  ) async {
    if (revision != _revision) return 'changed';
    _answers = {..._answers, ...answers};
    switch (actionId) {
      case 'start':
        _started = _clock();
        _step = 'attempt';
        _page = 1;
      case 'next' || 'nav3' || 'nav4':
        _step = 'attempt';
        _page = 2;
      case 'previous' || 'resume' || 'nav1' || 'nav2':
        _step = 'attempt';
        _page = 1;
      case 'finish' || 'cancel':
        _step = 'summary';
      case 'submit':
        _step = 'confirm';
      case 'confirm':
        _step = 'review';
      default:
        _step = 'view';
    }
    _count++;
    return 'invoked';
  }

  /// Drafts written as they change, as on a timed school page.
  @override
  Future<String?> stage(
    String revision,
    Map<String, List<String>> answers,
  ) async {
    if (revision != _revision) return 'changed';
    _answers = {..._answers, ...answers};
    return 'staged';
  }

  @override
  Future<void> focus(String questionId) async {}
}
