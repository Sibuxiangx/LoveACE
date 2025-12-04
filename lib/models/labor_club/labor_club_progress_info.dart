import 'package:json_annotation/json_annotation.dart';

part 'labor_club_progress_info.g.dart';

/// 劳动俱乐部进度信息
///
/// 包含总分和进度百分比
@JsonSerializable()
class LaborClubProgressInfo {
  /// 总分
  @JsonKey(name: 'SumScore')
  final double sumScore;

  /// 进度百分比
  @JsonKey(name: 'Progress')
  final num progress;

  LaborClubProgressInfo({required this.sumScore, required this.progress});

  /// 进度百分比（转换为 double）
  double get progressPercentage => progress.toDouble();

  /// 已完成活动数量（基于进度百分比估算，每次活动10%）
  int get finishCount => (progress / 10).floor();

  /// 是否已达标
  bool get isCompleted => progress >= 100;

  factory LaborClubProgressInfo.fromJson(Map<String, dynamic> json) =>
      _$LaborClubProgressInfoFromJson(json);

  Map<String, dynamic> toJson() => _$LaborClubProgressInfoToJson(this);
}
