// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smart_course_selection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CourseSelectionPreset _$CourseSelectionPresetFromJson(
  Map<String, dynamic> json,
) => CourseSelectionPreset(
  id: json['id'] as String,
  name: json['name'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  termCode: json['term_code'] as String,
  selectedCourses:
      (json['selected_courses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$CourseSelectionPresetToJson(
  CourseSelectionPreset instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'term_code': instance.termCode,
  'selected_courses': instance.selectedCourses,
};

SmartCourseSelectionData _$SmartCourseSelectionDataFromJson(
  Map<String, dynamic> json,
) => SmartCourseSelectionData(
  userId: json['user_id'] as String,
  termCode: json['term_code'] as String,
  courseDataRefreshTime: json['course_data_refresh_time'] == null
      ? null
      : DateTime.parse(json['course_data_refresh_time'] as String),
  availableCourses:
      (json['available_courses'] as List<dynamic>?)
          ?.map((e) => CourseScheduleRecord.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  presets:
      (json['presets'] as List<dynamic>?)
          ?.map(
            (e) => CourseSelectionPreset.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const [],
  currentPresetId: json['current_preset_id'] as String?,
  currentSelectedCourses:
      (json['current_selected_courses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  removedCourses:
      (json['removed_courses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  baseScheduleSnapshot:
      (json['base_schedule_snapshot'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  snapshotTime: json['snapshot_time'] == null
      ? null
      : DateTime.parse(json['snapshot_time'] as String),
);

Map<String, dynamic> _$SmartCourseSelectionDataToJson(
  SmartCourseSelectionData instance,
) => <String, dynamic>{
  'user_id': instance.userId,
  'term_code': instance.termCode,
  'course_data_refresh_time': instance.courseDataRefreshTime?.toIso8601String(),
  'available_courses': instance.availableCourses,
  'presets': instance.presets,
  'current_preset_id': instance.currentPresetId,
  'current_selected_courses': instance.currentSelectedCourses,
  'removed_courses': instance.removedCourses,
  'base_schedule_snapshot': instance.baseScheduleSnapshot,
  'snapshot_time': instance.snapshotTime?.toIso8601String(),
};
