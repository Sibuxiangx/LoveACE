import 'package:flutter/foundation.dart';
import '../models/aufe/login_status.dart';
import '../models/aufe/user_credentials.dart';
import '../services/analytics_service.dart';
import '../services/aufe/connector.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';
import '../services/aac/aac_ticket_manager.dart';
import '../services/labor_club/ldjlb_ticket_manager.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/text_validation.dart';

/// Authentication state enum
enum AuthState { initial, loading, authenticated, unauthenticated, error }

/// 登录失败冷却阶梯（按连续失败次数）：
/// 1 次无冷却，2 次 30 秒，3 次 120 秒，4 次及以上 600 秒
Duration loginCooldownAfterFailures(int failures) {
  if (failures <= 1) return Duration.zero;
  if (failures == 2) return const Duration(seconds: 30);
  if (failures == 3) return const Duration(seconds: 120);
  return const Duration(seconds: 600);
}

/// 登录失败计数与冷却截止时间：按学号保存在本地偏好（不含密码，不进安全存储）
class _LoginAttemptStore {
  static String _failuresKey(String userId) => 'login_failures_$userId';
  static String _cooldownUntilKey(String userId) =>
      'login_cooldown_until_$userId';

  static Future<DateTime?> loadCooldownUntil(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_cooldownUntilKey(userId));
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 记录一次失败，返回新的冷却截止时间
  static Future<DateTime> recordFailure(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final failures = (prefs.getInt(_failuresKey(userId)) ?? 0) + 1;
    final until = DateTime.now().add(loginCooldownAfterFailures(failures));
    await prefs.setInt(_failuresKey(userId), failures);
    await prefs.setInt(_cooldownUntilKey(userId), until.millisecondsSinceEpoch);
    return until;
  }

  /// 登录成功后清除失败计数与冷却
  static Future<void> reset(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failuresKey(userId));
    await prefs.remove(_cooldownUntilKey(userId));
  }
}

/// Provider for managing authentication state and user sessions
///
/// Handles login, logout, session checking, and credential management
/// Uses ChangeNotifier to notify listeners of state changes
///
/// Usage example:
/// ```dart
/// final authProvider = Provider.of<AuthProvider>(context);
///
/// // Login
/// await authProvider.login(
///   userId: '学号',
///   ecPassword: 'EC密码',
///   password: 'UAAP密码',
/// );
///
/// // Check session
/// final isValid = await authProvider.checkSession();
///
/// // Logout
/// await authProvider.logout();
/// ```
class AuthProvider extends ChangeNotifier {
  AUFEConnection? _connection;
  AuthState _state = AuthState.initial;
  String? _errorMessage;
  UserCredentials? _credentials;

  /// 学校 UAAP/CAS 强制改密拦截（不是密码错误：不清凭据、不自动重试）
  bool _passwordChangeRequired = false;

  /// 学校要求验证码时的图片（null 表示当前不需要验证码）
  Uint8List? _captchaImage;

  /// 持有待提交验证码上下文的连接（验证码流程中保留，其他结果时关闭）
  AUFEConnection? _captchaConnection;

  /// 当前学号的冷却截止时间（仅用于界面倒计时；登录时以本地偏好为准）
  DateTime? _cooldownUntil;

  /// 静默重登录因学校要求验证码而结束（凭据保留，登录页提示重新登录）
  bool _reloginCaptchaRequired = false;

  /// Get current authentication state
  AuthState get state => _state;

  /// Get current error message (if any)
  String? get errorMessage => _errorMessage;

  /// Get current connection instance
  AUFEConnection? get connection => _connection;

  /// Get current user credentials
  UserCredentials? get credentials => _credentials;

  /// 学校强制改密拦截标记（不是密码错误，不清凭据、不自动重试）
  bool get passwordChangeRequired => _passwordChangeRequired;

  /// 验证码图片（null 表示不需要验证码）
  Uint8List? get captchaImage => _captchaImage;

  /// 冷却截止时间（null 表示无冷却）
  DateTime? get cooldownUntil => _cooldownUntil;

  /// 冷却剩余秒数（向上取整，0 表示无冷却）
  int get cooldownSecondsLeft {
    final until = _cooldownUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) return 0;
    return (remaining.inMilliseconds / 1000).ceil();
  }

  /// 静默重登录因学校要求验证码而结束
  bool get reloginCaptchaRequired => _reloginCaptchaRequired;

  /// 用户确认改密提示
  void dismissPasswordChange() {
    _passwordChangeRequired = false;
    notifyListeners();
  }

  /// Check if user is authenticated
  bool get isAuthenticated => _state == AuthState.authenticated;

  /// VPN重定向回调 - 由UI层设置，用于导航回登录页面
  VoidCallback? onVpnRedirect;

  /// 是否正在进行静默重登录
  bool _isSilentRelogin = false;

  /// Login with user credentials
  ///
  /// Creates AUFEConnection and performs both EC and UAAP login
  /// Saves credentials securely on successful login
  ///
  /// [userId] - Student ID
  /// [ecPassword] - EC system password
  /// [password] - UAAP system password
  /// [captchaCode] - 学校要求验证码时用户输入的验证码；null 表示尚未进入验证码流程。
  ///   返回 false 且 [captchaImage] 非空时，界面展示验证码，用户输入后再次调用本方法。
  ///
  /// Returns true if login succeeds, false otherwise
  Future<bool> login({
    required String userId,
    required String ecPassword,
    required String password,
    String? captchaCode,
  }) {
    return _attemptLogin(
      userId: userId,
      ecPassword: ecPassword,
      password: password,
      captchaCode: captchaCode,
      countsAsUserAttempt: true,
    );
  }

  /// 登录实现
  ///
  /// [countsAsUserAttempt] 为 false（启动时自动恢复会话）时不计入失败次数
  Future<bool> _attemptLogin({
    required String userId,
    required String ecPassword,
    required String password,
    required String? captchaCode,
    required bool countsAsUserAttempt,
  }) async {
    try {
      // 冷却期内不触网
      final storedCooldown = await _LoginAttemptStore.loadCooldownUntil(userId);
      if (storedCooldown != null && storedCooldown.isAfter(DateTime.now())) {
        _cooldownUntil = storedCooldown;
        _errorMessage = '请 $cooldownSecondsLeft 秒后再试';
        LoggerService.info('⏳ 登录冷却中，未发起网络请求');
        _setState(AuthState.error);
        return false;
      }
      _cooldownUntil = null;

      // 验证码输入检查（仅验证码流程）
      final code = captchaCode?.trim();
      if (code != null && code.isEmpty) {
        _errorMessage = '请输入验证码';
        notifyListeners();
        return false;
      }
      if (code != null && hasFullWidthChars(code)) {
        _errorMessage = '验证码含全角字符 ${describeFullWidthChars(code)}，请用英文半角';
        notifyListeners();
        return false;
      }

      LoggerService.info('🔐 Starting login process...');
      LoggerService.info('🔐 User ID: $userId');

      _setState(AuthState.loading);
      _errorMessage = null;
      _passwordChangeRequired = false;
      _reloginCaptchaRequired = false;

      // 验证码流程复用同一连接（待提交的验证码上下文保存在连接内）；账号或密码变化则重建
      final pendingConnection = _captchaConnection;
      _captchaConnection = null;
      final canReuse = code != null &&
          pendingConnection != null &&
          pendingConnection.userId == userId &&
          pendingConnection.ecPassword == ecPassword &&
          pendingConnection.password == password;
      if (pendingConnection != null && !canReuse) {
        await pendingConnection.close();
      }

      // Create credentials
      final credentials = UserCredentials(
        userId: userId,
        ecPassword: ecPassword,
        password: password,
      );

      final AUFEConnection connection;
      if (canReuse) {
        connection = pendingConnection!;
      } else {
        // Create connection
        LoggerService.info('🔐 Creating AUFEConnection...');
        connection = AUFEConnection(
          userId: userId,
          ecPassword: ecPassword,
          password: password,
        );

        // Initialize HTTP client with VPN redirect handler
        LoggerService.info('🔐 Starting HTTP client...');
        connection.startClient(
          onVpnRedirect: () async {
            return await _handleVpnRedirect();
          },
        );
      }

      // Perform EC login
      LoggerService.info('🔐 Performing EC login...');
      var ecLoginStatus = await connection.ecLogin(captchaCode: code);
      var captchaInvalid = false;
      if (ecLoginStatus.captchaInvalid) {
        // 验证码错误：计一次失败，并在同一连接上立即取新图
        captchaInvalid = true;
        if (countsAsUserAttempt) await _recordLoginFailure(userId);
        ecLoginStatus = await connection.ecLogin();
      }
      LoggerService.info('🔐 EC login result: ${ecLoginStatus.success}');

      if (ecLoginStatus.captchaRequired) {
        // 需要（重新）输入验证码：保留连接以便提交，不计失败
        _captchaConnection = connection;
        _captchaImage = ecLoginStatus.captchaImage;
        _errorMessage = captchaInvalid ? '验证码错误，请重新输入' : '学校要求输入验证码';
        LoggerService.info('🖼️ EC 登录需要验证码');
        _setState(AuthState.error);
        return false;
      }

      // 其他结果均结束验证码流程
      _captchaImage = null;

      if (!ecLoginStatus.success) {
        if (ecLoginStatus.failInvalidCredentials && countsAsUserAttempt) {
          await _recordLoginFailure(userId);
        }
        _errorMessage = _getEcLoginErrorMessage(ecLoginStatus);
        LoggerService.info('❌ EC login failed: $_errorMessage');
        _setState(AuthState.error);
        await connection.close();
        AnalyticsService.instance.trackLoginFailed(userId, _errorMessage ?? 'ec_login_failed');
        return false;
      }

      // Perform UAAP login
      LoggerService.info('🔐 Performing UAAP login...');
      final uaapLoginStatus = await connection.uaapLogin();
      LoggerService.info('🔐 UAAP login result: ${uaapLoginStatus.success}');

      if (!uaapLoginStatus.success) {
        if (uaapLoginStatus.failPasswordChangeRequired) {
          // 学校强制改密：TGT 已铸出（密码正确），CAS 拒绝签发票据。
          // 不是密码错误：不清凭据、不计密码失败、不自动重试，本次会话作废
          LoggerService.warning('🏫 学校要求修改密码，停止登录流程');
          _passwordChangeRequired = true;
          _errorMessage = null;
          _setState(AuthState.error);
          await connection.close();
          AnalyticsService.instance.trackLoginFailed(userId, 'password_change_required');
          return false;
        }
        if (uaapLoginStatus.failInvalidCredentials && countsAsUserAttempt) {
          await _recordLoginFailure(userId);
        }
        _errorMessage = _getUaapLoginErrorMessage(uaapLoginStatus);
        LoggerService.info('❌ UAAP login failed: $_errorMessage');
        _setState(AuthState.error);
        await connection.close();
        AnalyticsService.instance.trackLoginFailed(userId, _errorMessage ?? 'uaap_login_failed');
        return false;
      }

      // 登录成功：清除该学号的失败计数与冷却（偏好写入失败不影响登录）
      try {
        await _LoginAttemptStore.reset(userId);
      } catch (e) {
        LoggerService.warning('⚠️ 清除登录失败计数失败: $e');
      }
      _cooldownUntil = null;

      // Save credentials securely. A storage failure must not fail the
      // whole login: the network login already succeeded, so degrade to a
      // warning (e.g. missing keyring daemon on minimal Linux desktops).
      LoggerService.info('🔐 Saving credentials...');
      try {
        await credentials.saveSecurely();
      } catch (e) {
        LoggerService.warning(
          '🔐 Failed to persist credentials, login continues: $e',
        );
      }

      // Update state
      _connection = connection;
      _credentials = credentials;
      _setState(AuthState.authenticated);

      LoggerService.info('✅ Login successful!');
      AnalyticsService.instance.trackLoginSuccess(userId);
      return true;
    } catch (e, stackTrace) {
      _errorMessage = '登录过程出错: $e';
      LoggerService.info('❌ Login error: $e');
      LoggerService.info('❌ Stack trace: $stackTrace');
      _setState(AuthState.error);
      AnalyticsService.instance.trackLoginFailed(userId, '登录异常');
      return false;
    }
  }

  /// 计一次登录失败并写入冷却截止时间（仅用户主动登录）
  Future<void> _recordLoginFailure(String userId) async {
    _cooldownUntil = await _LoginAttemptStore.recordFailure(userId);
    LoggerService.info('⏳ 登录失败已计数');
  }

  /// 点击验证码图片：在同一连接上重新获取图片（不计失败，不提交密码）
  /// 返回失败提示；成功取得新图返回 null
  Future<String?> refreshCaptcha() async {
    final connection = _captchaConnection;
    if (connection == null) return null;
    // 取用期间暂存于局部变量，避免与登录并发使用同一连接
    _captchaConnection = null;
    final status = await connection.ecLogin();
    if (status.captchaRequired) {
      _captchaConnection = connection;
      _captchaImage = status.captchaImage;
      notifyListeners();
      return null;
    }
    // 取图失败：结束验证码流程
    _captchaImage = null;
    await connection.close();
    _errorMessage = _getEcLoginErrorMessage(status);
    notifyListeners();
    return _errorMessage;
  }

  /// 清除验证码流程状态（学号变化、登出时调用）
  Future<void> clearCaptchaState() async {
    final connection = _captchaConnection;
    final hadCaptcha = connection != null || _captchaImage != null;
    _captchaConnection = null;
    _captchaImage = null;
    if (hadCaptcha) notifyListeners();
    await connection?.close();
  }

  /// 读取某学号的持久化冷却截止时间（登录页倒计时用）
  Future<void> loadCooldownFor(String userId) async {
    try {
      final until = await _LoginAttemptStore.loadCooldownUntil(userId);
      _cooldownUntil =
          (until != null && until.isAfter(DateTime.now())) ? until : null;
    } catch (e) {
      LoggerService.warning('⚠️ 读取登录冷却失败: $e');
      _cooldownUntil = null;
    }
    notifyListeners();
  }

  /// Logout and clear all session data
  ///
  /// Closes connection, clears credentials from secure storage,
  /// clears all cached data, and resets authentication state
  Future<void> logout() async {
    try {
      LoggerService.info('🚪 开始登出流程...');

      // Close connection
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
      }

      // 清除验证码流程状态
      await clearCaptchaState();

      // Clear credentials from secure storage
      await UserCredentials.clearSecurely();
      LoggerService.info('🗑️ 已清除用户凭证');

      // Clear all cached data
      await CacheManager.clear();
      LoggerService.info('🗑️ 已清除所有缓存数据');

      // Clear AAC ticket
      if (_credentials != null) {
        await AACTicketManager.deleteTicket(_credentials!.userId);
        await LDJLBTicketManager.deleteTicket(_credentials!.userId);
        LoggerService.info('🗑️ 已清除 AAC 和劳动俱乐部 ticket');
      }

      // Reset state
      _credentials = null;
      _errorMessage = null;
      _setState(AuthState.unauthenticated);

      AnalyticsService.instance.clearUser();
      AnalyticsService.instance.trackFeature('auth', 'logout');
      LoggerService.info('✅ 登出完成');
    } catch (e) {
      LoggerService.error('❌ 登出过程出错', error: e);
      // Still reset state even if cleanup fails
      _connection = null;
      _captchaImage = null;
      _captchaConnection = null;
      _credentials = null;
      _setState(AuthState.unauthenticated);
    }
  }

  /// Check if current session is still valid
  ///
  /// Performs health check on the connection
  /// If session is invalid, updates state to unauthenticated
  ///
  /// Returns true if session is valid, false otherwise
  Future<bool> checkSession() async {
    if (_connection == null || _state != AuthState.authenticated) {
      _setState(AuthState.unauthenticated);
      return false;
    }

    try {
      final isHealthy = await _connection!.healthCheck();

      if (!isHealthy) {
        _errorMessage = '会话已过期，请重新登录';
        _setState(AuthState.unauthenticated);
        return false;
      }

      return true;
    } catch (e) {
      _errorMessage = '检查会话状态失败: $e';
      _setState(AuthState.error);
      return false;
    }
  }

  /// Attempt to restore session from saved credentials
  ///
  /// Loads credentials from secure storage and attempts to login
  /// Useful for auto-login on app startup
  ///
  /// Returns true if session restored successfully, false otherwise
  Future<bool> restoreSession() async {
    try {
      _setState(AuthState.loading);

      // Load saved credentials
      final credentials = await UserCredentials.loadSecurely();
      if (credentials == null) {
        _setState(AuthState.unauthenticated);
        return false;
      }

      // Attempt login with saved credentials
      // 自动恢复会话：不计入失败次数（非用户主动登录）
      return await _attemptLogin(
        userId: credentials.userId,
        ecPassword: credentials.ecPassword,
        password: credentials.password,
        captchaCode: null,
        countsAsUserAttempt: false,
      );
    } catch (e) {
      _errorMessage = '恢复会话失败: $e';
      _setState(AuthState.unauthenticated);
      return false;
    }
  }

  /// Update authentication state and notify listeners
  void _setState(AuthState newState) {
    _state = newState;
    notifyListeners();
  }

  /// 处理VPN重定向（尝试静默重登录）
  /// 返回 true 表示静默重登录成功，false 表示失败
  Future<bool> _handleVpnRedirect() async {
    // 防止递归调用
    if (_isSilentRelogin) {
      LoggerService.warning('⚠️ 已在进行静默重登录，跳过');
      return false;
    }

    try {
      _isSilentRelogin = true;
      LoggerService.info('🔄 VPN会话过期，尝试静默重登录...');

      // 检查是否有保存的凭证
      if (_credentials == null) {
        LoggerService.warning('⚠️ 没有保存的凭证，无法静默重登录');
        await _handleSilentReloginFailed();
        return false;
      }

      // 尝试重新登录
      final success = await _performSilentRelogin();

      if (success) {
        LoggerService.info('✅ 静默重登录成功');
        AnalyticsService.instance.trackSessionReconnectSuccess();
        return true;
      } else {
        LoggerService.warning('❌ 静默重登录失败');
        AnalyticsService.instance.trackSessionReconnectFailed();
        await _handleSilentReloginFailed();
        return false;
      }
    } catch (e) {
      LoggerService.error('❌ 静默重登录异常', error: e);
      await _handleSilentReloginFailed();
      return false;
    } finally {
      _isSilentRelogin = false;
    }
  }

  /// 执行静默重登录
  Future<bool> _performSilentRelogin() async {
    if (_credentials == null || _connection == null) {
      return false;
    }

    try {
      // 执行EC登录
      LoggerService.info('🔐 静默重登录: 执行EC登录...');
      _reloginCaptchaRequired = false;
      final ecLoginStatus = await _connection!.ecLogin();
      if (ecLoginStatus.captchaRequired) {
        // 学校要求验证码：静默重连无法人工输入，停止重连（凭据保留）
        LoggerService.warning('🔐 静默重登录: 学校要求输入验证码，停止重连');
        _reloginCaptchaRequired = true;
        return false;
      }

      if (!ecLoginStatus.success) {
        LoggerService.warning('❌ 静默重登录: EC登录失败');
        return false;
      }

      // 执行UAAP登录
      LoggerService.info('🔐 静默重登录: 执行UAAP登录...');
      final uaapLoginStatus = await _connection!.uaapLogin();

      if (!uaapLoginStatus.success) {
        if (uaapLoginStatus.failPasswordChangeRequired) {
          // 学校强制改密：停止重连（再连也会被拦截），不清凭据，半成品会话作废
          LoggerService.warning('🏫 静默重登录: 学校要求修改密码，停止重连');
          await _connection?.close();
          _connection = null;
          _passwordChangeRequired = true;
          _errorMessage = null;
          _setState(AuthState.unauthenticated);
          return false;
        }
        LoggerService.warning('❌ 静默重登录: UAAP登录失败');
        return false;
      }

      LoggerService.info('✅ 静默重登录: 登录成功');
      return true;
    } catch (e) {
      LoggerService.error('❌ 静默重登录: 登录异常', error: e);
      return false;
    }
  }

  /// 处理静默重登录失败
  Future<void> _handleSilentReloginFailed() async {
    if (_passwordChangeRequired) {
      // 改密拦截：不清凭据、不登出，仅导航回登录页展示提示
      LoggerService.info('🏫 改密拦截：保留凭据，仅导航回登录页');
      onVpnRedirect?.call();
      return;
    }
    if (_reloginCaptchaRequired) {
      // 学校要求验证码：静默重连无法人工输入。保留凭据（登录页预填），结束会话，不登出
      LoggerService.info('🔐 静默重登录需要验证码：保留凭据，仅导航回登录页');
      await _connection?.close();
      _connection = null;
      _errorMessage = '学校要求输入验证码，请重新登录';
      _setState(AuthState.unauthenticated);
      onVpnRedirect?.call();
      return;
    }
    LoggerService.info('🚨 静默重登录失败，清除会话并触发导航回登录页面');

    // 清除当前会话状态
    await logout();

    // 触发UI层的导航回调
    if (onVpnRedirect != null) {
      onVpnRedirect!();
    }
  }

  /// Get user-friendly error message for EC login status
  String _getEcLoginErrorMessage(dynamic status) {
    if (status.failInvalidCredentials) {
      return 'EC系统用户名或密码错误';
    } else if (status.failNotFoundTwfid) {
      return '无法获取TwfID，请稍后重试';
    } else if (status.failNotFoundRsaKey) {
      return '无法获取RSA密钥，请稍后重试';
    } else if (status.failNotFoundRsaExp) {
      return '无法获取RSA指数，请稍后重试';
    } else if (status.failNotFoundCsrfCode) {
      return '无法获取CSRF代码，请稍后重试';
    } else if (status.failNetworkError) {
      return 'EC系统网络连接失败';
    } else {
      return 'EC系统登录失败';
    }
  }

  /// Get user-friendly error message for UAAP login status
  String _getUaapLoginErrorMessage(dynamic status) {
    if (status.failPasswordChangeRequired) {
      return passwordChangeGuidance;
    } else if (status.failInvalidCredentials) {
      return 'UAAP系统用户名或密码错误';
    } else if (status.failNotFoundLt) {
      return '无法获取lt参数，请稍后重试';
    } else if (status.failNotFoundExecution) {
      return '无法获取execution参数，请稍后重试';
    } else if (status.failNetworkError) {
      return 'UAAP系统网络连接失败';
    } else {
      return 'UAAP系统登录失败';
    }
  }

  @override
  void dispose() {
    // Close connection when provider is disposed
    _connection?.close();
    _captchaConnection?.close();
    super.dispose();
  }
}
