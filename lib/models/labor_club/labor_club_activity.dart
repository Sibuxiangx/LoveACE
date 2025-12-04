import 'package:json_annotation/json_annotation.dart';
import 'sign_item.dart';

part 'labor_club_activity.g.dart';

/// 字符串转布尔值的转换器（处理 "0"/"1" 或 null）
class StringToBoolConverter implements JsonConverter<bool?, dynamic> {
  const StringToBoolConverter();

  @override
  bool? fromJson(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      if (value == "1" || value.toLowerCase() == "true") return true;
      if (value == "0" || value.toLowerCase() == "false") return false;
      return null;
    }
    if (value is int) return value != 0;
    return null;
  }

  @override
  dynamic toJson(bool? value) => value;
}

/// 劳动俱乐部活动
///
/// 包含活动的所有基本信息
@JsonSerializable()
class LaborClubActivity {
  /// 活动ID
  @JsonKey(name: 'ID')
  final String id;

  /// 活动图标
  @JsonKey(name: 'Ico')
  final String? ico;

  /// 活动状态
  @JsonKey(name: 'State')
  final int state;

  /// 活动状态名称
  @JsonKey(name: 'StateName')
  final String stateName;

  /// 活动类型ID
  @JsonKey(name: 'TypeID')
  final String typeId;

  /// 活动类型名称
  @JsonKey(name: 'TypeName')
  final String typeName;

  /// 活动标题
  @JsonKey(name: 'Title')
  final String title;

  /// 开始时间
  @JsonKey(name: 'StartTime')
  final String startTime;

  /// 结束时间
  @JsonKey(name: 'EndTime')
  final String endTime;

  /// 负责人工号
  @JsonKey(name: 'ChargeUserNo')
  final String chargeUserNo;

  /// 负责人姓名
  @JsonKey(name: 'ChargeUserName')
  final String chargeUserName;

  /// 俱乐部ID
  @JsonKey(name: 'ClubID')
  final String clubId;

  /// 俱乐部名称
  @JsonKey(name: 'ClubName')
  final String clubName;

  /// 已报名人数
  @JsonKey(name: 'MemberNum')
  final int memberNum;

  /// 添加时间
  @JsonKey(name: 'AddTime')
  final String addTime;

  /// 人数限制
  @JsonKey(name: 'PeopleNum')
  final int peopleNum;

  /// 最小人数
  @JsonKey(name: 'PeopleNumMin')
  final int? peopleNumMin;

  /// 是否已加入
  @JsonKey(name: 'IsJson')
  @StringToBoolConverter()
  final bool? isJoined;

  /// 是否已关闭
  @JsonKey(name: 'IsClose')
  @StringToBoolConverter()
  final bool? isClosed;

  /// 报名开始时间
  @JsonKey(name: 'SignUpStartTime')
  final String signUpStartTime;

  /// 报名结束时间
  @JsonKey(name: 'SignUpEndTime')
  final String signUpEndTime;

  /// 签到列表（运行时添加，不从JSON解析）
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<SignItem>? signList;

  LaborClubActivity({
    this.id = '',
    this.ico,
    this.state = 0,
    this.stateName = '',
    this.typeId = '',
    this.typeName = '',
    this.title = '',
    this.startTime = '',
    this.endTime = '',
    this.chargeUserNo = '',
    this.chargeUserName = '',
    this.clubId = '',
    this.clubName = '',
    this.memberNum = 0,
    this.addTime = '',
    this.peopleNum = 0,
    this.peopleNumMin,
    this.isJoined,
    this.isClosed,
    this.signUpStartTime = '',
    this.signUpEndTime = '',
    this.signList,
  });

  /// 是否可以报名
  bool get canApply {
    if (isClosed == true || isJoined == true) return false;
    if (memberNum >= peopleNum) return false;
    return true;
  }

  /// 报名状态文本
  String get applyStatusText {
    if (isJoined == true) return '已加入';
    if (isClosed == true) return '已关闭';
    if (memberNum >= peopleNum) return '已满员';
    return '可报名';
  }

  /// 获取签到状态摘要
  String get signInStatus {
    if (signList == null || signList!.isEmpty) return '默认签到';

    final signedCount = signList!.where((s) => s.isSign).length;
    final totalCount = signList!.length;

    // 如果只有一条签到记录，使用 emoji 状态
    if (totalCount == 1) {
      final signItem = signList!.first;
      if (signItem.isSign) {
        return '😋 已签到';
      } else {
        // 检查是否过期
        try {
          final endTime = DateTime.parse(signItem.endTime);
          if (DateTime.now().isAfter(endTime)) {
            return '😭 未签到';
          } else {
            return '🤔 待签到';
          }
        } catch (e) {
          return '🤔 待签到';
        }
      }
    }

    // 多条签到记录时显示数量
    if (signedCount == totalCount) return '已完成 ($signedCount/$totalCount)';
    if (signedCount > 0) return '部分签到 ($signedCount/$totalCount)';
    return '未签到 (0/$totalCount)';
  }

  /// 是否已完成所有签到
  bool get isAllSigned {
    if (signList == null || signList!.isEmpty) return true;
    return signList!.every((s) => s.isSign);
  }

  factory LaborClubActivity.fromJson(Map<String, dynamic> json) =>
      _$LaborClubActivityFromJson(json);

  Map<String, dynamic> toJson() => _$LaborClubActivityToJson(this);
}
