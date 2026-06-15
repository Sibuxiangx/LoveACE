import 'package:json_annotation/json_annotation.dart';
import '../../utils/jwc_utils.dart';

part 'academic_info.g.dart';

/// 学业信息数据模型
@JsonSerializable()
class AcademicInfo {
  /// 已修课程数
  @JsonKey(name: 'courseNum')
  final int completedCourses;

  /// 不及格课程数
  @JsonKey(name: 'coursePas')
  final int failedCourses;

  /// 平均绩点
  @JsonKey(name: 'gpa')
  final double gpa;

  /// 待修课程数（必修且未修）
  @JsonKey(name: 'courseNum_bxqyxd')
  final int pendingCourses;

  /// 当前学期代码（格式：xxxx-yyyy-1-1）
  @JsonKey(name: 'zxjxjhh')
  final String currentTerm;

  /// 当前学期名称（计算属性，格式：xxxx-yyyy秋季学期）
  @JsonKey(includeFromJson: false, includeToJson: false)
  String get currentTermName => JWCUtils.convertTermFormat(currentTerm);

  AcademicInfo({
    required this.completedCourses,
    required this.failedCourses,
    required this.gpa,
    required this.pendingCourses,
    required this.currentTerm,
  });

  /// 从JSON创建实例
  factory AcademicInfo.fromJson(Map<String, dynamic> json) =>
      _$AcademicInfoFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$AcademicInfoToJson(this);
}
