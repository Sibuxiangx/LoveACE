/// ISIM (Integrated Student Information Management) 系统配置类
///
/// 管理ISIM系统的基础URL和路径转换
/// ISIM系统用于查询宿舍电费信息
class ISIMConfig {
  /// ISIM系统默认基础URL
  /// 通过VPN访问校内后勤管理系统
  static const String defaultBaseUrl =
      'http://hqkd-aufe-edu-cn.vpn2.aufe.edu.cn';

  /// API端点映射
  ///
  /// - init: 初始化JSESSION的端点
  /// - usageRecord: 获取用电记录的端点
  /// - paymentRecord: 获取充值记录的端点
  static const Map<String, String> endpoints = {
    'init': '/go',
    'usageRecord': '/use/record',
    'paymentRecord': '/pay/record',
  };

  /// 将相对路径转换为完整URL
  ///
  /// 如果路径已经是完整URL（以http://或https://开头），则直接返回
  /// 否则将路径与基础URL拼接
  ///
  /// 示例:
  /// ```dart
  /// final config = ISIMConfig();
  /// print(config.toFullUrl('/go'));
  /// // 输出: http://isim-aufe-edu-cn.vpn2.aufe.edu.cn:8118/go
  ///
  /// print(config.toFullUrl('http://example.com/api'));
  /// // 输出: http://example.com/api
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
