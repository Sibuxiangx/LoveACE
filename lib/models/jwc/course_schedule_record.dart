import 'package:json_annotation/json_annotation.dart';

part 'course_schedule_record.g.dart';

/// 课程开课记录数据模型
///
/// 对应教务系统的课程开课查询结果
@JsonSerializable()
class CourseScheduleRecord {
  /// 记录ID
  final String? id;

  /// 执行教学计划号
  final String? zxjxjhh;

  /// 课程号
  final String? kch;

  /// 课序号
  final String? kxh;

  /// 课程名
  final String? kcm;

  /// 学分
  final int? xf;

  /// 学时
  final int? xs;

  /// 开课院系号
  final String? kkxsh;

  /// 开课院系简称
  final String? kkxsjc;

  /// 考试类型代码
  final String? kslxdm;

  /// 考试类型名称
  final String? kslxmc;

  /// 授课教师
  final String? skjs;

  /// 本科生课容量
  final int? bkskrl;

  /// 本科生课余量
  final int? bkskyl;

  /// 选课模式代码
  final String? xkmsdm;

  /// 选课模式说明
  final String? xkmssm;

  /// 选课控制代码
  final String? xkkzdm;

  /// 选课控制说明
  final String? xkkzsm;

  /// 选课控制号
  final String? xkkzh;

  /// 选课限制说明
  final String? xkxzsm;

  /// 开课校区号
  final String? kkxqh;

  /// 开课校区名
  final String? kkxqm;

  /// 校区号
  final String? xqh;

  /// 教学楼号
  final String? jxlh;

  /// 教室号
  final String? jash;

  /// 上课周次
  final String? skzc;

  /// 上课星期
  final int? skxq;

  /// 上课节次
  final int? skjc;

  /// 持续节次
  final int? cxjc;

  /// 周次说明
  final String? zcsm;

  /// 课程类别代码
  final String? kclbdm;

  /// 课程类别名称
  final String? kclbmc;

  /// 选课备注
  final String? xkbz;

  /// 校区名
  final String? xqm;

  /// 教学楼名
  final String? jxlm;

  /// 教室名
  final String? jasm;

  /// 面向班级
  final String? mxbj;

  /// 学生数
  final int? xss;

  CourseScheduleRecord({
    this.id,
    this.zxjxjhh,
    this.kch,
    this.kxh,
    this.kcm,
    this.xf,
    this.xs,
    this.kkxsh,
    this.kkxsjc,
    this.kslxdm,
    this.kslxmc,
    this.skjs,
    this.bkskrl,
    this.bkskyl,
    this.xkmsdm,
    this.xkmssm,
    this.xkkzdm,
    this.xkkzsm,
    this.xkkzh,
    this.xkxzsm,
    this.kkxqh,
    this.kkxqm,
    this.xqh,
    this.jxlh,
    this.jash,
    this.skzc,
    this.skxq,
    this.skjc,
    this.cxjc,
    this.zcsm,
    this.kclbdm,
    this.kclbmc,
    this.xkbz,
    this.xqm,
    this.jxlm,
    this.jasm,
    this.mxbj,
    this.xss,
  });

  factory CourseScheduleRecord.fromJson(Map<String, dynamic> json) =>
      _$CourseScheduleRecordFromJson(json);

  Map<String, dynamic> toJson() => _$CourseScheduleRecordToJson(this);

  /// 获取节次字符串，如 "1-2"
  String? get classTimeStr {
    if (skjc == null || cxjc == null) return null;
    return '$skjc-${skjc! + cxjc! - 1}';
  }

  /// 获取星期几的中文表示
  String? get weekdayStr {
    if (skxq == null) return null;
    const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (skxq! >= 1 && skxq! <= 7) {
      return weekdays[skxq!];
    }
    return null;
  }

  /// 获取教师名（去除空格）
  String? get teacherName => skjs?.trim();

  /// 获取完整的上课时间地点描述
  String get scheduleDescription {
    final parts = <String>[];
    if (weekdayStr != null) parts.add(weekdayStr!);
    if (classTimeStr != null) parts.add('第$classTimeStr节');
    if (zcsm != null && zcsm!.isNotEmpty) parts.add(zcsm!);
    if (jxlm != null && jasm != null) {
      parts.add('$jxlm$jasm');
    } else if (xqm != null) {
      parts.add(xqm!);
    }
    return parts.join(' ');
  }
}

/// 课程开课查询响应的分页上下文
@JsonSerializable()
class CourseSchedulePageContext {
  final int totalCount;

  CourseSchedulePageContext({required this.totalCount});

  factory CourseSchedulePageContext.fromJson(Map<String, dynamic> json) =>
      _$CourseSchedulePageContextFromJson(json);

  Map<String, dynamic> toJson() => _$CourseSchedulePageContextToJson(this);
}

/// 课程开课查询响应的列表数据
@JsonSerializable()
class CourseScheduleList {
  final int pageSize;
  final int pageNum;
  final CourseSchedulePageContext pageContext;
  final List<CourseScheduleRecord> records;

  CourseScheduleList({
    required this.pageSize,
    required this.pageNum,
    required this.pageContext,
    required this.records,
  });

  factory CourseScheduleList.fromJson(Map<String, dynamic> json) =>
      _$CourseScheduleListFromJson(json);

  Map<String, dynamic> toJson() => _$CourseScheduleListToJson(this);
}

/// 课程开课查询响应
@JsonSerializable()
class CourseScheduleResponse {
  final int pfcx;
  final CourseScheduleList list;

  CourseScheduleResponse({
    required this.pfcx,
    required this.list,
  });

  factory CourseScheduleResponse.fromJson(Map<String, dynamic> json) =>
      _$CourseScheduleResponseFromJson(json);

  Map<String, dynamic> toJson() => _$CourseScheduleResponseToJson(this);
}
