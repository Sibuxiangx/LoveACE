class AUFEConnectorConstants {
  static const String serverUrl = 'https://vpn2.aufe.edu.cn';
  static const String uaapLoginUrl =
      'http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fjwcxk2.aufe.edu.cn%2Fj_spring_cas_security_check';
  static const String uaapCheckUrl =
      'http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118/';
  static const String ecCheckUrl =
      'http://txzx-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118/dzzy/list.htm';

  /// 默认超时时间（毫秒）
  static const int defaultTimeout = 60000; // 60秒
}
