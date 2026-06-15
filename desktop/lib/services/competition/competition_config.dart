/// 竞赛信息系统配置类
///
/// 管理创新创业管理平台的基础URL和路径转换
class CompetitionConfig {
  /// 创新创业管理平台基础URL
  static const String defaultBaseUrl =
      'http://211-86-241-245.vpn2.aufe.edu.cn:8118';

  /// 将相对路径转换为完整URL
  ///
  /// 如果路径已经是完整URL（以http://或https://开头），则直接返回
  /// 否则将路径与基础URL拼接
  ///
  /// 示例:
  /// ```dart
  /// final config = CompetitionConfig();
  /// print(config.toFullUrl('/xsXmMain.aspx'));
  /// // 输出: http://cxcy-aufe-edu-cn.vpn2.aufe.edu.cn:8118/xsXmMain.aspx
  /// ```
  String toFullUrl(String path) {
    // 如果已经是完整URL，直接返回
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // 移除基础URL末尾的斜杠
    final baseUrl = defaultBaseUrl.replaceAll(RegExp(r'/$'), '');

    // 移除路径开头的斜杠
    final cleanPath = path.replaceAll(RegExp(r'^/'), '');

    // 拼接并返回完整URL
    return '$baseUrl/$cleanPath';
  }
}
