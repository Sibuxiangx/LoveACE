// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credits_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditsSummary _$CreditsSummaryFromJson(Map<String, dynamic> json) =>
    CreditsSummary(
      disciplineCompetitionCredits:
          (json['discipline_competition_credits'] as num?)?.toDouble(),
      scientificResearchCredits: (json['scientific_research_credits'] as num?)
          ?.toDouble(),
      transferableCompetitionCredits:
          (json['transferable_competition_credits'] as num?)?.toDouble(),
      innovationPracticeCredits: (json['innovation_practice_credits'] as num?)
          ?.toDouble(),
      abilityCertificationCredits:
          (json['ability_certification_credits'] as num?)?.toDouble(),
      otherProjectCredits: (json['other_project_credits'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CreditsSummaryToJson(
  CreditsSummary instance,
) => <String, dynamic>{
  'discipline_competition_credits': instance.disciplineCompetitionCredits,
  'scientific_research_credits': instance.scientificResearchCredits,
  'transferable_competition_credits': instance.transferableCompetitionCredits,
  'innovation_practice_credits': instance.innovationPracticeCredits,
  'ability_certification_credits': instance.abilityCertificationCredits,
  'other_project_credits': instance.otherProjectCredits,
};
