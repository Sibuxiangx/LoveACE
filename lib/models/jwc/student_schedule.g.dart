// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'student_schedule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StudentScheduleResponse _$StudentScheduleResponseFromJson(
  Map<String, dynamic> json,
) => StudentScheduleResponse(
  allUnits: (json['allUnits'] as num).toDouble(),
  errorMessage: json['errorMessage'] as String? ?? '',
  xkxx:
      (json['xkxx'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const [],
  showSite: json['showSite'] as bool? ?? true,
  schoolId: json['school_id'] as String? ?? '',
  dateList:
      (json['dateList'] as List<dynamic>?)
          ?.map((e) => ScheduleDateInfo.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$StudentScheduleResponseToJson(
  StudentScheduleResponse instance,
) => <String, dynamic>{
  'allUnits': instance.allUnits,
  'errorMessage': instance.errorMessage,
  'xkxx': instance.xkxx,
  'showSite': instance.showSite,
  'school_id': instance.schoolId,
  'dateList': instance.dateList,
};

ScheduleDateInfo _$ScheduleDateInfoFromJson(Map<String, dynamic> json) =>
    ScheduleDateInfo(
      programPlanCode: json['programPlanCode'] as String? ?? '',
      programPlanName: json['programPlanName'] as String? ?? '',
      totalUnits: (json['totalUnits'] as num?)?.toDouble() ?? 0,
      selectCourseList:
          (json['selectCourseList'] as List<dynamic>?)
              ?.map((e) => ScheduleCourse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ScheduleDateInfoToJson(ScheduleDateInfo instance) =>
    <String, dynamic>{
      'programPlanCode': instance.programPlanCode,
      'programPlanName': instance.programPlanName,
      'totalUnits': instance.totalUnits,
      'selectCourseList': instance.selectCourseList,
    };

ScheduleCourse _$ScheduleCourseFromJson(Map<String, dynamic> json) =>
    ScheduleCourse(
      id: ScheduleCourseId.fromJson(json['id'] as Map<String, dynamic>),
      programPlanNumber: json['programPlanNumber'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      unit: (json['unit'] as num?)?.toDouble() ?? 0,
      programPlanName: json['programPlanName'] as String? ?? '',
      attendClassTeacher: json['attendClassTeacher'] as String? ?? '',
      studyModeCode: json['studyModeCode'] as String? ?? '',
      studyModeName: json['studyModeName'] as String? ?? '',
      coursePropertiesCode: json['coursePropertiesCode'] as String? ?? '',
      coursePropertiesName: json['coursePropertiesName'] as String? ?? '',
      examTypeCode: json['examTypeCode'] as String? ?? '',
      examTypeName: json['examTypeName'] as String? ?? '',
      courseCategoryCode: json['courseCategoryCode'] as String?,
      courseCategoryName: json['courseCategoryName'] as String?,
      restrictedCondition: json['restrictedCondition'] as String?,
      bz: json['bz'] as String?,
      timeAndPlaceList:
          (json['timeAndPlaceList'] as List<dynamic>?)
              ?.map(
                (e) => ScheduleTimePlace.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      selectCourseStatusCode: json['selectCourseStatusCode'] as String? ?? '',
      selectCourseStatusName: json['selectCourseStatusName'] as String? ?? '',
    );

Map<String, dynamic> _$ScheduleCourseToJson(ScheduleCourse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'programPlanNumber': instance.programPlanNumber,
      'courseName': instance.courseName,
      'unit': instance.unit,
      'programPlanName': instance.programPlanName,
      'attendClassTeacher': instance.attendClassTeacher,
      'studyModeCode': instance.studyModeCode,
      'studyModeName': instance.studyModeName,
      'coursePropertiesCode': instance.coursePropertiesCode,
      'coursePropertiesName': instance.coursePropertiesName,
      'examTypeCode': instance.examTypeCode,
      'examTypeName': instance.examTypeName,
      'courseCategoryCode': instance.courseCategoryCode,
      'courseCategoryName': instance.courseCategoryName,
      'restrictedCondition': instance.restrictedCondition,
      'bz': instance.bz,
      'timeAndPlaceList': instance.timeAndPlaceList,
      'selectCourseStatusCode': instance.selectCourseStatusCode,
      'selectCourseStatusName': instance.selectCourseStatusName,
    };

ScheduleCourseId _$ScheduleCourseIdFromJson(Map<String, dynamic> json) =>
    ScheduleCourseId(
      executiveEducationPlanNumber:
          json['executiveEducationPlanNumber'] as String? ?? '',
      coureNumber: json['coureNumber'] as String? ?? '',
      coureSequenceNumber: json['coureSequenceNumber'] as String? ?? '',
      studentNumber: json['studentNumber'] as String? ?? '',
    );

Map<String, dynamic> _$ScheduleCourseIdToJson(ScheduleCourseId instance) =>
    <String, dynamic>{
      'executiveEducationPlanNumber': instance.executiveEducationPlanNumber,
      'coureNumber': instance.coureNumber,
      'coureSequenceNumber': instance.coureSequenceNumber,
      'studentNumber': instance.studentNumber,
    };

ScheduleTimePlace _$ScheduleTimePlaceFromJson(Map<String, dynamic> json) =>
    ScheduleTimePlace(
      id: json['id'] as String? ?? '',
      executiveEducationPlanNumber:
          json['executiveEducationPlanNumber'] as String? ?? '',
      coureNumber: json['coureNumber'] as String? ?? '',
      coureSequenceNumber: json['coureSequenceNumber'] as String? ?? '',
      studentNumber: json['studentNumber'] as String? ?? '',
      classWeek: json['classWeek'] as String? ?? '',
      classDay: (json['classDay'] as num?)?.toInt() ?? 0,
      classSessions: (json['classSessions'] as num?)?.toInt() ?? 0,
      continuingSession: (json['continuingSession'] as num?)?.toInt() ?? 0,
      campusName: json['campusName'] as String? ?? '',
      teachingBuildingName: json['teachingBuildingName'] as String? ?? '',
      classroomName: json['classroomName'] as String? ?? '',
      weekDescription: json['weekDescription'] as String? ?? '',
      coursePropertiesName: json['coursePropertiesName'] as String? ?? '',
      coureName: json['coureName'] as String? ?? '',
    );

Map<String, dynamic> _$ScheduleTimePlaceToJson(ScheduleTimePlace instance) =>
    <String, dynamic>{
      'id': instance.id,
      'executiveEducationPlanNumber': instance.executiveEducationPlanNumber,
      'coureNumber': instance.coureNumber,
      'coureSequenceNumber': instance.coureSequenceNumber,
      'studentNumber': instance.studentNumber,
      'classWeek': instance.classWeek,
      'classDay': instance.classDay,
      'classSessions': instance.classSessions,
      'continuingSession': instance.continuingSession,
      'campusName': instance.campusName,
      'teachingBuildingName': instance.teachingBuildingName,
      'classroomName': instance.classroomName,
      'weekDescription': instance.weekDescription,
      'coursePropertiesName': instance.coursePropertiesName,
      'coureName': instance.coureName,
    };
