import 'package:json_annotation/json_annotation.dart';

part 'utility_models.g.dart';

/// 选项项（校区/楼栋/楼层/房间）
@JsonSerializable()
class SelectOption {
  /// 选项值（ID）
  final String value;

  /// 选项名称
  final String name;

  SelectOption({
    required this.value,
    required this.name,
  });

  factory SelectOption.fromJson(Map<String, dynamic> json) =>
      _$SelectOptionFromJson(json);

  Map<String, dynamic> toJson() => _$SelectOptionToJson(this);

  /// 从字符串解析（格式：value,name）
  factory SelectOption.fromString(String str) {
    final parts = str.split(',');
    if (parts.length >= 2) {
      return SelectOption(
        value: parts[0].trim(),
        name: parts[1].trim(),
      );
    }
    throw Exception('无效的选项格式: $str');
  }

  /// 从响应字符串解析选项列表（格式：value,name|value,name|...）
  static List<SelectOption> parseList(String response) {
    if (response.isEmpty) return [];

    final options = <SelectOption>[];
    final items = response.split('|');

    for (final item in items) {
      if (item.trim().isEmpty) continue;
      try {
        options.add(SelectOption.fromString(item));
      } catch (e) {
        // 跳过无效项
        continue;
      }
    }

    return options;
  }

  @override
  String toString() => '$name ($value)';
}

/// 学生信息
@JsonSerializable()
class StudentInfo {
  /// 学号
  final String studentId;

  /// 姓名
  final String name;

  /// 账户状态
  final String accountStatus;

  /// 卡状态
  final String cardStatus;

  /// 校园卡余额
  final double balance;

  /// 账户ID（用于充值）
  final String accId;

  StudentInfo({
    required this.studentId,
    required this.name,
    required this.accountStatus,
    required this.cardStatus,
    required this.balance,
    required this.accId,
  });

  factory StudentInfo.fromJson(Map<String, dynamic> json) =>
      _$StudentInfoFromJson(json);

  Map<String, dynamic> toJson() => _$StudentInfoToJson(this);

  /// 从HTML解析学生信息
  factory StudentInfo.fromHtml(String html) {
    // 解析学号
    final studentIdMatch =
        RegExp(r'编号</label>\s*<label>(\d+)</label>').firstMatch(html);
    final studentId = studentIdMatch?.group(1) ?? '';

    // 解析姓名
    final nameMatch =
        RegExp(r'姓名</label>\s*<label>([^<]+)</label>').firstMatch(html);
    final name = nameMatch?.group(1)?.trim() ?? '';

    // 解析账户状态
    final accountStatusMatch =
        RegExp(r'账户状态</label>\s*<label>([^<]+)</label>').firstMatch(html);
    final accountStatus = accountStatusMatch?.group(1)?.trim() ?? '';

    // 解析卡状态
    final cardStatusMatch =
        RegExp(r'卡状态</label>\s*<label>([^<]+)</label>').firstMatch(html);
    final cardStatus = cardStatusMatch?.group(1)?.trim() ?? '';

    // 解析余额
    final balanceMatch =
        RegExp(r'校园余额</label>\s*<label>([\d.]+)</label>').firstMatch(html);
    final balance = double.tryParse(balanceMatch?.group(1) ?? '0') ?? 0.0;

    // 解析账户ID
    final accIdMatch = RegExp(r'name="accId"\s+value\s*=\s*"(\d+)"').firstMatch(html);
    final accId = accIdMatch?.group(1) ?? '';

    return StudentInfo(
      studentId: studentId,
      name: name,
      accountStatus: accountStatus,
      cardStatus: cardStatus,
      balance: balance,
      accId: accId,
    );
  }
}

/// 房间选择信息
@JsonSerializable()
class RoomSelection {
  /// 校区ID
  final String dormId;

  /// 校区名称
  final String dormName;

  /// 楼栋名称
  final String buildingName;

  /// 楼层名称
  final String floorName;

  /// 房间ID
  final String roomId;

  /// 房间名称
  final String roomName;

  RoomSelection({
    required this.dormId,
    required this.dormName,
    required this.buildingName,
    required this.floorName,
    required this.roomId,
    required this.roomName,
  });

  factory RoomSelection.fromJson(Map<String, dynamic> json) =>
      _$RoomSelectionFromJson(json);

  Map<String, dynamic> toJson() => _$RoomSelectionToJson(this);

  @override
  String toString() => '$dormName $buildingName $floorName $roomName';
}

/// 电费充值请求
@JsonSerializable()
class UtilityPaymentRequest {
  /// 房间ID
  final String roomId;

  /// 校区ID
  final String dormId;

  /// 校区名称
  final String dormName;

  /// 楼栋名称
  final String buildName;

  /// 楼层名称
  final String floorName;

  /// 房间名称
  final String roomName;

  /// 账户ID
  final String accId;

  /// 余额
  final String balances;

  /// 支付类型（固定为2）
  final String payType;

  /// 选择的支付方式（1=校园卡，2=银行卡）
  final String choosePayType;

  /// 充值金额（整数元）
  final int money;

  UtilityPaymentRequest({
    required this.roomId,
    required this.dormId,
    required this.dormName,
    required this.buildName,
    required this.floorName,
    required this.roomName,
    required this.accId,
    required this.balances,
    this.payType = '2',
    this.choosePayType = '1',
    required this.money,
  });

  factory UtilityPaymentRequest.fromJson(Map<String, dynamic> json) =>
      _$UtilityPaymentRequestFromJson(json);

  Map<String, dynamic> toJson() => _$UtilityPaymentRequestToJson(this);

  /// 转换为表单数据
  Map<String, dynamic> toFormData() => {
        'roomId': roomId,
        'dormId': dormId,
        'dormName': dormName,
        'buildName': buildName,
        'floorName': floorName,
        'roomName': roomName,
        'accId': accId,
        'balances': balances,
        'payType': payType,
        'choosePayType': choosePayType,
        'money': money.toString(),
      };
}

/// 电费充值结果
@JsonSerializable()
class UtilityPaymentResult {
  /// 是否成功
  final bool success;

  /// 消息
  final String message;

  UtilityPaymentResult({
    required this.success,
    required this.message,
  });

  factory UtilityPaymentResult.fromJson(Map<String, dynamic> json) =>
      _$UtilityPaymentResultFromJson(json);

  Map<String, dynamic> toJson() => _$UtilityPaymentResultToJson(this);

  /// 从HTML解析结果
  factory UtilityPaymentResult.fromHtml(String html) {
    // 检查是否有消息
    final messageMatch =
        RegExp(r'id="message"[^>]*value\s*=\s*"([^"]*)"').firstMatch(html);
    final message = messageMatch?.group(1) ?? '';

    // 判断是否成功：消息包含"成功"关键字
    if (message.contains('成功')) {
      return UtilityPaymentResult(
        success: true,
        message: message,
      );
    }

    // 消息不为空但不包含成功，视为失败
    if (message.isNotEmpty) {
      return UtilityPaymentResult(
        success: false,
        message: message,
      );
    }

    // 检查HTML内容是否包含成功标识
    if (html.contains('缴费成功') || html.contains('充值成功')) {
      return UtilityPaymentResult(
        success: true,
        message: '充值成功',
      );
    }

    return UtilityPaymentResult(
      success: false,
      message: '未知结果',
    );
  }
}


/// 购电记录
@JsonSerializable()
class ElectricPurchaseRecord {
  /// 姓名
  final String name;

  /// 编号（学号）
  final String studentId;

  /// 购电区域
  final String area;

  /// 房间信息
  final String roomInfo;

  /// 购电金额
  final double amount;

  /// 购电日期
  final String purchaseDate;

  /// 营业部门
  final String department;

  ElectricPurchaseRecord({
    required this.name,
    required this.studentId,
    required this.area,
    required this.roomInfo,
    required this.amount,
    required this.purchaseDate,
    required this.department,
  });

  factory ElectricPurchaseRecord.fromJson(Map<String, dynamic> json) =>
      _$ElectricPurchaseRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ElectricPurchaseRecordToJson(this);
}

/// 购电记录查询结果
@JsonSerializable()
class ElectricPurchaseQueryResult {
  /// 查询起始日期
  final String startDate;

  /// 查询结束日期
  final String endDate;

  /// 购电记录列表
  final List<ElectricPurchaseRecord> records;

  ElectricPurchaseQueryResult({
    required this.startDate,
    required this.endDate,
    required this.records,
  });

  factory ElectricPurchaseQueryResult.fromJson(Map<String, dynamic> json) =>
      _$ElectricPurchaseQueryResultFromJson(json);

  Map<String, dynamic> toJson() => _$ElectricPurchaseQueryResultToJson(this);

  /// 记录数量
  int get count => records.length;

  /// 总购电金额
  double get totalAmount =>
      records.fold(0.0, (sum, record) => sum + record.amount);

  /// 从HTML解析购电记录
  factory ElectricPurchaseQueryResult.fromHtml(
    String html,
    String startDate,
    String endDate,
  ) {
    final records = <ElectricPurchaseRecord>[];

    // 解析表格行
    final rowRegex = RegExp(r'<tr>\s*<td>([^<]*)</td>\s*<td>([^<]*)</td>\s*<td>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td>([^<]*)</td>\s*</tr>', caseSensitive: false);
    final matches = rowRegex.allMatches(html);

    for (final match in matches) {
      final name = match.group(1)?.trim() ?? '';
      final studentId = match.group(2)?.trim() ?? '';
      final area = match.group(3)?.trim() ?? '';
      final roomInfo = match.group(4)?.trim() ?? '';
      final amountStr = match.group(5)?.trim() ?? '0';
      final purchaseDate = match.group(6)?.trim() ?? '';
      final department = match.group(7)?.trim() ?? '';

      // 跳过表头行
      if (name == '姓名' || name.isEmpty) continue;

      final amount = double.tryParse(amountStr) ?? 0.0;

      records.add(ElectricPurchaseRecord(
        name: name,
        studentId: studentId,
        area: area,
        roomInfo: roomInfo,
        amount: amount,
        purchaseDate: purchaseDate,
        department: department,
      ));
    }

    return ElectricPurchaseQueryResult(
      startDate: startDate,
      endDate: endDate,
      records: records,
    );
  }
}
