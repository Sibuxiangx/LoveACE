/// EC登录状态
class ECLoginStatus {
  final bool success;
  final bool failNotFoundTwfid;
  final bool failNotFoundRsaKey;
  final bool failNotFoundRsaExp;
  final bool failNotFoundCsrfCode;
  final bool failInvalidCredentials;
  final bool failMaybeAttacked;
  final bool failNetworkError;
  final bool failUnknownError;

  ECLoginStatus({
    this.success = false,
    this.failNotFoundTwfid = false,
    this.failNotFoundRsaKey = false,
    this.failNotFoundRsaExp = false,
    this.failNotFoundCsrfCode = false,
    this.failInvalidCredentials = false,
    this.failMaybeAttacked = false,
    this.failNetworkError = false,
    this.failUnknownError = false,
  });

  bool get isSuccess => success;
  bool get isFailed => !success;

  String get errorMessage {
    if (failNotFoundTwfid) return '未找到TwfID';
    if (failNotFoundRsaKey) return '未找到RSA密钥';
    if (failNotFoundRsaExp) return '未找到RSA指数';
    if (failNotFoundCsrfCode) return '未找到CSRF代码';
    if (failInvalidCredentials) return '用户名或密码错误';
    if (failMaybeAttacked) return '可能受到攻击或需要验证码';
    if (failNetworkError) return '网络连接错误';
    if (failUnknownError) return '未知错误';
    return '';
  }
}

/// 学校 UAAP/CAS 强制改密拦截：凭据校验通过（CAS 已铸出 TGT），但不再签发票据，
/// 而是把请求 302 重定向到改密页面（路径含 /mng/acp/completeInfo/password）。
/// 这不是密码错误：调用方不得清除本地凭据、不得计入密码失败次数、不得自动重试。
class PasswordChangeRequiredException implements Exception {
  @override
  String toString() => 'PasswordChangeRequiredException: 学校要求修改密码';
}

/// 改密拦截的通用指引文案
const String passwordChangeGuidance =
    '学校要求修改密码：请用浏览器登录学校教务系统完成密码修改，然后用新密码重新登录';

/// UAAP登录状态
class UAAPLoginStatus {
  final bool success;
  final bool failNotFoundLt;
  final bool failNotFoundExecution;
  final bool failInvalidCredentials;
  final bool failPasswordChangeRequired;
  final bool failNetworkError;
  final bool failUnknownError;

  UAAPLoginStatus({
    this.success = false,
    this.failNotFoundLt = false,
    this.failNotFoundExecution = false,
    this.failInvalidCredentials = false,
    this.failPasswordChangeRequired = false,
    this.failNetworkError = false,
    this.failUnknownError = false,
  });

  bool get isSuccess => success;
  bool get isFailed => !success;

  String get errorMessage {
    if (failPasswordChangeRequired) return '学校要求修改密码';
    if (failNotFoundLt) return '未找到lt参数';
    if (failNotFoundExecution) return '未找到execution参数';
    if (failInvalidCredentials) return '用户名或密码错误';
    if (failNetworkError) return '网络连接错误';
    if (failUnknownError) return '未知错误';
    return '';
  }
}

/// EC检查状态
class ECCheckStatus {
  final bool loggedIn;
  final bool failNetworkError;
  final bool failUnknownError;

  ECCheckStatus({
    this.loggedIn = false,
    this.failNetworkError = false,
    this.failUnknownError = false,
  });

  bool get isLoggedIn => loggedIn;
}
