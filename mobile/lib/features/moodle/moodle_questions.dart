import 'dart:convert';

import 'moodle_repository.dart';

/// Moodle activities that hold questions to answer, as on iOS
/// (`Features/Moodle/Questions`).
enum MoodleQuestionKind {
  quiz('測驗'),
  irs('即時問答'),
  choice('選擇'),
  feedback('回饋'),
  questionnaire('問卷'),
  survey('調查');

  const MoodleQuestionKind(this.title);
  final String title;

  static MoodleQuestionKind? of(Json module) {
    final name = '${module['modname']}'.toLowerCase();
    return values.where((k) => k.name == name).firstOrNull;
  }

  /// The canonical entry of a visible activity, never a replayed attempt URL.
  static Uri? entry(Json module) {
    final kind = of(module);
    final id = int.tryParse('${module['id']}') ?? 0;
    if (kind == null || id <= 0) return null;
    if (module['visible'] == 0 || module['uservisible'] == false) return null;
    // Restricted activities may still be listed with their conditions.
    final restricted = '${module['availabilityinfo'] ?? ''}'.trim().isNotEmpty;
    if (restricted && module['uservisible'] != true) return null;
    return Uri.https('euni.niu.edu.tw', '/mod/${kind.name}/view.php', {
      'id': '$id',
    });
  }
}

/// Course sections that contain question activities, each module once.
List<({String name, List<Json> modules})> moodleQuestionSections(
  List<Json> contents,
) {
  final seen = <Object?>{};
  return [
    for (final section in contents)
      if (section['visible'] != 0)
        if ([
              for (final m in objects(section['modules'] ?? []))
                if (m['visible'] != 0 &&
                    MoodleQuestionKind.of(m) != null &&
                    seen.add(m['id']))
                  m,
            ]
            case final modules when modules.isNotEmpty)
          (name: plain(section['name']), modules: modules),
  ];
}

class MoodleQuestionOption {
  MoodleQuestionOption.fromJson(Map json)
    : id = '${json['id']}',
      label = '${json['label']}',
      disabled = json['disabled'] == true;
  final String id, label;
  final bool disabled;
}

class MoodleQuestionField {
  MoodleQuestionField.fromJson(Map json)
    : id = '${json['id']}',
      kind = '${json['kind']}',
      label = '${json['label']}',
      values = [for (final v in (json['values'] as List? ?? [])) '$v'],
      options = [
        for (final o in (json['options'] as List? ?? []).whereType<Map>())
          MoodleQuestionOption.fromJson(o),
      ],
      required = json['required'] == true,
      disabled = json['disabled'] == true;
  final String id, kind, label;
  final List<String> values;
  final List<MoodleQuestionOption> options;
  final bool required, disabled;
  bool get isChoice => kind == 'single' || kind == 'multiple';
}

class MoodleQuestionAction {
  MoodleQuestionAction.fromJson(Map json)
    : id = '${json['id']}',
      label = '${json['label']}',
      disabled = json['disabled'] == true,
      fieldIds = [for (final f in (json['fieldIDs'] as List? ?? [])) '$f'],
      isNavigation = json['isNavigation'] == true;
  final String id, label;
  final bool disabled, isNavigation;
  final List<String> fieldIds;
}

class MoodleReviewChoice {
  MoodleReviewChoice.fromJson(Map json)
    : text = '${json['text'] ?? ''}',
      selected = json['selected'] == true,
      verdict = json['verdict'] as String?,
      feedback = '${json['feedback'] ?? ''}';
  final String text, feedback;
  final bool selected;
  final String? verdict;
}

/// One question on a quiz review page, read-only.
class MoodleReviewQuestion {
  MoodleReviewQuestion.fromJson(Map json)
    : id = '${json['id']}',
      title = '${json['title'] ?? ''}',
      text = '${json['text'] ?? ''}',
      prompt = '${json['prompt'] ?? ''}',
      status = '${json['status'] ?? ''}',
      verdict = json['verdict'] as String?,
      mark = '${json['mark'] ?? ''}',
      choices = [
        for (final c in (json['choices'] as List? ?? []).whereType<Map>())
          MoodleReviewChoice.fromJson(c),
      ],
      responses = [for (final r in (json['responses'] as List? ?? [])) '$r'],
      correctAnswer = '${json['correctAnswer'] ?? ''}',
      feedback = '${json['feedback'] ?? ''}',
      generalFeedback = '${json['generalFeedback'] ?? ''}',
      comment = '${json['comment'] ?? ''}',
      webReason = json['webReason'] as String?;
  final String id, title, text, prompt, status, mark;
  final String correctAnswer, feedback, generalFeedback, comment;
  final String? verdict, webReason;
  final List<MoodleReviewChoice> choices;
  final List<String> responses;
}

typedef MoodleQuestionDetail = ({String label, String value});

class MoodleQuestionResult {
  MoodleQuestionResult.fromJson(Map json)
    : grade = json['grade'] as String?,
      gradeLabel = json['gradeLabel'] as String?,
      information = _details(json['information']),
      attempts = [
        for (final a in (json['attempts'] as List? ?? []).whereType<Map>())
          (title: '${a['title'] ?? ''}', details: _details(a['details'])),
      ],
      notices = [for (final n in (json['notices'] as List? ?? [])) '$n'];
  final String? grade, gradeLabel;
  final List<MoodleQuestionDetail> information;
  final List<({String title, List<MoodleQuestionDetail> details})> attempts;
  final List<String> notices;

  static List<MoodleQuestionDetail> _details(Object? raw) => [
    for (final d in (raw as List? ?? []).whereType<Map>())
      (label: '${d['label'] ?? ''}', value: '${d['value'] ?? ''}'),
  ];
}

/// What the activity page shows now, read from its live DOM. [revision]
/// changes with the document or any question, control or action, so a
/// confirmation made on an older page is never applied to a newer one.
class MoodleQuestionPage {
  MoodleQuestionPage.fromJson(Map json)
    : revision = '${json['revision']}',
      title = '${json['title'] ?? ''}',
      text = '${json['text'] ?? ''}',
      fields = [
        for (final f in (json['fields'] as List? ?? []).whereType<Map>())
          MoodleQuestionField.fromJson(f),
      ],
      actions = [
        for (final a in (json['actions'] as List? ?? []).whereType<Map>())
          MoodleQuestionAction.fromJson(a),
      ],
      webReason = json['webReason'] as String?,
      result = json['result'] is Map
          ? MoodleQuestionResult.fromJson(json['result'] as Map)
          : null,
      reviewQuestions = json['reviewQuestions'] is List
          ? [
              for (final q
                  in (json['reviewQuestions'] as List).whereType<Map>())
                MoodleReviewQuestion.fromJson(q),
            ]
          : null;
  final String revision, title, text;
  final List<MoodleQuestionField> fields;
  final List<MoodleQuestionAction> actions;
  final String? webReason;
  final MoodleQuestionResult? result;
  final List<MoodleReviewQuestion>? reviewQuestions;

  Map<String, List<String>> get values => {
    for (final f in fields) f.id: f.values,
  };
}

/// Reads the page. Installs the reader first; it lives with the document.
const moodleQuestionSnapshot =
    '(() => { $moodleQuestionInstall; '
    'return JSON.stringify(window.__niuQuestionsV1.snapshot()); })()';

/// Clicks the school's own control for [actionId] after writing [answers]
/// (only into the fields that control submits). Answers 'invoked',
/// 'changed' or 'invalid'.
String moodleQuestionPerform(
  String revision,
  String actionId,
  Map<String, List<String>> answers,
) =>
    '(() => { $moodleQuestionInstall; return window.__niuQuestionsV1.perform('
    '${jsonEncode(revision)}, ${jsonEncode(actionId)}, ${jsonEncode(answers)}); })()';

/// Writes [answers] into the page without submitting, before the school
/// page is shown. Answers 'staged', 'changed' or 'invalid'.
String moodleQuestionStage(
  String revision,
  Map<String, List<String>> answers,
) =>
    '(() => { $moodleQuestionInstall; return window.__niuQuestionsV1.stage('
    '${jsonEncode(revision)}, ${jsonEncode(answers)}); })()';

String moodleQuestionFocus(String questionId) =>
    '(() => { $moodleQuestionInstall; return window.__niuQuestionsV1.focusQuestion('
    '${jsonEncode(questionId)}); })()';

/// The same reader as iOS (`MoodleQuestionPageScript.install`). Every action
/// resolves to a live DOM element: no endpoint, hidden token or form payload
/// is rebuilt or stored by the app.
const moodleQuestionInstall = r'''
(() => {
    if (window.__niuQuestionsV1) return;
    const ids = new WeakMap();
    let nextID = 0;
    const documentID = Math.random().toString(36).slice(2);
    let controls = new Map(), actions = new Map();
    const key = element => {
        if (!ids.has(element)) ids.set(element, 'n' + (++nextID));
        return ids.get(element);
    };
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    const visible = element => {
        if (!element || !element.isConnected) return false;
        const style = getComputedStyle(element);
        return !element.closest('[hidden], [aria-hidden="true"]') &&
            style.display !== 'none' && style.visibility !== 'hidden' &&
            element.getClientRects().length > 0;
    };
    const labelledBy = element => (element.getAttribute('aria-labelledby') || '').split(/\s+/)
        .map(id => id && document.getElementById(id)?.textContent).filter(Boolean).join(' ');
    const label = element => clean(
        element.getAttribute('aria-label') ||
        labelledBy(element) ||
        Array.from(element.labels || []).map(l => l.textContent).join(' ') ||
        element.closest('label')?.textContent ||
        element.getAttribute('placeholder') || ''
    );
    const disabled = element => element.matches(':disabled') || element.getAttribute('aria-disabled') === 'true';
    // Quiz answers sit inside an inner fieldset whose legend is only "Select one".
    const contextLabel = element => {
        const group = element.closest('.que') || element.closest('fieldset, [role="group"], .fitem');
        const text = clean(group?.querySelector('.qtext, legend, .col-form-label, .fitemtitle')?.textContent);
        const number = group?.matches('.que') ? clean(group.querySelector('.info .no')?.textContent) : '';
        return number && text ? number + '：' + text : text;
    };
    // Question flags and "clear my choice" are school page chrome, not answers.
    const quizChrome = element => !!element.closest('.que .info, .questionflag, .qtype_multichoice_clearchoice');
    const safeURL = href => {
        try {
            const url = new URL(href, document.baseURI);
            return url.protocol === 'https:' && url.hostname === 'euni.niu.edu.tw' &&
                (!url.port || url.port === '443') && !url.username && !url.password &&
                /^\/mod\/(quiz|irs|choice|feedback|questionnaire|survey)\/(view|attempt|summary|review|complete)\.php$/.test(url.pathname) &&
                !Array.from(url.searchParams.keys()).some(k => /delete|sesskey|confirm|submit|finish/i.test(k));
        } catch { return false; }
    };
    const safeForm = form => {
        try {
            const target = new URL(form.action || location.href, document.baseURI);
            return target.protocol === 'https:' && target.hostname === 'euni.niu.edu.tw' &&
                (!target.port || target.port === '443') && !target.username && !target.password &&
                /^\/mod\/(quiz|irs|choice|feedback|questionnaire|survey)\//.test(target.pathname);
        } catch { return false; }
    };
    const reviewText = element => {
        if (!element || !visible(element)) return '';
        const copy = element.cloneNode(true);
        const originals = Array.from(element.querySelectorAll('*'));
        const copies = Array.from(copy.querySelectorAll('*'));
        originals.forEach((node, i) => {
            if (!visible(node)) copies[i].remove();
        });
        copy.querySelectorAll('script, style, input, textarea, select, button, .accesshide, .sr-only, [aria-hidden="true"]').forEach(e => e.remove());
        copy.querySelectorAll('p, div, li, br, pre').forEach(e => e.appendChild(document.createTextNode('\n')));
        return (copy.textContent || '').split('\n').map(clean).filter(Boolean).join('\n');
    };
    const verdict = element => {
        if (!element) return null;
        return ['correct', 'partiallycorrect', 'incorrect'].find(value => element.classList.contains(value)) || null;
    };
    const reviewQuestions = root => Array.from(root.querySelectorAll('.que')).filter(visible).map((question, index) => {
        const read = selector => reviewText(question.querySelector(selector));
        const supported = ['multichoice', 'truefalse', 'shortanswer', 'numerical', 'essay', 'description']
            .some(type => question.classList.contains(type));
        let webReason = supported ? null : '此題包含特殊題型，請查看校方完整內容。';
        if (Array.from(question.querySelectorAll(
            'img:not(.icon), svg, math, .MathJax, .MathJax_Display, .filter_mathjaxloader, iframe, canvas, audio, video, object, embed, table, .attachments, a[href]'
        )).some(e => visible(e) && !e.closest('.info, .questionflag, .history'))) {
            webReason = '此題含圖片、公式、表格或附件，請搭配校方完整內容閱讀。';
        }
        const choices = Array.from(question.querySelectorAll('.answer input[type="radio"], .answer input[type="checkbox"]'))
            .filter(visible).map(input => {
                const row = input.closest('.r0, .r1') || input.parentElement;
                const labels = (input.getAttribute('aria-labelledby') || '').split(/\s+/)
                    .map(id => document.getElementById(id)).filter(e => e && question.contains(e));
                const text = labels.map(reviewText).filter(Boolean).join('\n') ||
                    Array.from(input.labels || []).map(reviewText).filter(Boolean).join('\n') ||
                    reviewText(row.querySelector('[data-region="answer-label"]'));
                if (!text) webReason ||= '此題選項無法完整呈現，請查看校方完整內容。';
                return {id: key(input), text, selected: input.checked,
                    verdict: verdict(row), feedback: reviewText(row.querySelector('.specificfeedback'))};
            });
        const responses = Array.from(question.querySelectorAll(
            '.answer input:not([type="hidden"]):not([type="radio"]):not([type="checkbox"]), .answer textarea, .qtype_essay_response'
        )).filter(visible).map(e => e.matches('input, textarea') ? e.value : reviewText(e));
        // Short-answer inputs may be placed directly in the formulation.
        if (!responses.length && (question.classList.contains('shortanswer') || question.classList.contains('numerical'))) {
            responses.push(...Array.from(question.querySelectorAll('.formulation input[type="text"], .formulation input[type="number"]'))
                .filter(visible).map(e => e.value));
        }
        const responseText = question.querySelector('.answer');
        if (!choices.length && !responses.length && responseText && supported && !question.classList.contains('description')) {
            const text = reviewText(responseText);
            if (text) responses.push(text);
        }
        if (question.querySelector('.answer select, .formulation [contenteditable="true"]')) {
            webReason ||= '此題的作答格式需查看校方完整內容。';
        }
        const feedback = Array.from(question.querySelectorAll('.specificfeedback'))
            .filter(e => !e.closest('.answer')).map(reviewText).filter(Boolean).join('\n');
        return {id: key(question), title: read('.info .no') || '題目 ' + (index + 1),
            text: read('.qtext'), prompt: read('.prompt'), status: read('.info .state'),
            verdict: verdict(question), mark: read('.info .grade'),
            choices, responses, correctAnswer: read('.rightanswer'), feedback,
            generalFeedback: read('.generalfeedback'), comment: read('.comment'),
            webReason};
    });
    const resultSummary = (root, currentURL) => {
        if (!/\/mod\/quiz\/(view|review)\.php(?:[?#]|$)/.test(currentURL)) return null;
        const tables = Array.from(root.querySelectorAll('table.quizreviewsummary, table.quizattemptsummary')).filter(visible);
        if (!tables.length) return null;
        const consumed = new Set();
        const content = element => {
            const copy = element.cloneNode(true);
            copy.querySelectorAll('script, style, .sr-only, .accesshide, [hidden]').forEach(e => e.remove());
            return clean(copy.textContent);
        };
        const detail = (element, label, value) => ({id: key(element), label: clean(label).replace(/[：:]\s*$/, ''), value});
        const attempts = [];
        for (const table of tables) {
            const previousCount = attempts.length;
            if (table.classList.contains('quizattemptsummary')) {
                const headers = Array.from(table.querySelectorAll('thead th')).map(content);
                for (const row of table.querySelectorAll('tbody tr')) {
                    const cells = Array.from(row.cells);
                    const details = cells.map((cell, i) => detail(cell, headers[i] || '紀錄', content(cell)))
                        .filter(d => d.value);
                    if (details.length) attempts.push({id: key(row), title: '作答紀錄 ' + (attempts.length + 1), details});
                }
            } else {
                const details = Array.from(table.querySelectorAll('tbody tr')).flatMap(row => {
                    const heading = row.querySelector('th'), value = row.querySelector('td');
                    return heading && value && content(heading) && content(value)
                        ? [detail(row, content(heading), content(value))] : [];
                });
                const cardTitle = table.closest('.card')?.querySelector('.card-title');
                if (details.length) attempts.push({
                    id: key(table), title: cardTitle ? content(cardTitle) : '作答紀錄 ' + (attempts.length + 1), details
                });
                if (cardTitle) consumed.add(cardTitle);
            }
            // Unknown/empty markup must remain available in the source notes.
            if (attempts.length > previousCount) consumed.add(table);
        }
        if (!attempts.length) return null;
        const pageHeading = root.querySelector('h1, h2');
        if (pageHeading && !pageHeading.closest('.que')) consumed.add(pageHeading);
        const information = [], notices = [];
        const addNotice = text => { if (text && !notices.includes(text)) notices.push(text); };
        for (const element of root.querySelectorAll('.activity-dates strong, [data-region="activity-dates"] strong')) {
            const row = element.parentElement;
            const label = content(element);
            const value = content(row).slice(label.length).trim();
            if (value) { information.push(detail(row, label, value)); consumed.add(row); }
        }
        for (const element of root.querySelectorAll('.quizinfo p, .quizattempt p, .quizattempt .quizattemptremaining')) {
            if (!visible(element)) continue;
            const text = content(element);
            const pair = text.match(/^([^：:]{1,60})[：:]\s*(.+)$/);
            if (pair) information.push(detail(element, pair[1], pair[2]));
            else addNotice(text);
            consumed.add(element);
        }
        let grade = null, gradeLabel = null;
        for (const heading of root.querySelectorAll('#feedback h2, #feedback h3, #feedback h4')) {
            const text = content(heading);
            const final = text.match(/^(?:.*?最後成績(?:是|為)?\s*[：:]?\s*|Your final grade (?:for this quiz )?is\s*)(.+)$/i);
            if (final) {
                grade = final[1]; gradeLabel = '最後成績'; consumed.add(heading); break;
            }
            if (/成績|grade/i.test(text)) {
                grade = text; gradeLabel = '目前成績'; consumed.add(heading); break;
            }
        }
        for (const heading of root.querySelectorAll('h2, h3')) {
            if (/^([您你]的作答[紀記]錄|Summary of your previous attempts|Summary of attempts)$/i.test(content(heading))) {
                consumed.add(heading);
            }
        }
        return {summary: {grade, gradeLabel, information, attempts, notices}, consumed};
    };
    const snapshot = () => {
        controls = new Map(); actions = new Map();
        const modal = Array.from(document.querySelectorAll('[role="dialog"], .modal.show, .moodle-dialogue')).find(visible);
        const root = modal || document.querySelector('#region-main, main[role="main"], main');
        const currentURL = location.href === 'about:blank' ? document.baseURI : location.href;
        const modulePath = /^https:\/\/euni\.niu\.edu\.tw(?::443)?\/mod\/(quiz|irs|choice|feedback|questionnaire|survey)\//;
        if (!root || !modulePath.test(currentURL)) {
            return {revision: documentID, title: '', text: '', fields: [], actions: [],
                    webReason: '需要在校方頁面完成登入或開啟此活動。'};
        }
        const result = modal ? null : resultSummary(root, currentURL);
        const isReview = !modal && /\/mod\/quiz\/review\.php(?:[?#]|$)/.test(currentURL);
        const questions = isReview ? reviewQuestions(root) : null;
        let webReason = null;
        // Timed activities may submit independently of native button taps.
        // Keep editing in the school DOM so automatic submission sees drafts.
        // Moodle always renders a hidden quiz timer, so only a visible running one counts.
        if (Array.from(document.querySelectorAll(
            '[role="timer"], [id*="timer" i], [class*="timer" i], [id*="countdown" i], [class*="countdown" i]'
        )).some(element => visible(element) && /\d/.test(element.textContent || ''))) {
            webReason = '此活動包含倒數計時，請使用校方頁面作答，以確保自動交卷時保留答案。';
        }
        const unsupported = root.querySelectorAll(
            'input[type="password"], input[type="file"], [contenteditable="true"], iframe, canvas, audio, video, math, .MathJax, .MathJax_Display, img'
        );
        if (Array.from(unsupported).some(el => visible(el) && !(isReview && el.closest('.que')) && !quizChrome(el) &&
            !(el.tagName === 'IMG' && (el.classList.contains('icon') || el.closest('.userpicture'))))) {
            webReason = '此頁包含圖片、公式、上傳或特殊互動，請使用校方頁面，避免遺漏題目內容。';
        }
        const allInputs = Array.from(root.querySelectorAll('input, textarea, select'))
            .filter(e => !(isReview && e.closest('.que')) && !quizChrome(e));
        if (allInputs.some(element => element.type !== 'hidden' && !disabled(element) &&
            !visible(element) && Array.from(element.labels || []).some(visible))) {
            webReason ||= '此頁使用特殊選項控制項，請使用校方頁面完成作答。';
        }
        const elements = allInputs.filter(visible);
        const fields = [], groups = new Map();
        for (const element of elements) {
            const type = (element.type || '').toLowerCase();
            if (['hidden', 'submit', 'button', 'reset', 'image'].includes(type)) continue;
            if (!['radio', 'checkbox', 'text', 'number', 'email', 'url', 'tel', 'search', 'textarea', 'select-one', 'select-multiple'].includes(type)) {
                webReason ||= '此題的輸入方式尚需使用校方頁面。';
                continue;
            }
            if (element.closest('.que')?.classList.contains('essay')) {
                webReason ||= '此頁包含申論或附件題，請使用校方編輯器。';
            }
            const isChoice = type === 'radio' || type === 'checkbox';
            const groupID = isChoice && element.name ?
                key(element.form || root) + ':' + type + ':' + element.name : key(element);
            if (groups.has(groupID)) { groups.get(groupID).push(element); continue; }
            groups.set(groupID, [element]);
        }
        for (const group of groups.values()) {
            const element = group[0], type = element.type;
            const id = key(element);
            const isChoice = type === 'radio' || type === 'checkbox';
            const options = isChoice ? group : element.tagName === 'SELECT' ? Array.from(element.options) : [];
            const field = {
                id,
                kind: type === 'radio' || type === 'select-one' ? 'single' :
                    type === 'checkbox' || type === 'select-multiple' ? 'multiple' :
                    type === 'textarea' ? 'longText' : 'text',
                label: (isChoice ? contextLabel(element) :
                    element.closest('.que') ? contextLabel(element) || label(element) :
                    label(element) || contextLabel(element)) || '作答',
                values: options.length ? options.filter(o => o.selected || o.checked).map(key) : [element.value || ''],
                options: options.map(o => ({id: key(o), label: label(o) || clean(o.textContent) || o.value || '選項',
                    disabled: disabled(o)})),
                required: group.some(e => e.required),
                disabled: group.every(e => disabled(e) || e.readOnly)
            };
            fields.push(field);
            controls.set(id, {element, group, options, field});
        }
        const buttons = Array.from(root.querySelectorAll('button, input[type="submit"], input[type="button"], a[href]'));
        const actionList = [];
        for (const element of buttons) {
            if (!visible(element) || element.type === 'reset') continue;
            if (isReview && (element.closest('.que') || element.tagName !== 'A')) continue;
            if (quizChrome(element)) continue;
            if (element.tagName === 'A' && !safeURL(element.href)) continue;
            if (element.closest('.activity-header, .activity-information, [data-region="activity-information"], [data-region="completion-info"], .tertiary-navigation')) continue;
            // File-picker, navigation-menu and rich-editor controls require the web UI.
            if (element.closest('.editor_atto, .tox, .filemanager, .dropdown-menu') ||
                element.getAttribute('data-toggle') === 'dropdown' ||
                element.getAttribute('data-bs-toggle') === 'dropdown') continue;
            const text = clean(element.textContent || element.value || element.getAttribute('aria-label'));
            if (!text) continue;
            if (result && disabled(element)) continue;
            if (result && element.form && !safeForm(element.form)) {
                const target = new URL(element.form.action, document.baseURI);
                // The course-return GET form is navigation, not a quiz action.
                if (element.form.method.toLowerCase() === 'get' &&
                    target.origin === 'https://euni.niu.edu.tw' && target.pathname === '/course/view.php') continue;
            }
            if (element.form && !safeForm(element.form)) {
                webReason ||= '此操作需要透過校方頁面完成。';
            }
            const fieldIDs = fields.filter(f => {
                const owner = controls.get(f.id).element.form;
                return element.tagName !== 'A' && (element.form ? owner === element.form : true);
            }).map(f => f.id);
            const action = {id: key(element), label: text,
                disabled: disabled(element), fieldIDs,
                // Quiz page navigation saves drafts; finishing still needs the summary page.
                isNavigation: (element.tagName === 'A' && safeURL(element.href)) ||
                    (element.matches('.mod_quiz-next-nav, .mod_quiz-prev-nav') && safeForm(element.form))};
            actions.set(action.id, element);
            actionList.push(action);
        }
        if (fields.length > 60 || actionList.length > 40) webReason = '此頁內容較複雜，請使用校方頁面。';
        const copy = root.cloneNode(true);
        const originals = Array.from(root.querySelectorAll('*'));
        const copies = Array.from(copy.querySelectorAll('*'));
        // Native fields already show these questions; keep the text only for web fallback.
        const nativeQuestions = new Set(webReason ? [] :
            fields.map(f => controls.get(f.id).element.closest('.que')).filter(Boolean));
        originals.forEach((element, index) => {
            if (!visible(element) || result?.consumed.has(element) || (isReview && element.matches('.que')) ||
                (element.matches('.que .info, .que .qtext, .que .ablock, .que .answer') &&
                    nativeQuestions.has(element.closest('.que')))) copies[index].remove();
        });
        if (result) {
            copy.querySelectorAll('h1, .activity-completion, [data-region="completion-info"], .tertiary-navigation').forEach(e => e.remove());
        }
        copy.querySelectorAll('script, style, noscript, input, textarea, select, button, label, nav, .accesshide, [hidden], [aria-hidden="true"], [role="timer"], [id*="timer" i], [class*="timer" i], [id*="countdown" i], [class*="countdown" i], time').forEach(e => e.remove());
        copy.querySelectorAll('p, div, tr, h1, h2, h3, li, br').forEach(e => e.appendChild(document.createTextNode('\n')));
        const fullText = (copy.textContent || '').split('\n').map(clean).filter(Boolean).join('\n');
        if (fullText.length > 16000) webReason = '題目內容較長，此處僅顯示摘要。請使用校方頁面閱讀完整題目並作答。';
        const text = fullText.slice(0, 16000);
        const title = clean(root.querySelector('h1, h2')?.textContent);
        // Changing a question, control or action invalidates pending native confirmation.
        const structure = JSON.stringify([fields.map(f => [f.id, f.kind, f.label, f.options, f.disabled]),
            actionList, text, webReason, result?.summary, questions]);
        return {revision: documentID + ':' + structure, title, text, fields, actions: actionList, webReason,
            result: result?.summary || null, reviewQuestions: questions};
    };
    const applyAnswers = (answers, allowedFields) => {
        // Validate the full payload before touching any input.
        for (const [id, values] of Object.entries(answers)) {
            const control = controls.get(id);
            if (!allowedFields.includes(id) || !control || !Array.isArray(values) || !values.every(v => typeof v === 'string')) return 'changed';
            if (control.field.disabled) continue;
            if (control.options.length && values.some(v => !control.options.some(o => key(o) === v &&
                (!disabled(o) || control.field.values.includes(v))))) return 'changed';
            if (control.field.kind === 'single' && values.length > 1) return 'changed';
            if (!control.options.length && control.element.maxLength >= 0 &&
                (values[0] || '').length > control.element.maxLength) return 'invalid';
        }
        for (const [id, values] of Object.entries(answers)) {
            const control = controls.get(id);
            if (control.field.disabled) continue;
            if (control.options.length) {
                for (const option of control.options) {
                    if (disabled(option)) continue;
                    if (option.tagName === 'OPTION') option.selected = values.includes(key(option));
                    else option.checked = values.includes(key(option));
                }
            } else {
                control.element.value = values[0] || '';
            }
        }
        return 'staged';
    };
    const stage = (revision, answers) => {
        const page = snapshot();
        if (page.revision !== revision || page.webReason) return 'changed';
        return applyAnswers(answers, page.fields.map(f => f.id));
    };
    const perform = (revision, actionID, answers) => {
        const page = snapshot();
        if (page.revision !== revision || page.webReason) return 'changed';
        const action = actions.get(actionID);
        if (!action || !visible(action) || disabled(action)) return 'changed';
        const allowedFields = page.actions.find(a => a.id === actionID).fieldIDs;
        const result = applyAnswers(answers, allowedFields);
        if (result !== 'staged') return result;
        if (action.form && !action.form.noValidate && !action.formNoValidate && !action.form.checkValidity()) return 'invalid';
        // Click the actual school control to preserve its validation and JS.
        // Do not dispatch change events: some activities auto-submit on change.
        action.click();
        return 'invoked';
    };
    const focusQuestion = id => {
        const question = Array.from(document.querySelectorAll('.que')).find(e => key(e) === id);
        if (!question || !visible(question)) return false;
        question.scrollIntoView({block: 'start'});
        return true;
    };
    window.__niuQuestionsV1 = {snapshot, stage, perform, focusQuestion};
})();
''';
