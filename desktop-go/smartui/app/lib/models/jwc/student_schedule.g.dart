// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'student_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StudentScheduleResponse _$StudentScheduleResponseFromJson(
  Map<String, dynamic> json,
) => StudentScheduleResponse(
  allUnits: (json['all_units'] as num).toDouble(),
  errorMessage: json['error_message'] as String? ?? '',
  xkxx:
      (json['xkxx'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const [],
  showSite: json['show_site'] as bool? ?? true,
  schoolId: json['school_id'] as String? ?? '',
  dateList:
      (json['date_list'] as List<dynamic>?)
          ?.map((e) => ScheduleDateInfo.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$StudentScheduleResponseToJson(
  StudentScheduleResponse instance,
) => <String, dynamic>{
  'all_units': instance.allUnits,
  'error_message': instance.errorMessage,
  'xkxx': instance.xkxx,
  'show_site': instance.showSite,
  'school_id': instance.schoolId,
  'date_list': instance.dateList,
};

ScheduleDateInfo _$ScheduleDateInfoFromJson(Map<String, dynamic> json) =>
    ScheduleDateInfo(
      programPlanCode: json['program_plan_code'] as String? ?? '',
      programPlanName: json['program_plan_name'] as String? ?? '',
      totalUnits: (json['total_units'] as num?)?.toDouble() ?? 0,
      selectCourseList:
          (json['select_course_list'] as List<dynamic>?)
              ?.map((e) => ScheduleCourse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ScheduleDateInfoToJson(ScheduleDateInfo instance) =>
    <String, dynamic>{
      'program_plan_code': instance.programPlanCode,
      'program_plan_name': instance.programPlanName,
      'total_units': instance.totalUnits,
      'select_course_list': instance.selectCourseList,
    };

ScheduleCourse _$ScheduleCourseFromJson(
  Map<String, dynamic> json,
) => ScheduleCourse(
  id: ScheduleCourseId.fromJson(json['id'] as Map<String, dynamic>),
  programPlanNumber: json['program_plan_number'] as String? ?? '',
  courseName: json['course_name'] as String? ?? '',
  unit: (json['unit'] as num?)?.toDouble() ?? 0,
  programPlanName: json['program_plan_name'] as String? ?? '',
  attendClassTeacher: json['attend_class_teacher'] as String? ?? '',
  studyModeCode: json['study_mode_code'] as String? ?? '',
  studyModeName: json['study_mode_name'] as String? ?? '',
  coursePropertiesCode: json['course_properties_code'] as String? ?? '',
  coursePropertiesName: json['course_properties_name'] as String? ?? '',
  examTypeCode: json['exam_type_code'] as String? ?? '',
  examTypeName: json['exam_type_name'] as String? ?? '',
  timeAndPlaceList:
      (json['time_and_place_list'] as List<dynamic>?)
          ?.map((e) => ScheduleTimePlace.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  selectCourseStatusCode: json['select_course_status_code'] as String? ?? '',
  selectCourseStatusName: json['select_course_status_name'] as String? ?? '',
);

Map<String, dynamic> _$ScheduleCourseToJson(ScheduleCourse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'program_plan_number': instance.programPlanNumber,
      'course_name': instance.courseName,
      'unit': instance.unit,
      'program_plan_name': instance.programPlanName,
      'attend_class_teacher': instance.attendClassTeacher,
      'study_mode_code': instance.studyModeCode,
      'study_mode_name': instance.studyModeName,
      'course_properties_code': instance.coursePropertiesCode,
      'course_properties_name': instance.coursePropertiesName,
      'exam_type_code': instance.examTypeCode,
      'exam_type_name': instance.examTypeName,
      'time_and_place_list': instance.timeAndPlaceList,
      'select_course_status_code': instance.selectCourseStatusCode,
      'select_course_status_name': instance.selectCourseStatusName,
    };

ScheduleCourseId _$ScheduleCourseIdFromJson(Map<String, dynamic> json) =>
    ScheduleCourseId(
      executiveEducationPlanNumber:
          json['executive_education_plan_number'] as String? ?? '',
      coureNumber: json['coure_number'] as String? ?? '',
      coureSequenceNumber: json['coure_sequence_number'] as String? ?? '',
      studentNumber: json['student_number'] as String? ?? '',
    );

Map<String, dynamic> _$ScheduleCourseIdToJson(ScheduleCourseId instance) =>
    <String, dynamic>{
      'executive_education_plan_number': instance.executiveEducationPlanNumber,
      'coure_number': instance.coureNumber,
      'coure_sequence_number': instance.coureSequenceNumber,
      'student_number': instance.studentNumber,
    };

ScheduleTimePlace _$ScheduleTimePlaceFromJson(Map<String, dynamic> json) =>
    ScheduleTimePlace(
      id: json['id'] as String? ?? '',
      executiveEducationPlanNumber:
          json['executive_education_plan_number'] as String? ?? '',
      coureNumber: json['coure_number'] as String? ?? '',
      coureSequenceNumber: json['coure_sequence_number'] as String? ?? '',
      studentNumber: json['student_number'] as String? ?? '',
      classWeek: json['class_week'] as String? ?? '',
      classDay: (json['class_day'] as num?)?.toInt() ?? 0,
      classSessions: (json['class_sessions'] as num?)?.toInt() ?? 0,
      continuingSession: (json['continuing_session'] as num?)?.toInt() ?? 0,
      campusName: json['campus_name'] as String? ?? '',
      teachingBuildingName: json['teaching_building_name'] as String? ?? '',
      classroomName: json['classroom_name'] as String? ?? '',
      weekDescription: json['week_description'] as String? ?? '',
      coursePropertiesName: json['course_properties_name'] as String? ?? '',
      coureName: json['coure_name'] as String? ?? '',
    );

Map<String, dynamic> _$ScheduleTimePlaceToJson(ScheduleTimePlace instance) =>
    <String, dynamic>{
      'id': instance.id,
      'executive_education_plan_number': instance.executiveEducationPlanNumber,
      'coure_number': instance.coureNumber,
      'coure_sequence_number': instance.coureSequenceNumber,
      'student_number': instance.studentNumber,
      'class_week': instance.classWeek,
      'class_day': instance.classDay,
      'class_sessions': instance.classSessions,
      'continuing_session': instance.continuingSession,
      'campus_name': instance.campusName,
      'teaching_building_name': instance.teachingBuildingName,
      'classroom_name': instance.classroomName,
      'week_description': instance.weekDescription,
      'course_properties_name': instance.coursePropertiesName,
      'coure_name': instance.coureName,
    };
