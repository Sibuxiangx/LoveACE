// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exam_schedule_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExamScheduleItem _$ExamScheduleItemFromJson(Map<String, dynamic> json) =>
    ExamScheduleItem(
      title: json['title'] as String,
      start: json['start'] as String,
      color: json['color'] as String,
    );

Map<String, dynamic> _$ExamScheduleItemToJson(ExamScheduleItem instance) =>
    <String, dynamic>{
      'title': instance.title,
      'start': instance.start,
      'color': instance.color,
    };
