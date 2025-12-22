import 'package:json_annotation/json_annotation.dart';

part 'student_schedule.g.dart';

/// 学生课表响应
@JsonSerializable()
class StudentScheduleResponse {
  /// 总学分
  @JsonKey(name: 'allUnits')
  final double allUnits;

  /// 错误消息
  @JsonKey(name: 'errorMessage')
  final String errorMessage;

  /// 课程信息映射（课程号_序号 -> 课程详情）
  @JsonKey(name: 'xkxx')
  final List<Map<String, dynamic>> xkxx;

  /// 是否显示地点
  @JsonKey(name: 'showSite')
  final bool showSite;

  /// 学校ID
  @JsonKey(name: 'school_id')
  final String schoolId;

  /// 日期列表（包含培养方案信息）
  @JsonKey(name: 'dateList')
  final List<ScheduleDateInfo> dateList;

  StudentScheduleResponse({
    required this.allUnits,
    this.errorMessage = '',
    this.xkxx = const [],
    this.showSite = true,
    this.schoolId = '',
    this.dateList = const [],
  });

  factory StudentScheduleResponse.fromJson(Map<String, dynamic> json) =>
      _$StudentScheduleResponseFromJson(json);

  Map<String, dynamic> toJson() => _$StudentScheduleResponseToJson(this);

  /// 获取所有课程列表
  List<ScheduleCourse> get courses {
    final result = <ScheduleCourse>[];
    for (final dateInfo in dateList) {
      result.addAll(dateInfo.selectCourseList);
    }
    return result;
  }
}

/// 日期信息（包含培养方案和课程列表）
@JsonSerializable()
class ScheduleDateInfo {
  /// 培养方案代码
  @JsonKey(name: 'programPlanCode')
  final String programPlanCode;

  /// 培养方案名称
  @JsonKey(name: 'programPlanName')
  final String programPlanName;

  /// 总学分
  @JsonKey(name: 'totalUnits')
  final double totalUnits;

  /// 选课列表
  @JsonKey(name: 'selectCourseList')
  final List<ScheduleCourse> selectCourseList;

  ScheduleDateInfo({
    this.programPlanCode = '',
    this.programPlanName = '',
    this.totalUnits = 0,
    this.selectCourseList = const [],
  });

  factory ScheduleDateInfo.fromJson(Map<String, dynamic> json) =>
      _$ScheduleDateInfoFromJson(json);

  Map<String, dynamic> toJson() => _$ScheduleDateInfoToJson(this);
}


/// 课表课程
@JsonSerializable()
class ScheduleCourse {
  /// 课程ID
  @JsonKey(name: 'id')
  final ScheduleCourseId id;

  /// 培养方案编号
  @JsonKey(name: 'programPlanNumber')
  final String programPlanNumber;

  /// 课程名称
  @JsonKey(name: 'courseName')
  final String courseName;

  /// 学分
  @JsonKey(name: 'unit')
  final double unit;

  /// 培养方案名称
  @JsonKey(name: 'programPlanName')
  final String programPlanName;

  /// 授课教师
  @JsonKey(name: 'attendClassTeacher')
  final String attendClassTeacher;

  /// 修读方式代码
  @JsonKey(name: 'studyModeCode')
  final String studyModeCode;

  /// 修读方式名称
  @JsonKey(name: 'studyModeName')
  final String studyModeName;

  /// 课程性质代码
  @JsonKey(name: 'coursePropertiesCode')
  final String coursePropertiesCode;

  /// 课程性质名称
  @JsonKey(name: 'coursePropertiesName')
  final String coursePropertiesName;

  /// 考试类型代码
  @JsonKey(name: 'examTypeCode')
  final String examTypeCode;

  /// 考试类型名称
  @JsonKey(name: 'examTypeName')
  final String examTypeName;

  /// 课程类别代码
  @JsonKey(name: 'courseCategoryCode')
  final String? courseCategoryCode;

  /// 课程类别名称
  @JsonKey(name: 'courseCategoryName')
  final String? courseCategoryName;

  /// 限制条件
  @JsonKey(name: 'restrictedCondition')
  final String? restrictedCondition;

  /// 备注
  @JsonKey(name: 'bz')
  final String? bz;

  /// 时间地点列表
  @JsonKey(name: 'timeAndPlaceList')
  final List<ScheduleTimePlace> timeAndPlaceList;

  /// 选课状态代码
  @JsonKey(name: 'selectCourseStatusCode')
  final String selectCourseStatusCode;

  /// 选课状态名称
  @JsonKey(name: 'selectCourseStatusName')
  final String selectCourseStatusName;

  ScheduleCourse({
    required this.id,
    this.programPlanNumber = '',
    this.courseName = '',
    this.unit = 0,
    this.programPlanName = '',
    this.attendClassTeacher = '',
    this.studyModeCode = '',
    this.studyModeName = '',
    this.coursePropertiesCode = '',
    this.coursePropertiesName = '',
    this.examTypeCode = '',
    this.examTypeName = '',
    this.courseCategoryCode,
    this.courseCategoryName,
    this.restrictedCondition,
    this.bz,
    this.timeAndPlaceList = const [],
    this.selectCourseStatusCode = '',
    this.selectCourseStatusName = '',
  });

  factory ScheduleCourse.fromJson(Map<String, dynamic> json) =>
      _$ScheduleCourseFromJson(json);

  Map<String, dynamic> toJson() => _$ScheduleCourseToJson(this);

  /// 课程号
  String get courseCode => id.coureNumber;

  /// 课序号
  String get courseSequence => id.coureSequenceNumber;

  /// 唯一标识
  String get uniqueKey => '${id.coureNumber}_${id.coureSequenceNumber}';
}

/// 课程ID
@JsonSerializable()
class ScheduleCourseId {
  /// 执行教学计划号（学期代码）
  @JsonKey(name: 'executiveEducationPlanNumber')
  final String executiveEducationPlanNumber;

  /// 课程号
  @JsonKey(name: 'coureNumber')
  final String coureNumber;

  /// 课序号
  @JsonKey(name: 'coureSequenceNumber')
  final String coureSequenceNumber;

  /// 学号
  @JsonKey(name: 'studentNumber')
  final String studentNumber;

  ScheduleCourseId({
    this.executiveEducationPlanNumber = '',
    this.coureNumber = '',
    this.coureSequenceNumber = '',
    this.studentNumber = '',
  });

  factory ScheduleCourseId.fromJson(Map<String, dynamic> json) =>
      _$ScheduleCourseIdFromJson(json);

  Map<String, dynamic> toJson() => _$ScheduleCourseIdToJson(this);
}

/// 时间地点信息
@JsonSerializable()
class ScheduleTimePlace {
  /// ID
  @JsonKey(name: 'id')
  final String id;

  /// 执行教学计划号
  @JsonKey(name: 'executiveEducationPlanNumber')
  final String executiveEducationPlanNumber;

  /// 课程号
  @JsonKey(name: 'coureNumber')
  final String coureNumber;

  /// 课序号
  @JsonKey(name: 'coureSequenceNumber')
  final String coureSequenceNumber;

  /// 学号
  @JsonKey(name: 'studentNumber')
  final String studentNumber;

  /// 上课周次（24位二进制字符串，1表示有课）
  @JsonKey(name: 'classWeek')
  final String classWeek;

  /// 星期几（1-7）
  @JsonKey(name: 'classDay')
  final int classDay;

  /// 开始节次
  @JsonKey(name: 'classSessions')
  final int classSessions;

  /// 连续节数
  @JsonKey(name: 'continuingSession')
  final int continuingSession;

  /// 校区名称
  @JsonKey(name: 'campusName')
  final String campusName;

  /// 教学楼名称
  @JsonKey(name: 'teachingBuildingName')
  final String teachingBuildingName;

  /// 教室名称
  @JsonKey(name: 'classroomName')
  final String classroomName;

  /// 周次描述
  @JsonKey(name: 'weekDescription')
  final String weekDescription;

  /// 课程性质名称
  @JsonKey(name: 'coursePropertiesName')
  final String coursePropertiesName;

  /// 课程名称
  @JsonKey(name: 'coureName')
  final String coureName;

  ScheduleTimePlace({
    this.id = '',
    this.executiveEducationPlanNumber = '',
    this.coureNumber = '',
    this.coureSequenceNumber = '',
    this.studentNumber = '',
    this.classWeek = '',
    this.classDay = 0,
    this.classSessions = 0,
    this.continuingSession = 0,
    this.campusName = '',
    this.teachingBuildingName = '',
    this.classroomName = '',
    this.weekDescription = '',
    this.coursePropertiesName = '',
    this.coureName = '',
  });

  factory ScheduleTimePlace.fromJson(Map<String, dynamic> json) =>
      _$ScheduleTimePlaceFromJson(json);

  Map<String, dynamic> toJson() => _$ScheduleTimePlaceToJson(this);

  /// 结束节次
  int get endSession => classSessions + continuingSession - 1;

  /// 地点描述
  String get locationDescription => '$campusName $teachingBuildingName $classroomName';
}
