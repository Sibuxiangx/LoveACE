import 'package:json_annotation/json_annotation.dart';

part 'transaction_record.g.dart';

/// 一卡通消费记录
///
/// 包含单条消费/充值记录的详细信息
@JsonSerializable()
class TransactionRecord {
  /// 记账时间
  final String accountingTime;

  /// 消费时间
  final String transactionTime;

  /// 出账金额（消费）
  final double? expense;

  /// 入账金额（充值）
  final double? income;

  /// 操作类型（如：消费、充值等）
  final String operationType;

  /// 余额
  final double balance;

  /// 消费区域
  final String area;

  /// 终端号
  final String terminalId;

  TransactionRecord({
    required this.accountingTime,
    required this.transactionTime,
    this.expense,
    this.income,
    required this.operationType,
    required this.balance,
    required this.area,
    required this.terminalId,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) =>
      _$TransactionRecordFromJson(json);

  Map<String, dynamic> toJson() => _$TransactionRecordToJson(this);

  /// 是否为消费记录
  bool get isExpense => expense != null && expense! > 0;

  /// 是否为充值记录
  bool get isIncome => income != null && income! > 0;

  /// 获取金额（正数为入账，负数为出账）
  double get amount => isIncome ? income! : -(expense ?? 0);

  /// 获取金额显示文本
  String get amountText {
    if (isIncome) {
      return '+${income!.toStringAsFixed(2)}元';
    } else if (isExpense) {
      return '-${expense!.toStringAsFixed(2)}元';
    }
    return '0.00元';
  }
}

/// 消费记录查询结果
@JsonSerializable()
class TransactionQueryResult {
  /// 消费记录列表
  final List<TransactionRecord> records;

  /// 查询起始日期
  final String startDate;

  /// 查询终止日期
  final String endDate;

  TransactionQueryResult({
    required this.records,
    required this.startDate,
    required this.endDate,
  });

  factory TransactionQueryResult.fromJson(Map<String, dynamic> json) =>
      _$TransactionQueryResultFromJson(json);

  Map<String, dynamic> toJson() => _$TransactionQueryResultToJson(this);

  /// 总消费金额
  double get totalExpense =>
      records.fold(0.0, (sum, r) => sum + (r.expense ?? 0));

  /// 总充值金额
  double get totalIncome =>
      records.fold(0.0, (sum, r) => sum + (r.income ?? 0));

  /// 记录数量
  int get count => records.length;

  /// 从HTML响应中解析消费记录
  ///
  /// HTML格式示例：
  /// ```html
  /// <table>
  ///   <tr><th>记账时间</th><th>消费时间</th>...</tr>
  ///   <tr><td>2025-12-15</td><td>2025-12-15 12:00</td>...</tr>
  /// </table>
  /// ```
  factory TransactionQueryResult.fromHtml(
    String html,
    String startDate,
    String endDate,
  ) {
    final records = <TransactionRecord>[];

    // 匹配表格行（跳过表头）
    // 表格结构：记账时间、消费时间、出账、入账、操作类型、余额、消费区域、终端号
    final rowRegex = RegExp(
      r'<tr>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*</tr>',
      caseSensitive: false,
      dotAll: true,
    );

    final matches = rowRegex.allMatches(html);

    for (final match in matches) {
      try {
        final accountingTime = _cleanHtmlText(match.group(1) ?? '');
        final transactionTime = _cleanHtmlText(match.group(2) ?? '');
        final expenseStr = _cleanHtmlText(match.group(3) ?? '');
        final incomeStr = _cleanHtmlText(match.group(4) ?? '');
        final operationType = _cleanHtmlText(match.group(5) ?? '');
        final balanceStr = _cleanHtmlText(match.group(6) ?? '');
        final area = _cleanHtmlText(match.group(7) ?? '');
        final terminalId = _cleanHtmlText(match.group(8) ?? '');

        // 解析金额
        final expense = _parseAmount(expenseStr);
        final income = _parseAmount(incomeStr);
        final balance = _parseAmount(balanceStr) ?? 0.0;

        records.add(TransactionRecord(
          accountingTime: accountingTime,
          transactionTime: transactionTime,
          expense: expense,
          income: income,
          operationType: operationType,
          balance: balance,
          area: area,
          terminalId: terminalId,
        ));
      } catch (e) {
        // 跳过解析失败的行
        continue;
      }
    }

    return TransactionQueryResult(
      records: records,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 清理HTML文本
  static String _cleanHtmlText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '') // 移除HTML标签
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  /// 解析金额字符串
  static double? _parseAmount(String text) {
    if (text.isEmpty) return null;
    // 移除非数字字符（保留小数点和负号）
    final cleanText = text.replaceAll(RegExp(r'[^\d.\-]'), '');
    if (cleanText.isEmpty) return null;
    return double.tryParse(cleanText);
  }
}
