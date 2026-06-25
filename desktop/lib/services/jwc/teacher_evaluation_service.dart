import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/backend/uni_response.dart';
import '../../models/jwc/teacher_evaluation.dart';
import '../../services/aufe/connector.dart';
import '../../services/logger_service.dart';

enum EvaluationStrategy { smart, alwaysHighest }

class TeacherEvaluationService {
  final AUFEConnection connection;
  final Random _random = Random();

  TeacherEvaluationService(this.connection);

  Future<UniResponse<TeacherEvaluationCourseList>> loadCourses() async {
    try {
      final index = await _fetchIndex();
      if (index.isClosed) {
        return UniResponse.success(
          TeacherEvaluationCourseList(
            tokenValue: index.tokenValue,
            isClosed: true,
            closedMessage: index.closedMessage.isNotEmpty ? index.closedMessage : '评价暂未开启',
          ),
        );
      }
      if (index.tokenValue.isEmpty) throw Exception('未找到评教 token');
      return UniResponse.success(
        TeacherEvaluationCourseList(
          tokenValue: index.tokenValue,
          isClosed: false,
          courses: await _fetchCourses(),
        ),
      );
    } catch (e) {
      LoggerService.error('❌ 获取评教课程失败', error: e);
      return UniResponse.failure(e.toString(), retryable: true);
    }
  }

  Future<UniResponse<TeacherEvaluationPreparedForm>> prepareEvaluation(
    TeacherEvaluationCourse course,
    int pendingCount,
    String indexToken, {
    EvaluationStrategy strategy = EvaluationStrategy.smart,
  }) async {
    try {
      if (indexToken.isEmpty) throw Exception('首页 token 为空');
      final response = await connection.client.post(
        '$baseUrl/student/teachingEvaluation/teachingEvaluation/evaluationPage',
        data: _evaluationPageForm(course, pendingCount, indexToken),
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: _ajaxHeaders,
        ),
      );
      final html = response.data.toString();
      final questionnaire = _parseQuestionnaire(html);
      if (questionnaire.tokenValue.isEmpty) throw Exception('未找到评价页 token');
      if (questionnaire.radioQuestions.isEmpty && questionnaire.textQuestions.isEmpty) {
        throw Exception('未解析到评价题目');
      }

      final form = <String, String>{
        'optType': 'submit',
        'tokenValue': questionnaire.tokenValue,
        'questionnaireCode': course.questionnaireCode.ifEmpty(questionnaire.questionnaireCode),
        'evaluationContent': course.evaluationContentNumber.ifEmpty(questionnaire.evaluationContent),
        'evaluatedPeopleNumber': course.evaluatedPeopleNumber.ifEmpty(questionnaire.evaluatedPeopleNumber),
        'count': pendingCount.toString(),
      };

      for (final question in questionnaire.radioQuestions) {
        form[question.key] = _chooseOption(question, strategy: strategy).value;
      }
      for (final question in questionnaire.textQuestions) {
        form[question.key] = _randomText(question.type);
      }

      return UniResponse.success(
        TeacherEvaluationPreparedForm(
          course: course,
          questionnaireTitle: questionnaire.title,
          formData: form,
        ),
      );
    } catch (e) {
      LoggerService.error('❌ 准备评教表单失败', error: e);
      return UniResponse.failure(e.toString(), retryable: true);
    }
  }

  Future<UniResponse<TeacherEvaluationSubmitResult>> submitEvaluation(
    TeacherEvaluationPreparedForm prepared,
  ) async {
    try {
      final response = await connection.client.post(
        '$baseUrl/student/teachingEvaluation/teachingEvaluation/assessment?sf_request_type=ajax',
        data: prepared.formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: _ajaxHeaders,
        ),
      );
      final body = response.data.toString();
      final Map<String, dynamic>? json = _tryDecodeJson(response.data);
      final result = json?['result']?.toString() ?? '';
      final message = (json?['msg']?.toString() ?? '').ifEmpty(
        result.toLowerCase() == 'success'
            ? '提交成功'
            : (json != null ? '提交失败，服务端返回错误' : body.take(120)),
      );
      return UniResponse.success(
        TeacherEvaluationSubmitResult(
          success: result.toLowerCase() == 'success',
          message: message,
        ),
      );
    } catch (e) {
      LoggerService.error('❌ 提交评教失败', error: e);
      return UniResponse.failure(e.toString(), retryable: true);
    }
  }

  Future<UniResponse<bool>> verifyCourseEvaluated(TeacherEvaluationCourse course) async {
    try {
      final courseList = await loadCourses();
      if (!courseList.success || courseList.data == null) {
        return UniResponse.failure(courseList.error ?? '刷新课程列表失败', retryable: true);
      }
      final refreshedCourse = courseList.data!.courses.where((item) => item.matches(course)).firstOrNull;
      return UniResponse.success(refreshedCourse?.isEvaluated == true);
    } catch (e) {
      return UniResponse.failure(e.toString(), retryable: true);
    }
  }

  Future<TeacherEvaluationIndex> _fetchIndex() async {
    final response = await connection.client.get(
      '$baseUrl/student/teachingEvaluation/evaluation/index',
      options: Options(headers: _pageHeaders),
    );
    final html = response.data.toString();
    final doc = html_parser.parse(html);
    final alert = doc
        .querySelectorAll('#page-content-template .alert, .page-content .alert, .main-content .alert')
        .where((element) => element.text.contains('评估开关已关闭'))
        .firstOrNull;
    return TeacherEvaluationIndex(
      tokenValue: _parseTokenValue(doc, html),
      isClosed: alert != null,
      closedMessage: alert?.text.trim() ?? '',
    );
  }

  Future<List<TeacherEvaluationCourse>> _fetchCourses() async {
    final response = await connection.client.post(
      '$baseUrl/student/teachingEvaluation/teachingEvaluation/search?sf_request_type=ajax',
      data: {'optType': '1', 'pagesize': '50'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: _ajaxHeaders,
      ),
    );
    final root = _responseMap(response.data);
    final data = root['data'];
    if (data is! List) return [];
    return data
        .map(_asStringMap)
        .whereType<Map<String, dynamic>>()
        .map(_parseCourse)
        .whereType<TeacherEvaluationCourse>()
        .toList();
  }

  TeacherEvaluationCourse? _parseCourse(Map<String, dynamic> obj) {
    final id = _asStringMap(obj['id']) ?? const <String, dynamic>{};
    final questionnaire = _asStringMap(obj['questionnaire']) ?? const <String, dynamic>{};
    final course = TeacherEvaluationCourse(
      name: obj.string('evaluationContent'),
      teacher: obj.string('evaluatedPeople'),
      evaluatedPeople: obj.string('evaluatedPeople'),
      evaluatedPeopleNumber: id.string('evaluatedPeople'),
      coureSequenceNumber: id.string('coureSequenceNumber'),
      evaluationContentNumber: id.string('evaluationContentNumber'),
      questionnaireCode: questionnaire.string('questionnaireNumber'),
      questionnaireName: questionnaire.string('questionnaireName'),
      isEvaluated: obj.string('isEvaluated') == '是',
    );
    return course.name.isNotEmpty || course.teacher.isNotEmpty || course.evaluationContentNumber.isNotEmpty
        ? course
        : null;
  }

  Map<String, String> _evaluationPageForm(
    TeacherEvaluationCourse course,
    int pendingCount,
    String indexToken,
  ) =>
      {
        'count': pendingCount.toString(),
        'evaluatedPeople': course.evaluatedPeople,
        'evaluatedPeopleNumber': course.evaluatedPeopleNumber,
        'questionnaireCode': course.questionnaireCode,
        'questionnaireName': course.questionnaireName,
        'coureSequenceNumber': course.coureSequenceNumber,
        'evaluationContentNumber': course.evaluationContentNumber,
        'evaluationContentContent': '',
        'tokenValue': indexToken,
      };

  TeacherEvaluationQuestionnaire _parseQuestionnaire(String html) {
    final doc = html_parser.parse(html);
    return TeacherEvaluationQuestionnaire(
      title: doc.querySelector('div.title')?.text.trim() ??
          doc.querySelector('h1')?.text.trim() ??
          doc.querySelector('h2')?.text.trim() ??
          '',
      tokenValue: _parseQuestionnaireTokenValue(doc, html),
      questionnaireCode: doc.inputValue('wjdm'),
      evaluatedPeopleNumber: doc.inputValue('bprdm'),
      evaluationContent: doc.inputValue('pgnr'),
      evaluatedPerson: doc
              .querySelectorAll('td')
              .where((td) => td.text.contains('被评人') || td.text.contains('教师'))
              .firstOrNull
              ?.nextElementSibling
              ?.text
              .trim() ??
          '',
      radioQuestions: _parseRadioQuestions(doc),
      textQuestions: _parseTextQuestions(doc),
    );
  }

  List<TeacherEvaluationRadioQuestion> _parseRadioQuestions(Document doc) {
    final groups = <String, List<Element>>{};
    for (final radio in doc.querySelectorAll('input[type=radio][name]')) {
      final name = radio.attributes['name'] ?? '';
      if (name.isNotEmpty) groups.putIfAbsent(name, () => []).add(radio);
    }
    return groups.entries.map((entry) {
      final row = entry.value.first.nearestRow();
      final options = entry.value.map((radio) {
        final value = radio.attributes['value'] ?? '';
        if (value.isEmpty) return null;
        final scoreAndWeight = value.scoreAndWeight();
        return TeacherEvaluationOption(
          key: entry.key,
          value: value,
          score: scoreAndWeight.$1,
          weight: scoreAndWeight.$2,
          label: radio.optionLabel(doc),
        );
      }).whereType<TeacherEvaluationOption>().toList();
      if (options.isEmpty) return null;
      return TeacherEvaluationRadioQuestion(
        key: entry.key,
        category: row?.querySelector('td[rowspan]')?.text.trim() ?? '',
        title: row.questionText(minLength: 5, selectorToExclude: 'input[type=radio]').ifEmpty(
          row.previousRowText(minLength: 5),
        ),
        options: options,
      );
    }).whereType<TeacherEvaluationRadioQuestion>().toList();
  }

  List<TeacherEvaluationTextQuestion> _parseTextQuestions(Document doc) {
    return doc.querySelectorAll('textarea[name]').map((textarea) {
      final name = textarea.attributes['name'] ?? '';
      if (name.isEmpty) return null;
      final td = textarea.ancestors.firstWhereOrNull((parent) => parent.localName == 'td');
      final row = textarea.nearestRow();
      final title = td?.previousElementSibling?.text.trim().takeIfNotEmpty() ??
          td?.text.trim().takeIfLengthGreaterThan(3) ??
          row.previousRowText(minLength: 3);
      return TeacherEvaluationTextQuestion(
        key: name,
        title: title,
        required: name == 'zgpj' || name.contains('zgpj'),
        type: _textType(name, title),
      );
    }).whereType<TeacherEvaluationTextQuestion>().toList();
  }

  TeacherEvaluationOption _chooseOption(
    TeacherEvaluationRadioQuestion question, {
    EvaluationStrategy strategy = EvaluationStrategy.smart,
  }) {
    final options = [...question.options]..sort((a, b) => b.weight.compareTo(a.weight));

    // 一键非常满意：强制选最高权重
    if (strategy == EvaluationStrategy.alwaysHighest) {
      final fullWeightOptions = options.where((option) => option.weight == 1.0).toList();
      if (fullWeightOptions.isNotEmpty) {
        return fullWeightOptions[_random.nextInt(fullWeightOptions.length)];
      }
      return options.first;
    }

    final fullWeightOptions = options.where((option) => option.weight == 1.0).toList();
    if (fullWeightOptions.isNotEmpty && _random.nextDouble() < 0.8) {
      return fullWeightOptions[_random.nextInt(fullWeightOptions.length)];
    }
    final grouped = <double, List<TeacherEvaluationOption>>{};
    for (final option in options) {
      grouped.putIfAbsent(option.weight, () => []).add(option);
    }
    final weights = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final secondWeight = fullWeightOptions.isNotEmpty
        ? weights.firstWhereOrNull((weight) => weight != 1.0)
        : null;
    final secondGroup = secondWeight != null ? grouped[secondWeight] : null;
    final candidates = secondGroup ?? grouped[weights.first]!;
    return candidates[_random.nextInt(candidates.length)];
  }

  String _randomText(TeacherEvaluationTextType type) {
    final pool = switch (type) {
      TeacherEvaluationTextType.inspiration => _inspirationTexts,
      TeacherEvaluationTextType.suggestion => _suggestionTexts,
      TeacherEvaluationTextType.overall || TeacherEvaluationTextType.general => _overallTexts,
    };
    var last = '';
    for (var i = 0; i < 3; i++) {
      last = pool[_random.nextInt(pool.length)].sanitizeAnswer();
      if (last.isValidAnswer()) return last;
    }
    return last;
  }

  TeacherEvaluationTextType _textType(String name, String title) {
    if (name == 'zgpj' || name.contains('zgpj')) return TeacherEvaluationTextType.overall;
    if (title.contains('启发') || title.contains('启示')) return TeacherEvaluationTextType.inspiration;
    if (title.contains('建议') || title.contains('意见') || title.contains('改进')) {
      return TeacherEvaluationTextType.suggestion;
    }
    return TeacherEvaluationTextType.general;
  }

  String _parseTokenValue(Document doc, String html) {
    return doc.querySelector('input#tokenValue')?.attributes['value']?.takeIfNotEmpty() ??
        doc.querySelector('input[name=tokenValue]')?.attributes['value']?.takeIfNotEmpty() ??
        _tokenRegex.firstMatch(html)?.group(1) ??
        '';
  }

  String _parseQuestionnaireTokenValue(Document doc, String html) {
    return doc.querySelector('input[name=tokenValue]')?.attributes['value']?.takeIfNotEmpty() ??
        doc.querySelector('input#tokenValue')?.attributes['value']?.takeIfNotEmpty() ??
        _tokenRegex.firstMatch(html)?.group(1) ??
        '';
  }

  Map<String, dynamic> _responseMap(Object? data) {
    final decoded = _tryDecodeJson(data);
    if (decoded == null) throw const FormatException('评教课程列表响应格式异常');
    return decoded;
  }

  Map<String, dynamic>? _tryDecodeJson(Object? data) {
    try {
      if (data is Map) return _asStringMap(data);
      final body = data.toString();
      final decoded = jsonDecode(body);
      return _asStringMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static const baseUrl = 'http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118';
  static const _mobileSafariUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
  static final _tokenRegex = RegExp(r'''(?:id|name)=[\"']tokenValue[\"'][^>]*value=[\"']([^\"']+)[\"']''');
  static const _pageHeaders = {'User-Agent': _mobileSafariUa};
  static const _ajaxHeaders = {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'X-Requested-With': 'XMLHttpRequest',
    'User-Agent': _mobileSafariUa,
  };

  static const _overallTexts = [
    '老师授课有条理有重点，教会我做事要分清主次、抓住关键的思维方法',
    '老师讲课认真负责，课程内容充实丰富，理论与实践结合得很好，让我收获颇丰，对专业知识有了更深入的理解',
    '老师教学认真细致，课堂安排合理，知识点讲解清楚，能够结合实际帮助我们理解课程内容',
    '课程内容讲解清晰，老师备课充分，课堂节奏适中，整体学习体验很好，收获也比较明显',
  ];
  static const _inspirationTexts = [
    '课程内容对我很有启发，帮助我从不同角度理解专业问题，也提升了分析和解决问题的能力',
    '老师的讲解让我对课程知识有了新的认识，课堂案例也启发我把理论和实际问题联系起来思考',
    '这门课让我收获很多，不仅理解了知识点，也学会了更有条理地分析问题和表达自己的观点',
  ];
  static const _suggestionTexts = [
    '老师讲课很好，很认真负责，我没有什么建议，希望老师继续保持现有的教学方式',
    '整体教学效果很好，建议后续可以适当增加课堂互动和案例拓展，帮助同学进一步巩固理解',
    '目前课程安排比较合理，没有明显建议，希望继续保持认真负责的教学态度和清晰的讲解方式',
  ];
}

extension on Map<String, dynamic> {
  String string(String key) => this[key]?.toString() ?? '';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
  String? takeIfNotEmpty() => isNotEmpty ? this : null;
  String? takeIfLengthGreaterThan(int minLength) => length > minLength ? this : null;
  String take(int maxLength) => length <= maxLength ? this : substring(0, maxLength);
  String sanitizeAnswer() => replaceAll(RegExp(r'\s+'), '');
  bool isValidAnswer() => length >= 4 && !RegExp(r'(.)\1\1').hasMatch(this);
  (double, double) scoreAndWeight() {
    final parts = split('_');
    return (double.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0, double.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? firstWhereOrNull(bool Function(T value) predicate) {
    for (final value in this) {
      if (predicate(value)) return value;
    }
    return null;
  }
}

extension on Document {
  String inputValue(String name) => querySelector('input[name=$name]')?.attributes['value'] ?? '';
}

extension on Element {
  Iterable<Element> get ancestors sync* {
    var element = parent;
    while (element != null) {
      yield element;
      element = element.parent;
    }
  }

  Element? nearestRow() => ancestors.firstWhereOrNull((parent) => parent.localName == 'tr');

  String optionLabel(Document doc) {
    final id = this.id;
    if (id.isNotEmpty) {
      final label = doc.querySelectorAll('label').firstWhereOrNull((label) => label.attributes['for'] == id)?.text.trim();
      if (label != null && label.isNotEmpty) return label;
    }
    final parent = this.parent;
    if (parent?.localName == 'label') {
      final text = parent!.text.trim();
      if (text.isNotEmpty) return text;
    }
    return ancestors.firstWhereOrNull((parent) => parent.localName == 'td')?.text.trim() ?? '';
  }
}

extension on Element? {
  String questionText({required int minLength, required String selectorToExclude}) {
    final element = this;
    if (element == null) return '';
    return element
            .querySelectorAll('td')
            .firstWhereOrNull((cell) => cell.querySelectorAll(selectorToExclude).isEmpty && cell.text.trim().length > minLength)
            ?.text
            .trim() ??
        '';
  }

  String previousRowText({required int minLength}) {
    var previous = this?.previousElementSibling;
    while (previous != null) {
      if (previous.localName == 'tr') {
        final text = previous
                .querySelectorAll('td')
                .firstWhereOrNull((cell) => cell.text.trim().length > minLength)
                ?.text
                .trim() ??
            '';
        if (text.isNotEmpty) return text;
      }
      previous = previous.previousElementSibling;
    }
    return '';
  }
}
