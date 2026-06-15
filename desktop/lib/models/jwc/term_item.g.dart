// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'term_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TermItem _$TermItemFromJson(Map<String, dynamic> json) => TermItem(
  termCode: json['term_code'] as String,
  termName: json['term_name'] as String,
  isCurrent: json['is_current'] as bool,
);

Map<String, dynamic> _$TermItemToJson(TermItem instance) => <String, dynamic>{
  'term_code': instance.termCode,
  'term_name': instance.termName,
  'is_current': instance.isCurrent,
};
