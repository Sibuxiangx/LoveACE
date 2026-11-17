import 'dart:math';
import 'package:json_annotation/json_annotation.dart';
import 'plan_course.dart';

part 'plan_category.g.dart';

/// 培养方案分类数据模型
@JsonSerializable()
class PlanCategory {
  /// 分类ID
  @JsonKey(name: 'category_id')
  final String categoryId;

  /// 分类名称
  @JsonKey(name: 'category_name')
  final String categoryName;

  /// 最低修读学分
  @JsonKey(name: 'min_credits')
  final double minCredits;

  /// 通过学分
  @JsonKey(name: 'completed_credits')
  final double completedCredits;

  /// 已修课程门数
  @JsonKey(name: 'total_courses')
  final int totalCourses;

  /// 已及格课程门数
  @JsonKey(name: 'passed_courses')
  final int passedCourses;

  /// 未及格课程门数
  @JsonKey(name: 'failed_courses')
  final int failedCourses;

  /// 必修课缺修门数
  @JsonKey(name: 'missing_required_courses')
  final int missingRequiredCourses;

  /// 子分类列表
  final List<PlanCategory> subcategories;

  /// 课程列表
  final List<PlanCourse> courses;

  PlanCategory({
    required this.categoryId,
    required this.categoryName,
    this.minCredits = 0.0,
    this.completedCredits = 0.0,
    this.totalCourses = 0,
    this.passedCourses = 0,
    this.failedCourses = 0,
    this.missingRequiredCourses = 0,
    this.subcategories = const [],
    this.courses = const [],
  });

  /// 从JSON创建实例
  factory PlanCategory.fromJson(Map<String, dynamic> json) =>
      _$PlanCategoryFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$PlanCategoryToJson(this);

  /// 从 zTree 节点创建分类对象
  factory PlanCategory.fromZTreeNode(Map<String, dynamic> node) {
    final name = node['name'] as String? ?? '';
    final flagId = node['flagId'] as String? ?? '';

    // 移除 HTML 标签
    final cleanName = name
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();

    // 解析统计信息
    final statsPattern = RegExp(
      r'([^(]+)\(最低修读学分:([0-9.]+),通过学分:([0-9.]+),'
      r'已修课程门数:(\d+),已及格课程门数:(\d+),'
      r'未及格课程门数:(\d+),必修课缺修门数:(\d+)\)',
    );

    final match = statsPattern.firstMatch(cleanName);

    if (match != null) {
      return PlanCategory(
        categoryId: flagId,
        categoryName: match.group(1)!.trim(),
        minCredits: double.parse(match.group(2)!),
        completedCredits: double.parse(match.group(3)!),
        totalCourses: int.parse(match.group(4)!),
        passedCourses: int.parse(match.group(5)!),
        failedCourses: int.parse(match.group(6)!),
        missingRequiredCourses: int.parse(match.group(7)!),
      );
    }

    // 子分类可能没有完整统计信息
    return PlanCategory(
      categoryId: flagId,
      categoryName: cleanName,
    );
  }

  /// 计算完成百分比
  double get completionPercentage {
    if (minCredits <= 0) return 0;
    return (completedCredits / minCredits * 100).clamp(0, 100);
  }

  /// 是否达标
  bool get isCompleted => completedCredits >= minCredits;

  /// 是否有子项
  bool get hasChildren => subcategories.isNotEmpty || courses.isNotEmpty;

  /// 获取层级深度
  int getDepth() {
    if (subcategories.isEmpty) return 0;
    return 1 + subcategories.map((s) => s.getDepth()).reduce(max);
  }
}
