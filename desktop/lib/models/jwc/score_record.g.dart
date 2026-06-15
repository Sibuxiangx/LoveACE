// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'score_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScoreRecord _$ScoreRecordFromJson(Map<String, dynamic> json) => ScoreRecord(
  sequence: (json['sequence'] as num).toInt(),
  termId: json['term_id'] as String,
  courseCode: json['course_code'] as String,
  courseClass: json['course_class'] as String,
  courseNameCn: json['course_name_cn'] as String,
  courseNameEn: json['course_name_en'] as String,
  credits: json['credits'] as String,
  hours: (json['hours'] as num).toInt(),
  courseType: json['course_type'] as String?,
  examType: json['exam_type'] as String?,
  score: json['score'] as String,
  retakeScore: json['retake_score'] as String?,
  makeupScore: json['makeup_score'] as String?,
);

Map<String, dynamic> _$ScoreRecordToJson(ScoreRecord instance) =>
    <String, dynamic>{
      'sequence': instance.sequence,
      'term_id': instance.termId,
      'course_code': instance.courseCode,
      'course_class': instance.courseClass,
      'course_name_cn': instance.courseNameCn,
      'course_name_en': instance.courseNameEn,
      'credits': instance.credits,
      'hours': instance.hours,
      'course_type': instance.courseType,
      'exam_type': instance.examType,
      'score': instance.score,
      'retake_score': instance.retakeScore,
      'makeup_score': instance.makeupScore,
    };
