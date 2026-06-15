import 'package:json_annotation/json_annotation.dart';
import 'course_schedule_record.dart';

part 'smart_course_selection.g.dart';

/// 智能排课预设
@JsonSerializable()
class CourseSelectionPreset {
  /// 预设ID
  final String id;

  /// 预设名称
  final String name;

  /// 创建时间
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// 更新时间
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// 学期代码
  @JsonKey(name: 'term_code')
  final String termCode;

  /// 模拟选课的课程列表（课程号_序号）
  @JsonKey(name: 'selected_courses')
  final List<String> selectedCourses;

  CourseSelectionPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.termCode,
    this.selectedCourses = const [],
  });

  factory CourseSelectionPreset.fromJson(Map<String, dynamic> json) =>
      _$CourseSelectionPresetFromJson(json);

  Map<String, dynamic> toJson() => _$CourseSelectionPresetToJson(this);

  /// 创建新预设
  factory CourseSelectionPreset.create({
    required String name,
    required String termCode,
    List<String> selectedCourses = const [],
  }) {
    final now = DateTime.now();
    return CourseSelectionPreset(
      id: '${now.millisecondsSinceEpoch}',
      name: name,
      createdAt: now,
      updatedAt: now,
      termCode: termCode,
      selectedCourses: selectedCourses,
    );
  }

  /// 复制并更新
  CourseSelectionPreset copyWith({
    String? name,
    List<String>? selectedCourses,
  }) {
    return CourseSelectionPreset(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      termCode: termCode,
      selectedCourses: selectedCourses ?? this.selectedCourses,
    );
  }
}

/// 智能排课数据（持久化存储）
@JsonSerializable()
class SmartCourseSelectionData {
  /// 用户ID
  @JsonKey(name: 'user_id')
  final String userId;

  /// 选课学期代码
  @JsonKey(name: 'term_code')
  final String termCode;

  /// 开课数据刷新时间
  @JsonKey(name: 'course_data_refresh_time')
  final DateTime? courseDataRefreshTime;

  /// 开课数据（所有可选课程）
  @JsonKey(name: 'available_courses')
  final List<CourseScheduleRecord> availableCourses;

  /// 预设列表
  final List<CourseSelectionPreset> presets;

  /// 当前选中的预设ID
  @JsonKey(name: 'current_preset_id')
  final String? currentPresetId;

  /// 当前模拟选课的课程列表（课程号_序号）
  @JsonKey(name: 'current_selected_courses')
  final List<String> currentSelectedCourses;

  /// 模拟退课的课程列表（课程号_序号）- 从原始课表中移除的课程
  @JsonKey(name: 'removed_courses')
  final List<String> removedCourses;

  /// 基准课表快照（课程号_序号列表）- 用于检测远程课表变化
  @JsonKey(name: 'base_schedule_snapshot')
  final List<String> baseScheduleSnapshot;

  /// 快照创建时间
  @JsonKey(name: 'snapshot_time')
  final DateTime? snapshotTime;

  SmartCourseSelectionData({
    required this.userId,
    required this.termCode,
    this.courseDataRefreshTime,
    this.availableCourses = const [],
    this.presets = const [],
    this.currentPresetId,
    this.currentSelectedCourses = const [],
    this.removedCourses = const [],
    this.baseScheduleSnapshot = const [],
    this.snapshotTime,
  });

  factory SmartCourseSelectionData.fromJson(Map<String, dynamic> json) =>
      _$SmartCourseSelectionDataFromJson(json);

  Map<String, dynamic> toJson() => _$SmartCourseSelectionDataToJson(this);

  /// 创建空数据
  factory SmartCourseSelectionData.empty(String userId, String termCode) {
    return SmartCourseSelectionData(
      userId: userId,
      termCode: termCode,
    );
  }

  /// 复制并更新
  SmartCourseSelectionData copyWith({
    String? termCode,
    DateTime? courseDataRefreshTime,
    List<CourseScheduleRecord>? availableCourses,
    List<CourseSelectionPreset>? presets,
    String? currentPresetId,
    List<String>? currentSelectedCourses,
    List<String>? removedCourses,
    List<String>? baseScheduleSnapshot,
    DateTime? snapshotTime,
  }) {
    return SmartCourseSelectionData(
      userId: userId,
      termCode: termCode ?? this.termCode,
      courseDataRefreshTime:
          courseDataRefreshTime ?? this.courseDataRefreshTime,
      availableCourses: availableCourses ?? this.availableCourses,
      presets: presets ?? this.presets,
      currentPresetId: currentPresetId ?? this.currentPresetId,
      currentSelectedCourses:
          currentSelectedCourses ?? this.currentSelectedCourses,
      removedCourses: removedCourses ?? this.removedCourses,
      baseScheduleSnapshot: baseScheduleSnapshot ?? this.baseScheduleSnapshot,
      snapshotTime: snapshotTime ?? this.snapshotTime,
    );
  }
}

/// 课程时间槽（用于冲突检测）
class CourseTimeSlot {
  /// 星期几（1-7）
  final int weekday;

  /// 开始节次
  final int startSession;

  /// 结束节次
  final int endSession;

  /// 上课周次（24位二进制字符串）
  final String classWeek;

  /// 课程标识
  final String courseKey;

  /// 课程名称
  final String courseName;

  CourseTimeSlot({
    required this.weekday,
    required this.startSession,
    required this.endSession,
    required this.classWeek,
    required this.courseKey,
    required this.courseName,
  });

  /// 检查是否与另一个时间槽冲突
  bool conflictsWith(CourseTimeSlot other) {
    // 不同星期不冲突
    if (weekday != other.weekday) return false;

    // 检查节次是否重叠
    if (endSession < other.startSession || startSession > other.endSession) {
      return false;
    }

    // 检查周次是否重叠
    for (int i = 0; i < classWeek.length && i < other.classWeek.length; i++) {
      if (classWeek[i] == '1' && other.classWeek[i] == '1') {
        return true; // 同一周都有课，冲突
      }
    }

    return false;
  }
}
