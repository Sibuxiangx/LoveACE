import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/backend/uni_response.dart';
import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/term_item.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

class ClassCurriculumOption {
  final String code;
  final String name;

  ClassCurriculumOption({required this.code, required this.name});
}

class ClassCurriculumClassOption {
  final String planCode;
  final String classCode;
  final String className;
  final String? departmentName;
  final String? subjectName;

  ClassCurriculumClassOption({
    required this.planCode,
    required this.classCode,
    required this.className,
    this.departmentName,
    this.subjectName,
  });
}

class ClassCurriculumService {
  final AUFEConnection connection;
  final JWCConfig config;

  static const Map<String, String> endpoints = {
    'index': '/student/teachingResources/classCurriculum/index',
    'search': '/student/teachingResources/classCurriculum/search',
    'subjectJson':
        '/student/teachingResources/gradeAndClassCurriculum/subjectJson',
    'callback':
        '/student/teachingResources/classCurriculum/searchCurriculumInfo/callback',
  };

  ClassCurriculumService(this.connection, this.config);

  Future<UniResponse<List<TermItem>>> getTerms() async {
    try {
      return await RetryHandler.retry(
        operation: () async {
          final url = config.toFullUrl(endpoints['index']!);
          final response = await connection.client.get(url);
          var htmlContent = response.data;
          if (htmlContent == null) throw Exception('班级课表页面响应为空');
          if (htmlContent is! String) htmlContent = htmlContent.toString();

          final document = html_parser.parse(htmlContent);
          final select = document.querySelector(
                'select[name="executiveEducationPlanNum"]',
              ) ??
              document.querySelector('select#executiveEducationPlanNum');
          if (select == null) throw Exception('未找到班级课表学期筛选项');

          final terms = select.querySelectorAll('option').map((option) {
            final code = option.attributes['value'] ?? '';
            final name = option.text.trim();
            return TermItem(
              termCode: code,
              termName: name,
              isCurrent: option.attributes.containsKey('selected'),
            );
          }).where((term) => term.termCode.isNotEmpty).toList();

          if (terms.isEmpty) throw Exception('未能解析出班级课表学期列表');
          return UniResponse.success(terms);
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      LoggerService.error('获取班级课表学期列表失败', error: e);
      return ErrorHandler.handleError(e, '获取班级课表学期列表失败');
    }
  }

  Future<UniResponse<List<ClassCurriculumOption>>> getDepartments() async {
    try {
      return await RetryHandler.retry(
        operation: () async {
          final url = config.toFullUrl(endpoints['index']!);
          final response = await connection.client.get(url);
          var htmlContent = response.data;
          if (htmlContent == null) throw Exception('班级课表页面响应为空');
          if (htmlContent is! String) htmlContent = htmlContent.toString();

          final document = html_parser.parse(htmlContent);
          final select = document.querySelector('select#departmentNum') ??
              document.querySelector('select[name="departmentNum"]');
          if (select == null) throw Exception('未找到院系筛选项');

          final options = select.querySelectorAll('option').map((option) {
            final code = option.attributes['value'] ?? '';
            final name = option.text.trim();
            return ClassCurriculumOption(code: code, name: name);
          }).where((option) => option.code.isNotEmpty).toList();

          return UniResponse.success(options);
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      LoggerService.error('获取班级课表院系列表失败', error: e);
      return ErrorHandler.handleError(e, '获取院系列表失败');
    }
  }

  Future<UniResponse<List<ClassCurriculumOption>>> getSubjects({
    required String departmentCode,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async {
          final url = config.toFullUrl(endpoints['subjectJson']!);
          final response = await connection.client.get(
            _withQuery(url, {'departmentNum': departmentCode}),
          );
          var data = response.data;
          if (data is String) data = jsonDecode(data);
          if (data is! List) throw Exception('专业列表响应格式错误');

          final options = data.map((item) {
            final map = item as Map<String, dynamic>;
            return ClassCurriculumOption(
              code: '${map['subjectCode'] ?? ''}',
              name: '${map['subjectName'] ?? ''}',
            );
          }).where((option) => option.code.isNotEmpty).toList();

          return UniResponse.success(options);
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      LoggerService.error('获取班级课表专业列表失败', error: e);
      return ErrorHandler.handleError(e, '获取专业列表失败');
    }
  }

  Future<UniResponse<List<ClassCurriculumClassOption>>> queryClasses({
    required String planCode,
    required String departmentCode,
    String? subjectCode,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async {
          final url = config.toFullUrl(endpoints['search']!);
          final response = await connection.client.post(
            url,
            data: {
              'executiveEducationPlanNum': planCode,
              'yearNum': '',
              'departmentNum': departmentCode,
              'subjectNum': subjectCode ?? '',
              'classNum': '',
              'pageNum': '1',
              'pageSize': '500',
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );

          var data = response.data;
          if (data is String) data = jsonDecode(data);
          if (data is! List || data.isEmpty) throw Exception('班级列表响应格式错误');

          final records = (data.first as Map<String, dynamic>)['records'];
          if (records is! List) throw Exception('班级列表 records 格式错误');

          final classes = records.map((item) {
            final map = item as Map<String, dynamic>;
            final id = (map['id'] as Map?)?.cast<String, dynamic>() ?? {};
            return ClassCurriculumClassOption(
              planCode: '${id['executiveEducationPlanNumber'] ?? planCode}',
              classCode: '${id['classNum'] ?? ''}',
              className: '${map['className'] ?? id['classNum'] ?? ''}',
              departmentName: map['departmentName']?.toString(),
              subjectName: map['subjectName']?.toString(),
            );
          }).where((item) => item.classCode.isNotEmpty).toList();

          return UniResponse.success(classes);
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      LoggerService.error('查询班级列表失败', error: e);
      return ErrorHandler.handleError(e, '查询班级列表失败');
    }
  }

  Future<UniResponse<List<CourseScheduleRecord>>> queryClassCurriculum({
    required String planCode,
    required String classCode,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async {
          final url = config.toFullUrl(endpoints['callback']!);
          final response = await connection.client.get(
            _withQuery(url, {
              'planCode': planCode,
              'classCode': classCode,
              'sf_request_type': 'ajax',
            }),
          );

          var data = response.data;
          if (data is String) data = jsonDecode(data);
          if (data is! Map<String, dynamic>) throw Exception('班级课表响应格式错误');

          final body = data['data'];
          if (body is! Map<String, dynamic>) throw Exception('班级课表 data 格式错误');
          final kbInfo = body['kbInfo'];
          if (kbInfo is! List || kbInfo.isEmpty || kbInfo.first is! List) {
            return UniResponse.success(<CourseScheduleRecord>[]);
          }

          final records = (kbInfo.first as List)
              .map((item) => _mapCourseRecord(item as Map<String, dynamic>))
              .toList();
          return UniResponse.success(records);
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
      );
    } catch (e) {
      LoggerService.error('查询班级课表失败', error: e);
      return ErrorHandler.handleError(e, '查询班级课表失败');
    }
  }

  CourseScheduleRecord _mapCourseRecord(Map<String, dynamic> item) {
    final id = (item['id'] as Map?)?.cast<String, dynamic>() ?? {};
    return CourseScheduleRecord(
      zxjxjhh: id['zxjxjhh']?.toString(),
      kch: id['kch']?.toString(),
      kxh: id['kxh']?.toString(),
      kcm: item['kcm']?.toString(),
      xf: _parseInt(item['xf']),
      kkxsh: item['kkxsh']?.toString(),
      kkxsjc: item['kkxsm']?.toString(),
      kslxdm: item['kslxdm']?.toString(),
      kslxmc: item['kslxmc']?.toString(),
      skjs: item['jsm']?.toString(),
      bkskyl: _parseInt(item['bkskyl']),
      xqh: item['xqh']?.toString(),
      jxlh: item['jxlh']?.toString(),
      jxlm: item['jxlm']?.toString(),
      jash: item['jash']?.toString(),
      jasm: item['jasm']?.toString(),
      skzc: id['skzc']?.toString(),
      skxq: _parseInt(id['skxq']),
      skjc: _parseInt(id['skjc']),
      cxjc: _parseInt(item['cxjc']),
      zcsm: item['zcsm']?.toString(),
      xqm: item['xqm']?.toString(),
      mxbj: item['bm']?.toString() ?? item['bjh']?.toString(),
      xss: _parseInt(item['xss']),
    );
  }

  int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return double.tryParse(value.toString())?.toInt();
  }

  String _withQuery(String url, Map<String, String> queryParameters) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...queryParameters,
    }).toString();
  }
}
