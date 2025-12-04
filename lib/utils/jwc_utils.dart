/// 教务系统工具函数
///
/// 提供学期格式转换等通用工具方法
class JWCUtils {
  /// 转换学期格式
  ///
  /// 将教务系统的学期代码转换为可读的学期名称
  ///
  /// 格式规则:
  /// - xxxx-yyyy-1-1 -> xxxx-yyyy秋季学期
  /// - xxxx-yyyy-2-1 -> xxxx-yyyy春季学期
  ///
  /// 参数:
  /// - [zxjxjhh] 学期代码，如 "2025-2026-1-1"
  ///
  /// 返回:
  /// - 转换后的学期名称，如 "2025-2026秋季学期"
  /// - 如果格式不匹配，返回原值
  ///
  /// 示例:
  /// ```dart
  /// print(JWCUtils.convertTermFormat('2025-2026-1-1'));
  /// // 输出: 2025-2026秋季学期
  ///
  /// print(JWCUtils.convertTermFormat('2025-2026-2-1'));
  /// // 输出: 2025-2026春季学期
  ///
  /// print(JWCUtils.convertTermFormat('invalid'));
  /// // 输出: invalid
  /// ```
  static String convertTermFormat(String zxjxjhh) {
    try {
      final parts = zxjxjhh.split('-');
      if (parts.length >= 3) {
        final yearStart = parts[0];
        final yearEnd = parts[1];
        final semesterNum = parts[2];

        if (semesterNum == '1') {
          return '$yearStart-$yearEnd秋季学期';
        } else if (semesterNum == '2') {
          return '$yearStart-$yearEnd春季学期';
        }
      }
      return zxjxjhh; // 如果格式不匹配，返回原值
    } catch (e) {
      return zxjxjhh;
    }
  }

  // 隐私构造函数，防止实例化
  JWCUtils._();
}
