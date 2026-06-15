import 'package:json_annotation/json_annotation.dart';
import 'score_record.dart';

part 'term_score_response.g.dart';

/// 学期成绩响应
///
/// 包含总记录数和成绩记录列表
@JsonSerializable()
class TermScoreResponse {
  /// 总记录数
  @JsonKey(name: 'total_count')
  final int totalCount;

  /// 成绩记录列表
  @JsonKey(name: 'records')
  final List<ScoreRecord> records;

  TermScoreResponse({required this.totalCount, required this.records});

  factory TermScoreResponse.fromJson(Map<String, dynamic> json) =>
      _$TermScoreResponseFromJson(json);

  Map<String, dynamic> toJson() => _$TermScoreResponseToJson(this);
}
