/// Sample school data for the review demo. Shapes match what each school
/// page's extraction script returns, so the normal parsers and screens run
/// unchanged. Every name, number and record here is fictional.
abstract final class DemoData {
  static DateTime get _taipei =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  /// ROC date, e.g. 115/10/01, [days] from today.
  static String rocDate(int days) {
    final d = _taipei.add(Duration(days: days));
    return '${d.year - 1911}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  static String _westernDate(int days) {
    final d = _taipei.add(Duration(days: days));
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  /// Unix seconds [days] from now, for Moodle timestamps.
  static int unix(int days, {int hour = 0}) =>
      DateTime.now()
          .add(Duration(days: days, hours: hour))
          .millisecondsSinceEpoch ~/
      1000;

  /// The demo student's (fictional) name, shown wherever a name appears.
  static const studentName = '陳宜安';

  static const profile = <String, dynamic>{
    'chName': studentName,
    'facultyName': '資訊工程學系',
    'grade': '3',
  };

  // ── 課表 (TKE2240) ──────────────────────────────────────────────────────
  static const _times = [
    ('1', '08:10~09:00'),
    ('2', '09:10~10:00'),
    ('3', '10:10~11:00'),
    ('4', '11:10~12:00'),
    ('5', '13:10~14:00'),
    ('6', '14:10~15:00'),
    ('7', '15:10~16:00'),
    ('8', '16:10~17:00'),
  ];

  /// Day index 0–4 → period → 「教師\n課程\n教室」.
  static const _courses = <int, Map<String, String>>{
    0: {
      '1': '王大明\n資料結構\n工程館 E101',
      '2': '王大明\n資料結構\n工程館 E101',
      '5': '李小華\n線性代數\n綜合大樓 B204',
      '6': '李小華\n線性代數\n綜合大樓 B204',
    },
    1: {
      '3': '陳志明\n計算機組織\n工程館 E205',
      '4': '陳志明\n計算機組織\n工程館 E205',
      '7': '林美玲\n體育－羽球\n體育館',
      '8': '林美玲\n體育－羽球\n體育館',
    },
    2: {
      '1': 'Emily Chen\n英文（二）\n綜合大樓 A302',
      '2': 'Emily Chen\n英文（二）\n綜合大樓 A302',
      '5': '黃建國\n作業系統\n工程館 E303',
      '6': '黃建國\n作業系統\n工程館 E303',
      '7': '黃建國\n作業系統\n工程館 E303',
    },
    3: {
      '3': '張雅婷\n機率與統計\n綜合大樓 B105',
      '4': '張雅婷\n機率與統計\n綜合大樓 B105',
      '5': '吳俊傑\n宜蘭文化導論\n人文館 H201',
      '6': '吳俊傑\n宜蘭文化導論\n人文館 H201',
    },
    4: {
      '2': '王大明\n軟體工程實務\n工程館 E401',
      '3': '王大明\n軟體工程實務\n工程館 E401',
      '4': '王大明\n軟體工程實務\n工程館 E401',
    },
  };

  static List<List<String>> get scheduleRows => [
    ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'],
    for (final (period, time) in _times)
      [
        period,
        time,
        for (var day = 0; day < 5; day++) _courses[day]?[period] ?? '',
      ],
  ];

  // ── 成績 (GRD5130 / GRD5131 / 歷年) ─────────────────────────────────────
  static Map<String, dynamic> grades(String mode) => switch (mode) {
    'midterm' => {
      'title': '115 學年度 上學期',
      'average': '',
      'rank': '',
      'rows': [
        ['1', '1151', 'B3E0101A', '必修', '資料結構', '86'],
        ['2', '1151', 'B3E0102A', '必修', '計算機組織', '78'],
        ['3', '1151', 'B3E0103A', '必修', '作業系統', ''],
        ['4', '1151', 'B3E0104A', '必修', '機率與統計', '91'],
        ['5', '1151', 'B3G0201A', '選修', '軟體工程實務', ''],
      ],
    },
    'finalTerm' => {
      'title': '114 學年度 下學期',
      'average': '84.6',
      'rank': '7/52',
      'rows': [
        ['1', '1142', 'B2E0201A', '必修', '物件導向程式設計', '90'],
        ['2', '1142', 'B2E0202A', '必修', '離散數學', '82'],
        ['3', '1142', 'B2E0203A', '必修', '數位邏輯', '79'],
        ['4', '1142', 'B2G0301A', '選修', '網頁程式設計', '93'],
        ['5', '1142', 'B2P0101A', '必修', '體育－桌球', '88'],
      ],
    },
    _ => {
      'rows': [
        ['1141', '必修', '3', '程式設計（一）', '88'],
        ['1141', '必修', '3', '微積分（一）', '76'],
        ['1141', '必修', '2', '英文（一）', '85'],
        ['1141', '通識', '2', '當代藝術賞析', '92'],
        ['1142', '必修', '3', '物件導向程式設計', '90'],
        ['1142', '必修', '3', '離散數學', '82'],
        ['1142', '必修', '3', '數位邏輯', '79'],
        ['1142', '選修', '3', '網頁程式設計', '93'],
        ['1142', '必修', '0', '體育－桌球', '88'],
      ],
      'ranks': [
        {
          'sem': '1141',
          'classRank': '12/55',
          'departmentRank': '21/85',
          'average': '84.1',
        },
        {
          'sem': '1142',
          'classRank': '7/52',
          'departmentRank': '15/88',
          'average': '84.6',
        },
      ],
    },
  };

  // ── 畢業門檻 (ENRG010) ─────────────────────────────────────────────────
  static const graduation = <String, dynamic>{
    'diverseHours': ['18', '20', '12', '20', '20', '20', '6', '20'],
    'creditRequired': ['128', '82'],
    'englishAbility': '已通過',
    'physicalFitness': '尚未檢測',
    'creditCourse': '',
  };

  // ── 在學證明 (ENR5020) ─────────────────────────────────────────────────
  static Map<String, dynamic> registration(String account) => {
    'student': account,
    'printable': true,
    'rows': [
      {
        '註冊學年期': '1151',
        '學號': account,
        '在學狀態': '在學',
        '註冊狀態': '已完成註冊',
        '註冊日期': rocDate(-21),
        '學雜費': '已繳費',
        '就學貸款': '無',
      },
      {
        '註冊學年期': '1142',
        '學號': account,
        '在學狀態': '在學',
        '註冊狀態': '已完成註冊',
        '註冊日期': '115/02/16',
        '學雜費': '已繳費',
        '就學貸款': '無',
      },
    ],
  };

  // ── 請假 ────────────────────────────────────────────────────────────────
  static Map<String, dynamic> get leaveStatistics => {
    'periods': {
      '事假': '2',
      '病假': '3',
      '公假': '0',
      '喪假': '0',
      '婚假': '0',
      '產假（產前假／陪產假／流產假／哺乳假）': '0',
      '生理假': '0',
      '心理健康假': '0',
      '防疫假': '0',
      '其他': '0',
    },
    'scope': '本學期',
  };

  static List<Map<String, dynamic>> get _leaveRecords => [
    {
      '假單序號': 'D1150928',
      '請假類別': '事假',
      '審核結果': '審核中',
      '申請日期': rocDate(-2),
      '請假起日': rocDate(3),
      '請假訖日': rocDate(3),
      '起始節次': '3',
      '迄止節次': '4',
      '請假總節數': '2',
      '請假事由': '參加家人婚禮',
    },
    {
      '假單序號': 'D1150921',
      '請假類別': '事假',
      '審核結果': '退回',
      '申請日期': rocDate(-6),
      '請假起日': rocDate(-5),
      '請假訖日': rocDate(-5),
      '起始節次': '5',
      '迄止節次': '6',
      '請假總節數': '2',
      '請假事由': '處理戶籍資料',
    },
    {
      '假單序號': 'D1150915',
      '請假類別': '病假',
      '審核結果': '核准',
      '申請日期': rocDate(-12),
      '請假起日': rocDate(-14),
      '請假訖日': rocDate(-14),
      '起始節次': '1',
      '迄止節次': '3',
      '請假總節數': '3',
      '請假事由': '感冒發燒就醫',
    },
  ];

  static Map<String, dynamic> get leaveList => {
    'records': _leaveRecords,
    'page': '1',
    'pages': '1',
    'total': '${_leaveRecords.length}',
  };

  static Map<String, dynamic> leaveRecord(String id) => _leaveRecords
      .firstWhere((r) => r['假單序號'] == id, orElse: () => _leaveRecords.first);

  /// 學生請假修改: what the school allows for each demo form.
  static Map<String, dynamic> get leaveActions => {
    'actions': [
      {'formNo': 'D1150928', 'withdraw': true, 'modify': true},
      {
        'formNo': 'D1150921',
        'withdraw': true,
        'modify': true,
        'supplement': true,
      },
    ],
  };

  static Map<String, dynamic> leaveDetail(String id) {
    final record = leaveRecord(id);
    final approved = record['審核結果'] == '核准';
    return {
      'fields': {'請假事由': record['請假事由'], '證明文件': approved ? '診斷證明.pdf' : '無'},
      'periods': [
        [
          for (
            var p = int.parse('${record['起始節次']}');
            p <= int.parse('${record['迄止節次']}');
            p++
          )
            ['${record['請假起日']}', '第$p節', approved ? '資料結構' : '計算機組織'],
        ],
      ],
      'workflowName': '學生請假（3 日以內）',
      'workflow': [
        {
          '簽核狀況': '已簽核',
          '簽核日期': '${record['申請日期']} 09:12',
          '關卡說明': '申請人',
          '簽核單位': '資訊工程學系',
          '簽核人': studentName,
          '簽核意見': '(申請送出)',
        },
        if (record['審核結果'] == '退回')
          {
            '簽核狀況': '退回',
            '簽核日期': '${record['申請日期']} 15:40',
            '關卡說明': '導師',
            '簽核單位': '資訊工程學系',
            '簽核人': '王大明',
            '簽核意見': '請補上戶政事務所的證明文件後再送出。',
          }
        else ...[
          {
            '簽核狀況': '已簽核',
            '簽核日期': '${record['申請日期']} 15:40',
            '關卡說明': '導師',
            '簽核單位': '資訊工程學系',
            '簽核人': '王大明',
            '簽核意見': '(已簽核，查無簽核意見。)',
          },
          {
            '簽核狀況': approved ? '已簽核' : '簽核中',
            '簽核日期': approved ? '${record['申請日期']} 16:05' : '',
            '關卡說明': '生活輔導組',
            '簽核單位': '學務處',
            '簽核人': approved ? '林怡君' : '',
            '簽核意見': approved ? '已核准，請保留就醫證明。' : '',
          },
        ],
      ],
    };
  }

  // ── 活動報名 ────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> get events => [
    {
      'id': '11201',
      'name': '職涯探索工作坊：從履歷到面試',
      'department': '學生職涯發展中心',
      'status': '報名中',
      'time': '${_westernDate(7)} 13:30 ~ ${_westernDate(7)} 16:30',
      'location': '圖書館 B1 國際會議廳',
      'people': '已報名 38 / 60 人',
      'registration': '${_westernDate(-5)} ~ ${_westernDate(5)}',
      'details': '由業界講師帶領撰寫履歷、模擬面試，現場提供一對一回饋。',
      'contact': '職涯中心 03-9317000 分機 1234',
      'remark': '請攜帶筆電',
      'hours': '專業進取（已認證，3 小時）',
      'targets': '本校在校生',
    },
    {
      'id': '11202',
      'name': '淨灘志工服務：守護蘭陽海岸',
      'department': '服務學習中心',
      'status': '報名中',
      'time': '${_westernDate(10)} 08:00 ~ ${_westernDate(10)} 12:00',
      'location': '壯圍海岸（校門口集合）',
      'people': '已報名 22 / 40 人',
      'registration': '${_westernDate(-3)} ~ ${_westernDate(8)}',
      'details': '一起到壯圍海岸淨灘，提供交通車與保險。',
      'contact': '服務學習中心 03-9317000 分機 2345',
      'remark': '',
      'hours': '服務學習（已認證，4 小時）',
      'targets': '本校在校生',
    },
    {
      'id': '11203',
      'name': '心理健康講座：與壓力和平共處',
      'department': '學生諮商中心',
      'status': '報名中',
      'time': '${_westernDate(4)} 18:30 ~ ${_westernDate(4)} 20:30',
      'location': '綜合大樓 B101',
      'people': '已報名 51 / 80 人',
      'registration': '${_westernDate(-7)} ~ ${_westernDate(3)}',
      'details': '諮商心理師分享壓力調適技巧與實作練習。',
      'contact': '諮商中心 03-9317000 分機 3456',
      'remark': '',
      'hours': '多元成長（已認證，2 小時）',
      'targets': '本校在校生',
    },
    {
      'id': '11204',
      'name': 'AI 應用實作營',
      'department': '資訊工程學系',
      'status': '已額滿',
      'time': '${_westernDate(14)} 09:00 ~ ${_westernDate(14)} 17:00',
      'location': '工程館 E301 電腦教室',
      'people': '已報名 40 / 40 人',
      'registration': '${_westernDate(-10)} ~ ${_westernDate(2)}',
      'details': '一日實作營，從資料整理到模型部署。',
      'contact': '資工系辦 03-9317000 分機 4567',
      'remark': '額滿後開放候補',
      'hours': '專業進取（已認證，6 小時）',
      'targets': '本校在校生',
    },
  ];

  /// Already registered when the demo starts.
  static Map<String, dynamic> get registeredEvent => {
    'id': '11188',
    'name': '新生盃籃球賽志工',
    'department': '體育室',
    'status': '報名成功',
    'time': '${_westernDate(2)} 12:00 ~ ${_westernDate(2)} 18:00',
    'location': '體育館',
    'people': '已報名 12 / 15 人',
    'registration': '${_westernDate(-14)} ~ ${_westernDate(-1)}',
    'details': '協助記錄比分與場地整理。',
    'contact': '體育室 03-9317000 分機 5678',
    'remark': '',
    'hours': '服務學習（已認證，6 小時）',
    'targets': '本校在校生',
  };

  // ── 郵件包裹 ────────────────────────────────────────────────────────────
  static List<Map<String, String>> get postal => [
    {
      'sequence': '1',
      'receivedDate': rocDate(-1),
      'trackingNumber': 'RR123456789TW',
      'unit': '資訊工程學系',
      'category': '包裹',
      'quantity': '1',
      'signature': '否',
      'completedDate': '',
      'status': 'waiting',
    },
    {
      'sequence': '2',
      'receivedDate': rocDate(-9),
      'trackingNumber': '6612345678',
      'unit': '資訊工程學系',
      'category': '掛號信',
      'quantity': '1',
      'signature': '是',
      'completedDate': rocDate(-8),
      'status': 'collected',
    },
  ];

  // ── M 園區 (Moodle web service) ────────────────────────────────────────
  static const _moodleCourses = [
    (101, '資料結構', 'B3E0101A', '王大明', '3'),
    (102, '計算機組織', 'B3E0102A', '陳志明', '3'),
    (103, '作業系統', 'B3E0103A', '黃建國', '3'),
    (104, '機率與統計', 'B3E0104A', '張雅婷', '3'),
    (105, '線性代數', 'B3E0105A', '李小華', '3'),
    (106, '軟體工程實務', 'B3G0201A', '王大明', '3'),
    (107, '英文（二）', 'B3L0102A', 'Emily Chen', '2'),
    (108, '宜蘭文化導論', 'B3C0301A', '吳俊傑', '2'),
  ];

  static const _file =
      'https://euni.niu.edu.tw/webservice/pluginfile.php/1/mod_resource/content/1';

  /// Answers a Moodle web-service read with sample data.
  static Object? moodle(String function, Map<String, Object> params) {
    int? id(String key) => int.tryParse('${params[key]}');
    // Forum = course×10(+1), discussion = forum×10+n, assignment = course×10+n.
    final cid =
        id('courseid') ??
        id('courseids[0]') ??
        switch (id('forumid')) {
          final forum? => forum ~/ 10,
          null => null,
        } ??
        switch (id('discussionid')) {
          final discussion? => discussion ~/ 100,
          null => null,
        } ??
        switch (id('assignid')) {
          final assignment? => assignment ~/ 10,
          null => null,
        };
    final course = _moodleCourses.firstWhere(
      (c) => c.$1 == cid,
      orElse: () => _moodleCourses.first,
    );
    switch (function) {
      case 'core_enrol_get_users_courses':
        return [
          for (final (cid, name, code, teacher, credits) in _moodleCourses)
            {
              'id': cid,
              'fullname': name,
              'shortname': '1151_$code',
              'summary': '開課教師：$teacher\n學分數：$credits',
              'visible': 1,
            },
        ];
      case 'core_course_get_contents':
        final cid = course.$1;
        return [
          {
            'id': cid * 10,
            'name': '課程資訊',
            'summary': '<p>歡迎修習${course.$2}，請先閱讀課程大綱。</p>',
            'modules': [
              {
                'id': cid * 100 + 1,
                'name': '課程大綱',
                'modname': 'resource',
                'url':
                    'https://euni.niu.edu.tw/mod/resource/view.php?id=${cid * 100 + 1}',
                'contents': [
                  {'filename': '課程大綱.pdf', 'fileurl': '$_file/syllabus.pdf'},
                ],
              },
              {
                'id': cid * 100 + 6,
                'name': '課程公告',
                'modname': 'forum',
                'instance': cid * 10,
                'url':
                    'https://euni.niu.edu.tw/mod/forum/view.php?id=${cid * 100 + 6}',
              },
              {
                'id': cid * 100 + 7,
                'name': '分組名單',
                'modname': 'page',
                'instance': cid,
                'url':
                    'https://euni.niu.edu.tw/mod/page/view.php?id=${cid * 100 + 7}',
                'contents': [
                  {
                    'type': 'file',
                    'filename': 'index.html',
                    'fileurl':
                        'https://euni.niu.edu.tw/webservice/pluginfile.php/1/mod_page/content/1/index.html',
                  },
                ],
              },
              {
                'id': cid * 100 + 2,
                'name': '出席紀錄',
                'modname': 'attendance',
                'instance': cid,
                'url':
                    'https://euni.niu.edu.tw/mod/attendance/view.php?id=${cid * 100 + 2}',
              },
            ],
          },
          {
            'id': cid * 10 + 1,
            'name': '第 1 週：課程介紹',
            'summary': '',
            'modules': [
              {
                'id': cid * 100 + 3,
                'name': '第一週講義',
                'modname': 'resource',
                'url':
                    'https://euni.niu.edu.tw/mod/resource/view.php?id=${cid * 100 + 3}',
                'contents': [
                  {'filename': '第一週講義.pdf', 'fileurl': '$_file/week1.pdf'},
                ],
              },
              {
                'id': cid * 100 + 5,
                'name': '隨堂小考',
                'modname': 'quiz',
                'instance': cid * 10 + 2,
                'visible': 1,
                'uservisible': true,
                'url':
                    'https://euni.niu.edu.tw/mod/quiz/view.php?id=${cid * 100 + 5}',
              },
              {
                'id': cid * 100 + 4,
                'name': '作業一',
                'modname': 'assign',
                'instance': cid * 10 + 1,
                'url':
                    'https://euni.niu.edu.tw/mod/assign/view.php?id=${cid * 100 + 4}',
              },
            ],
          },
        ];
      case 'mod_forum_get_forums_by_courses':
        return [
          {'id': course.$1 * 10, 'name': '課程公告', 'type': 'news', 'intro': ''},
          {
            'id': course.$1 * 10 + 1,
            'name': '課程討論區',
            'type': 'general',
            'intro': '<p>課程相關問題可在這裡發問。</p>',
          },
        ];
      case 'mod_forum_get_forum_discussions':
        final forum = id('forumid') ?? course.$1 * 10;
        final news = forum % 10 == 0;
        return {
          'discussions': [
            {
              'id': forum * 10 + 1,
              'discussion': forum * 10 + 1,
              'name': news ? '期中考範圍公告' : '作業一提問',
              'subject': news ? '期中考範圍公告' : '作業一提問',
              'message': news
                  ? '<p>期中考範圍為第 1 至第 8 週，請準時到考。</p>'
                  : '<p>請問作業一可以使用標準函式庫嗎？</p>',
              'userfullname': news ? course.$4 : studentName,
              'timemodified': unix(-2),
              'numreplies': news ? 0 : 1,
              'attachments': [],
            },
            if (news)
              {
                'id': forum * 10 + 2,
                'discussion': forum * 10 + 2,
                'name': '歡迎修課',
                'subject': '歡迎修課',
                'message': '<p>本學期課程進度與評分方式請見課程大綱。</p>',
                'userfullname': course.$4,
                'timemodified': unix(-20),
                'numreplies': 0,
                'attachments': [],
              },
          ],
        };
      case 'mod_forum_get_discussion_posts':
        return {
          'posts': [
            {
              'id': 1,
              'subject': '作業一提問',
              'message': '<p>請問作業一可以使用標準函式庫嗎？</p>',
              'author': {'fullname': studentName},
              'timecreated': unix(-2),
              'attachments': [],
            },
            {
              'id': 2,
              'subject': 'Re: 作業一提問',
              'message': '<p>可以，但核心資料結構請自行實作。</p>',
              'author': {'fullname': course.$4},
              'timecreated': unix(-1),
              'attachments': [],
            },
          ],
        };
      case 'mod_page_get_pages_by_courses':
        return {
          'pages': [
            {
              'id': course.$1,
              'coursemodule': course.$1 * 100 + 7,
              'name': '分組名單',
              'intro': '',
              'content':
                  '<p>期末專題分組如下，請各組於第 6 週前確認題目。</p>'
                  '<table><tr><th>組別</th><th>組員</th><th>題目</th></tr>'
                  '<tr><td>第 1 組</td><td>$studentName、陳宥廷、林品妤</td><td>校園導覽 App</td></tr>'
                  '<tr><td>第 2 組</td><td>黃柏翰、許芷涵、蔡承恩</td><td>圖書館座位查詢</td></tr></table>',
            },
          ],
        };
      case 'mod_assign_get_assignments':
        final ids = [
          for (final entry in params.entries)
            if (entry.key.startsWith('courseids['))
              int.tryParse('${entry.value}'),
        ].whereType<int>();
        return {
          'courses': [
            for (final id in ids)
              {
                'id': id,
                'assignments': [
                  {
                    'id': id * 10 + 1,
                    'cmid': id * 100 + 4,
                    'name': '作業一',
                    'intro': '<p>完成第一週練習題，上傳 PDF 檔。</p>',
                    // Spread over today, this week and later.
                    'duedate': unix(
                      const [0, 1, 3, 6, 9, 12, 16, 20][id % 8],
                      hour: 6,
                    ),
                  },
                  {
                    'id': id * 10 + 2,
                    'cmid': id * 100 + 5,
                    'name': '課堂心得',
                    'intro': '<p>寫下本週課堂心得，300 字以內。</p>',
                    'duedate': unix(-3 - id % 3),
                  },
                ],
              },
          ],
        };
      case 'mod_assign_get_submission_status':
        final assignment = id('assignid') ?? 0;
        // One overdue reflection is still to hand in.
        final done = assignment % 10 == 2 && assignment != 1042;
        return {
          'lastattempt': {
            'submission': {
              'status': done ? 'submitted' : 'new',
              'timemodified': done ? unix(-4) : 0,
              'plugins': [
                {
                  'type': 'file',
                  'fileareas': [
                    {
                      'area': 'submission_files',
                      'files': [
                        if (done)
                          {
                            'filename': '課堂心得.pdf',
                            'fileurl': '$_file/note.pdf',
                          },
                      ],
                    },
                  ],
                },
              ],
            },
            'graded': done,
          },
        };
      case 'gradereport_user_get_grade_items':
        return {
          'usergrades': [
            {
              'gradeitems': [
                {
                  'itemname': '課堂心得',
                  'gradeformatted': '92.00',
                  'rangeformatted': '0–100',
                  'percentageformatted': '92.00 %',
                  'weightformatted': '10.00 %',
                  'feedback': '<p>觀察很仔細。</p>',
                },
                {
                  'itemname': '作業一',
                  'gradeformatted': '-',
                  'rangeformatted': '0–100',
                  'percentageformatted': '-',
                  'weightformatted': '20.00 %',
                  'feedback': '',
                },
              ],
            },
          ],
        };
      case 'core_message_get_messages':
        return {
          'messages': [
            {
              'id': 1,
              'subject': '資料結構：作業一即將截止',
              'smallmessage': '作業一將於 6 天後截止。',
              'fullmessage': '作業一將於 6 天後截止，請記得上傳。',
              'fullmessagehtml': '<p>作業一將於 6 天後截止，請記得上傳。</p>',
              'timecreated': unix(0, hour: -3),
              'contexturl': '',
            },
            {
              'id': 2,
              'subject': '計算機組織：新公告',
              'smallmessage': '期中考範圍公告',
              'fullmessage': '期中考範圍為第 1 至第 8 週。',
              'fullmessagehtml': '<p>期中考範圍為第 1 至第 8 週。</p>',
              'timecreated': unix(-2),
              'contexturl': '',
            },
          ],
        };
    }
    return const <String, dynamic>{};
  }

  /// 出席紀錄: (date, description, status label).
  static List<(String, String, String)> get attendance => [
    (_westernDate(-21), '第 1 週', '出席'),
    (_westernDate(-14), '第 2 週', '出席'),
    (_westernDate(-7), '第 3 週', '遲到'),
    (_westernDate(0), '第 4 週', '尚未點名'),
  ];
}
