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

/// UAAP登录状态
class UAAPLoginStatus {
  final bool success;
  final bool failNotFoundLt;
  final bool failNotFoundExecution;
  final bool failInvalidCredentials;
  final bool failNetworkError;
  final bool failUnknownError;

  UAAPLoginStatus({
    this.success = false,
    this.failNotFoundLt = false,
    this.failNotFoundExecution = false,
    this.failInvalidCredentials = false,
    this.failNetworkError = false,
    this.failUnknownError = false,
  });

  bool get isSuccess => success;
  bool get isFailed => !success;

  String get errorMessage {
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
