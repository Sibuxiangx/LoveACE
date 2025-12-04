import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'award_project.g.dart';

/// 获奖项目数据模型
@JsonSerializable()
class AwardProject {
  /// 申报ID
  @JsonKey(name: 'project_id')
  final String projectId;

  /// 项目名称/赛事名称
  @JsonKey(name: 'project_name')
  final String projectName;

  /// 级别（校级/省部级/国家级）
  final String level;

  /// 等级（一等奖/二等奖等）
  final String grade;

  /// 获奖日期 YYYY/M/D
  @JsonKey(name: 'award_date')
  final String awardDate;

  /// 主持人姓名
  @JsonKey(name: 'applicant_id')
  final String applicantId;

  /// 参与人姓名（当前用户）
  @JsonKey(name: 'applicant_name')
  final String applicantName;

  /// 顺序号
  final int order;

  /// 获奖学分
  final double credits;

  /// 奖励金额
  final double bonus;

  /// 申报状态
  final String status;

  /// 学校审核状态
  @JsonKey(name: 'verification_status')
  final String verificationStatus;

  AwardProject({
    this.projectId = '',
    this.projectName = '',
    this.level = '',
    this.grade = '',
    this.awardDate = '',
    this.applicantId = '',
    this.applicantName = '',
    this.order = 0,
    this.credits = 0.0,
    this.bonus = 0.0,
    this.status = '',
    this.verificationStatus = '',
  });

  /// 从JSON创建实例
  factory AwardProject.fromJson(Map<String, dynamic> json) =>
      _$AwardProjectFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$AwardProjectToJson(this);

  /// 获取等级颜色
  /// 
  /// 根据项目等级和主题模式返回合适的颜色
  /// - 国家级：红色
  /// - 省部级/省级：橙色
  /// - 校级：蓝色
  /// - 其他：灰色
  Color getLevelColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (level.contains('国家级')) {
      return isDark ? Colors.red.shade300 : Colors.red;
    } else if (level.contains('省部级') || level.contains('省级')) {
      return isDark ? Colors.orange.shade300 : Colors.orange;
    } else if (level.contains('校级')) {
      return isDark ? Colors.blue.shade300 : Colors.blue;
    }
    return isDark ? Colors.grey.shade300 : Colors.grey;
  }

  /// 获取等级图标
  /// 
  /// 根据项目等级返回对应的图标
  /// - 国家级：奖杯图标
  /// - 省部级/省级：军功章图标
  /// - 校级：学校图标
  /// - 其他：奖杯图标
  IconData getLevelIcon() {
    if (level.contains('国家级')) {
      return Icons.emoji_events;
    } else if (level.contains('省部级') || level.contains('省级')) {
      return Icons.military_tech;
    } else if (level.contains('校级')) {
      return Icons.school;
    }
    return Icons.emoji_events;
  }

  /// 获取审核状态图标
  /// 
  /// 根据审核状态返回对应的图标
  /// - 通过：勾选图标
  /// - 未通过：取消图标
  /// - 其他：时钟图标
  IconData getVerificationIcon() {
    if (verificationStatus.contains('通过')) {
      return Icons.check_circle;
    } else if (verificationStatus.contains('未通过')) {
      return Icons.cancel;
    }
    return Icons.schedule;
  }

  /// 获取审核状态颜色
  /// 
  /// 根据审核状态和主题模式返回合适的颜色
  /// - 通过：绿色
  /// - 未通过：红色
  /// - 其他：灰色
  Color getVerificationColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (verificationStatus.contains('通过')) {
      return isDark ? Colors.green.shade300 : Colors.green;
    } else if (verificationStatus.contains('未通过')) {
      return isDark ? Colors.red.shade300 : Colors.red;
    }
    return Colors.grey;
  }
}
