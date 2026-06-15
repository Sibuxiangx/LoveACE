// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'award_project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AwardProject _$AwardProjectFromJson(Map<String, dynamic> json) => AwardProject(
  projectId: json['project_id'] as String? ?? '',
  projectName: json['project_name'] as String? ?? '',
  level: json['level'] as String? ?? '',
  grade: json['grade'] as String? ?? '',
  awardDate: json['award_date'] as String? ?? '',
  applicantId: json['applicant_id'] as String? ?? '',
  applicantName: json['applicant_name'] as String? ?? '',
  order: (json['order'] as num?)?.toInt() ?? 0,
  credits: (json['credits'] as num?)?.toDouble() ?? 0.0,
  bonus: (json['bonus'] as num?)?.toDouble() ?? 0.0,
  status: json['status'] as String? ?? '',
  verificationStatus: json['verification_status'] as String? ?? '',
);

Map<String, dynamic> _$AwardProjectToJson(AwardProject instance) =>
    <String, dynamic>{
      'project_id': instance.projectId,
      'project_name': instance.projectName,
      'level': instance.level,
      'grade': instance.grade,
      'award_date': instance.awardDate,
      'applicant_id': instance.applicantId,
      'applicant_name': instance.applicantName,
      'order': instance.order,
      'credits': instance.credits,
      'bonus': instance.bonus,
      'status': instance.status,
      'verification_status': instance.verificationStatus,
    };
