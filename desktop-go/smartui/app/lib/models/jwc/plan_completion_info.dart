import 'package:json_annotation/json_annotation.dart';
import 'plan_category.dart';

part 'plan_completion_info.g.dart';

/// 培养方案完成信息数据模型
@JsonSerializable()
class PlanCompletionInfo {
  /// 培养方案名称
  @JsonKey(name: 'plan_name')
  final String planName;

  /// 专业名称
  final String major;

  /// 年级
  final String grade;

  /// 根分类列表
  final List<PlanCategory> categories;

  /// 总分类数
  @JsonKey(name: 'total_categories')
  final int totalCategories;

  /// 总课程数
  @JsonKey(name: 'total_courses')
  final int totalCourses;

  /// 已通过课程数
  @JsonKey(name: 'passed_courses')
  final int passedCourses;

  /// 未通过课程数
  @JsonKey(name: 'failed_courses')
  final int failedCourses;

  /// 未修读课程数
  @JsonKey(name: 'unread_courses')
  final int unreadCourses;

  /// 预估毕业学分
  @JsonKey(name: 'estimated_graduation_credits')
  final double estimatedGraduationCredits;

  PlanCompletionInfo({
    required this.planName,
    required this.major,
    required this.grade,
    required this.categories,
    this.totalCategories = 0,
    this.totalCourses = 0,
    this.passedCourses = 0,
    this.failedCourses = 0,
    this.unreadCourses = 0,
    this.estimatedGraduationCredits = 0.0,
  });

  /// 从JSON创建实例
  factory PlanCompletionInfo.fromJson(Map<String, dynamic> json) =>
      _$PlanCompletionInfoFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$PlanCompletionInfoToJson(this);

  /// 计算统计信息
  PlanCompletionInfo calculateStatistics() {
    int totalCourses = 0;
    int passedCourses = 0;
    int failedCourses = 0;
    int unreadCourses = 0;

    void countCourses(List<PlanCategory> categories) {
      for (var category in categories) {
        for (var course in category.courses) {
          totalCourses++;
          if (course.isPassed) {
            passedCourses++;
          } else if (course.statusDescription == '未通过') {
            failedCourses++;
          } else {
            unreadCourses++;
          }
        }
        countCourses(category.subcategories);
      }
    }

    countCourses(categories);

    return PlanCompletionInfo(
      planName: planName,
      major: major,
      grade: grade,
      categories: categories,
      totalCategories: _countTotalCategories(categories),
      totalCourses: totalCourses,
      passedCourses: passedCourses,
      failedCourses: failedCourses,
      unreadCourses: unreadCourses,
      estimatedGraduationCredits: _calculateEstimatedGraduationCredits(),
    );
  }

  /// 计算总分类数
  int _countTotalCategories(List<PlanCategory> categories) {
    int count = categories.length;
    for (var category in categories) {
      count += _countTotalCategories(category.subcategories);
    }
    return count;
  }

  /// 计算预估毕业学分
  /// 统计所有叶子分类节点（没有子分类的分类）的最低学分之和
  double _calculateEstimatedGraduationCredits() {
    double total = 0.0;

    void findLeafCategories(PlanCategory category) {
      // 如果没有子分类，说明是叶子分类节点
      if (category.subcategories.isEmpty) {
        total += category.minCredits;
      } else {
        // 有子分类，继续递归查找
        for (var sub in category.subcategories) {
          findLeafCategories(sub);
        }
      }
    }

    // 遍历所有根分类
    for (var category in categories) {
      findLeafCategories(category);
    }

    return total;
  }
}
