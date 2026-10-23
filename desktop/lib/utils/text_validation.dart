/// 登录输入的全角字符检测（与 Android TextValidation.kt 保持一致）
///
/// 中文输入法很容易混入全角数字/字母/标点/空格，而教务系统只认半角原文。
/// 只提示、不自动转换（不替用户改密码内容）。

/// 全角区间（闭区间，成对出现）
const List<int> _fullWidthRanges = [
  0x3000, 0x3000, // 全角空格
  0xFF01, 0xFF60, // 全角 ASCII 变体（！＂＃０９ＡＺａｚ等）
  0xFFE0, 0xFFE6, // 全角货币/符号（￠￡￥等）
];

List<String> _findFullWidthChars(String text) {
  final result = <String>[];
  for (final unit in text.codeUnits) {
    for (var i = 0; i < _fullWidthRanges.length; i += 2) {
      if (unit >= _fullWidthRanges[i] && unit <= _fullWidthRanges[i + 1]) {
        result.add(String.fromCharCode(unit));
        break;
      }
    }
  }
  return result;
}

/// 文本是否包含全角字符
bool hasFullWidthChars(String text) => _findFullWidthChars(text).isNotEmpty;

/// 错误提示里展示前几个全角字符（全角空格显示成 ␣ 才看得见）
String describeFullWidthChars(String text) => _findFullWidthChars(text)
    .take(3)
    .map((c) => c == '\u3000' ? '␣' : "'$c'")
    .join(' ');
