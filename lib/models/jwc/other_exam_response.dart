import 'package:json_annotation/json_annotation.dart';
import 'other_exam_record.dart';

part 'other_exam_response.g.dart';

/// 其他考试响应模型（中间模型）
///
/// 用于解析其他考试 API 的分页响应
@JsonSerializable()
class OtherExamResponse {
  @JsonKey(name: 'pageSize')
  final int pageSize;

  @JsonKey(name: 'pageNum')
  final int pageNum;

  @JsonKey(name: 'pageContext')
  final Map<String, int> pageContext;

  @JsonKey(name: 'records')
  final List<OtherExamRecord>? records;

  OtherExamResponse({
    required this.pageSize,
    required this.pageNum,
    required this.pageContext,
    this.records,
  });

  factory OtherExamResponse.fromJson(Map<String, dynamic> json) =>
      _$OtherExamResponseFromJson(json);

  Map<String, dynamic> toJson() => _$OtherExamResponseToJson(this);
}
