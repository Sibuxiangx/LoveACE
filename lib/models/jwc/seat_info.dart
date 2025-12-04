import 'package:json_annotation/json_annotation.dart';

part 'seat_info.g.dart';

/// 座位信息模型（中间模型）
///
/// 用于存储从 HTML 解析出的座位信息
@JsonSerializable()
class SeatInfo {
  @JsonKey(name: 'course_name')
  final String courseName; // 课程名称

  @JsonKey(name: 'seat_number')
  final String seatNumber; // 座位号

  SeatInfo({
    required this.courseName,
    required this.seatNumber,
  });

  factory SeatInfo.fromJson(Map<String, dynamic> json) =>
      _$SeatInfoFromJson(json);

  Map<String, dynamic> toJson() => _$SeatInfoToJson(this);
}
