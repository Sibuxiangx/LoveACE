/// 劳动俱乐部系统配置类
///
/// 管理劳动俱乐部系统的基础URL和路径转换
class LDJLBConfig {
  /// 劳动俱乐部系统API基础URL
  static const String baseUrl =
      'http://api-ldjlb-ac-acxk-net.vpn2.aufe.edu.cn:8118';

  /// 劳动俱乐部系统Web基础URL
  static const String webUrl = 'http://ldjlb-aufe-edu-cn.vpn2.aufe.edu.cn:8118';

  /// 登录服务URL（用于获取ticket）
  static const String loginServiceUrl =
      'http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.ldjlb.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue';

  /// 将相对路径转换为完整URL
  ///
  /// 如果路径已经是完整URL（以http://或https://开头），则直接返回
  /// 否则将路径与基础URL拼接
  ///
  /// 示例:
  /// ```dart
  /// final config = LDJLBConfig();
  /// print(config.toFullUrl('/User/Center/DoGetScoreInfo'));
  /// // 输出: http://ldjlb-aufe-edu-cn.vpn2.aufe.edu.cn:8118/User/Center/DoGetScoreInfo
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
    final cleanBaseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');

    // 移除路径开头的斜杠
    final cleanPath = path.replaceAll(RegExp(r'^/'), '');

    // 拼接并返回完整URL
    return '$cleanBaseUrl/$cleanPath';
  }
}
