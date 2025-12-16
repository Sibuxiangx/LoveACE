import 'package:json_annotation/json_annotation.dart';

part 'card_balance.g.dart';

/// 一卡通余额信息
///
/// 包含校园卡当前余额
@JsonSerializable()
class CardBalance {
  /// 校园卡余额（单位：元）
  final double balance;

  /// 余额字符串（原始格式，如 "0.18元"）
  final String balanceText;

  CardBalance({
    required this.balance,
    required this.balanceText,
  });

  factory CardBalance.fromJson(Map<String, dynamic> json) =>
      _$CardBalanceFromJson(json);

  Map<String, dynamic> toJson() => _$CardBalanceToJson(this);

  /// 从HTML响应中解析余额信息
  ///
  /// HTML格式示例：
  /// ```html
  /// <div class="show">
  ///   <label>校园卡余额：</label>
  ///   <label>0.18元</label>
  /// </div>
  /// ```
  factory CardBalance.fromHtml(String html) {
    // 使用正则表达式提取余额
    // 匹配 "校园卡余额：</label><label>X.XX元" 格式
    final balanceRegex = RegExp(
      r'校园卡余额[：:]\s*</label>\s*<label>\s*([\d.]+)\s*元',
      caseSensitive: false,
    );

    final match = balanceRegex.firstMatch(html);
    if (match != null && match.groupCount >= 1) {
      final balanceStr = match.group(1)!;
      final balance = double.tryParse(balanceStr) ?? 0.0;
      return CardBalance(
        balance: balance,
        balanceText: '$balanceStr元',
      );
    }

    // 备用正则：匹配更宽松的格式
    final fallbackRegex = RegExp(
      r'余额[：:]?\s*([\d.]+)\s*元',
      caseSensitive: false,
    );

    final fallbackMatch = fallbackRegex.firstMatch(html);
    if (fallbackMatch != null && fallbackMatch.groupCount >= 1) {
      final balanceStr = fallbackMatch.group(1)!;
      final balance = double.tryParse(balanceStr) ?? 0.0;
      return CardBalance(
        balance: balance,
        balanceText: '$balanceStr元',
      );
    }

    throw Exception('无法从HTML中解析余额信息');
  }
}
