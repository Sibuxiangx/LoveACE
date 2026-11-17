import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'plan_course.g.dart';

/// 培养方案课程数据模型
@JsonSerializable()
class PlanCourse {
  /// 课程代码
  @JsonKey(name: 'course_code')
  final String courseCode;

  /// 课程名称
  @JsonKey(name: 'course_name')
  final String courseName;

  /// 学分
  final double? credits;

  /// 成绩
  final String? score;

  /// 考试日期
  @JsonKey(name: 'exam_date')
  final String? examDate;

  /// 课程类型（必修/任选等）
  @JsonKey(name: 'course_type')
  final String courseType;

  /// 是否通过
  @JsonKey(name: 'is_passed')
  final bool isPassed;

  /// 状态描述（未修读/已通过/未通过）
  @JsonKey(name: 'status_description')
  final String statusDescription;

  PlanCourse({
    required this.courseCode,
    required this.courseName,
    this.credits,
    this.score,
    this.examDate,
    this.courseType = '',
    this.isPassed = false,
    this.statusDescription = '未修读',
  });

  /// 从JSON创建实例
  factory PlanCourse.fromJson(Map<String, dynamic> json) =>
      _$PlanCourseFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$PlanCourseToJson(this);

  /// 从 zTree 节点创建课程对象
  factory PlanCourse.fromZTreeNode(Map<String, dynamic> node) {
    final name = node['name'] as String? ?? '';
    final flagType = node['flagType'] as String? ?? '';

    // 判断通过状态
    bool isPassed = false;
    String statusDescription = '未修读';

    if (name.contains('fa-smile-o fa-1x green')) {
      isPassed = true;
      statusDescription = '已通过';
    } else if (name.contains('fa-meh-o fa-1x light-grey')) {
      isPassed = false;
      statusDescription = '未修读';
    } else if (name.contains('fa-frown-o fa-1x red')) {
      isPassed = false;
      statusDescription = '未通过';
    }

    // 移除 HTML 标签
    final cleanName = name
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();

    // 解析课程信息
    String courseCode = '';
    String courseName = '';
    double? credits;
    String? score;
    String? examDate;
    String courseType = '';

    if (flagType == 'kch') {
      // 解析课程代码
      final codeMatch = RegExp(r'\[([^\]]+)\]').firstMatch(cleanName);
      if (codeMatch != null) {
        courseCode = codeMatch.group(1)!;
        var remaining = cleanName.substring(codeMatch.end).trim();

        // 解析学分
        final creditMatch = RegExp(r'\[([0-9.]+)学分\]').firstMatch(remaining);
        if (creditMatch != null) {
          credits = double.tryParse(creditMatch.group(1)!);
          remaining = remaining.replaceFirst(creditMatch.group(0)!, '').trim();
        }

        // 解析括号内容
        final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(remaining);
        if (parenMatch != null) {
          final parenContent = parenMatch.group(1)!;
          courseName = remaining.substring(0, parenMatch.start).trim();

          // 提取成绩和日期
          final scoreMatch = RegExp(r'([0-9.]+)').firstMatch(parenContent);
          if (scoreMatch != null) {
            score = scoreMatch.group(1);
          }

          final dateMatch = RegExp(r'(\d{8})').firstMatch(parenContent);
          if (dateMatch != null) {
            examDate = dateMatch.group(1);
          }

          // 提取课程类型
          if (parenContent.contains(',')) {
            courseType = parenContent.split(',')[0].trim();
          }
        } else {
          courseName = remaining;
        }
      }
    }

    return PlanCourse(
      courseCode: courseCode,
      courseName: courseName,
      credits: credits,
      score: score,
      examDate: examDate,
      courseType: courseType,
      isPassed: isPassed,
      statusDescription: statusDescription,
    );
  }

  /// 获取状态图标
  IconData get statusIcon {
    if (isPassed) return Icons.check_circle;
    if (statusDescription == '未通过') return Icons.cancel;
    return Icons.radio_button_unchecked;
  }

  /// 获取状态颜色
  Color getStatusColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPassed) {
      return isDark ? Colors.green.shade300 : Colors.green;
    }
    if (statusDescription == '未通过') {
      return isDark ? Colors.red.shade300 : Colors.red;
    }
    return Colors.grey;
  }
}
