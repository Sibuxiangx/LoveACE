import 'package:json_annotation/json_annotation.dart';
import 'sign_item.dart';

part 'activity_detail.g.dart';

/// 活动详情
///
/// 包含活动的详细信息，包括表单数据、审批流程和教师列表
@JsonSerializable()
class ActivityDetail {
  /// 活动ID
  @JsonKey(name: 'ID')
  final String id;

  /// 活动标题
  @JsonKey(name: 'Title')
  final String title;

  /// 开始时间
  @JsonKey(name: 'StartTime')
  final String startTime;

  /// 结束时间
  @JsonKey(name: 'EndTime')
  final String endTime;

  /// 负责人姓名
  @JsonKey(name: 'ChargeUserName')
  final String chargeUserName;

  /// 俱乐部名称
  @JsonKey(name: 'ClubName')
  final String clubName;

  /// 已报名人数
  @JsonKey(name: 'MemberNum')
  final int memberNum;

  /// 人数限制
  @JsonKey(name: 'PeopleNum')
  final int peopleNum;

  /// 表单数据（可能为 null）
  @JsonKey(name: 'formData', defaultValue: [])
  final List<FormField> formData;

  /// 审批流程数据（可能为 null）
  @JsonKey(name: 'flowData', defaultValue: [])
  final List<FlowData> flowData;

  /// 教师列表（可能为 null）
  @JsonKey(name: 'teacherList', defaultValue: [])
  final List<Teacher> teacherList;

  /// 签到记录列表（可能为 null）
  @JsonKey(name: 'SignList', defaultValue: [])
  final List<SignItem> signList;

  /// 报名开始时间
  @JsonKey(name: 'SignUpStartTime')
  final String? signUpStartTime;

  /// 报名结束时间
  @JsonKey(name: 'SignUpEndTime')
  final String? signUpEndTime;

  ActivityDetail({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.chargeUserName,
    required this.clubName,
    required this.memberNum,
    required this.peopleNum,
    required this.formData,
    required this.flowData,
    required this.teacherList,
    required this.signList,
    this.signUpStartTime,
    this.signUpEndTime,
  });

  /// 从表单数据中提取地点（支持多种字段名）
  String get location {
    if (formData.isEmpty) {
      return '';
    }

    try {
      // 查找活动地址字段
      for (var field in formData) {
        if (field.name == '活动地址' ||
            field.name == 'Location' ||
            field.name == '地点' ||
            field.name == '活动地点') {
          return field.value;
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /// 从表单数据中提取地点（旧版本，使用 firstWhere）
  String get locationOld {
    try {
      final locationField = formData.firstWhere(
        (field) =>
            field.name == '活动地址' ||
            field.name == 'Location' ||
            field.name == '地点' ||
            field.name == '活动地点',
        orElse: () => FormField(name: '', value: ''),
      );
      return locationField.value;
    } catch (e) {
      return '';
    }
  }

  /// 获取签到状态摘要
  String get signInStatus {
    if (signList.isEmpty) return '默认签到';

    final signedCount = signList.where((s) => s.isSign).length;
    final totalCount = signList.length;

    // 如果只有一条签到记录，使用 emoji 状态
    if (totalCount == 1) {
      final signItem = signList.first;
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
    if (signedCount == totalCount) return '已完成签到 ($signedCount/$totalCount)';
    if (signedCount > 0) return '部分签到 ($signedCount/$totalCount)';
    return '未签到 (0/$totalCount)';
  }

  /// 是否已完成所有签到
  bool get isAllSigned {
    if (signList.isEmpty) return true; // 默认签到视为已完成
    return signList.every((s) => s.isSign);
  }

  factory ActivityDetail.fromJson(Map<String, dynamic> json) =>
      _$ActivityDetailFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityDetailToJson(this);
}

/// 表单字段
@JsonSerializable()
class FormField {
  /// 字段ID
  @JsonKey(name: 'ID')
  final String id;

  /// 字段名称
  @JsonKey(name: 'Name')
  final String name;

  /// 是否必填
  @JsonKey(name: 'IsMust')
  final bool isMust;

  /// 字段类型
  @JsonKey(name: 'FieldType')
  final int fieldType;

  /// 字段值
  @JsonKey(name: 'Value')
  final String value;

  FormField({
    this.id = '',
    required this.name,
    this.isMust = false,
    this.fieldType = 1,
    required this.value,
  });

  factory FormField.fromJson(Map<String, dynamic> json) =>
      _$FormFieldFromJson(json);

  Map<String, dynamic> toJson() => _$FormFieldToJson(this);
}

/// 审批流程数据
@JsonSerializable()
class FlowData {
  /// 审批节点名称
  @JsonKey(name: 'FlowTypeName')
  final String nodeName;

  /// 审批人姓名
  @JsonKey(name: 'ExamUserName')
  final String userName;

  /// 是否通过
  @JsonKey(name: 'IsAdopt')
  final bool? isAdopt;

  /// 审批时间
  @JsonKey(name: 'ExamTime')
  final String time;

  FlowData({
    required this.nodeName,
    required this.userName,
    this.isAdopt,
    required this.time,
  });

  factory FlowData.fromJson(Map<String, dynamic> json) =>
      _$FlowDataFromJson(json);

  Map<String, dynamic> toJson() => _$FlowDataToJson(this);
}

/// 教师信息
@JsonSerializable()
class Teacher {
  /// 教师姓名
  @JsonKey(name: 'UserName')
  final String name;

  /// 教师工号
  @JsonKey(name: 'UserNo')
  final String userNo;

  Teacher({required this.name, this.userNo = ''});

  factory Teacher.fromJson(Map<String, dynamic> json) =>
      _$TeacherFromJson(json);

  Map<String, dynamic> toJson() => _$TeacherToJson(this);
}
