/// 爱安财系统配置类
///
/// 管理爱安财系统的基础URL和路径转换
class AACConfig {
  /// 爱安财系统API基础URL
  static const String defaultBaseUrl =
      'http://api-dekt-ac-acxk-net.vpn2.aufe.edu.cn:8118';

  /// 爱安财系统Web基础URL
  static const String webUrl = 'http://dekt-ac-acxk-net.vpn2.aufe.edu.cn:8118';

  /// 登录服务URL（用于获取ticket）
  static const String loginServiceUrl =
      'http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.dekt.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue';

  /// 将相对路径转换为完整URL
  ///
  /// 如果路径已经是完整URL（以http://或https://开头），则直接返回
  /// 否则将路径与基础URL拼接
  String toFullUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final baseUrl = defaultBaseUrl.replaceAll(RegExp(r'/$'), '');
    final cleanPath = path.replaceAll(RegExp(r'^/'), '');

    return '$baseUrl/$cleanPath';
  }
}
