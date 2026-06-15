import 'package:flutter/foundation.dart';
import '../models/aufe/user_credentials.dart';
import '../services/aufe/connector.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';
import '../services/aac/aac_ticket_manager.dart';
import '../services/labor_club/ldjlb_ticket_manager.dart';

/// Authentication state enum
enum AuthState { initial, loading, authenticated, unauthenticated, error }

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

  /// Get current authentication state
  AuthState get state => _state;

  /// Get current error message (if any)
  String? get errorMessage => _errorMessage;

  /// Get current connection instance
  AUFEConnection? get connection => _connection;

  /// Get current user credentials
  UserCredentials? get credentials => _credentials;

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
  ///
  /// Returns true if login succeeds, false otherwise
  Future<bool> login({
    required String userId,
    required String ecPassword,
    required String password,
  }) async {
    try {
      LoggerService.info('🔐 Starting login process...');
      LoggerService.info('🔐 User ID: $userId');

      _setState(AuthState.loading);
      _errorMessage = null;

      // Create credentials
      final credentials = UserCredentials(
        userId: userId,
        ecPassword: ecPassword,
        password: password,
      );

      // Create connection
      LoggerService.info('🔐 Creating AUFEConnection...');
      final connection = AUFEConnection(
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

      // Perform EC login
      LoggerService.info('🔐 Performing EC login...');
      final ecLoginStatus = await connection.ecLogin();
      LoggerService.info('🔐 EC login result: ${ecLoginStatus.success}');

      if (!ecLoginStatus.success) {
        _errorMessage = _getEcLoginErrorMessage(ecLoginStatus);
        LoggerService.info('❌ EC login failed: $_errorMessage');
        _setState(AuthState.error);
        await connection.close();
        return false;
      }

      // Perform UAAP login
      LoggerService.info('🔐 Performing UAAP login...');
      final uaapLoginStatus = await connection.uaapLogin();
      LoggerService.info('🔐 UAAP login result: ${uaapLoginStatus.success}');

      if (!uaapLoginStatus.success) {
        _errorMessage = _getUaapLoginErrorMessage(uaapLoginStatus);
        LoggerService.info('❌ UAAP login failed: $_errorMessage');
        _setState(AuthState.error);
        await connection.close();
        return false;
      }

      // Save credentials securely
      LoggerService.info('🔐 Saving credentials...');
      await credentials.saveSecurely();

      // Update state
      _connection = connection;
      _credentials = credentials;
      _setState(AuthState.authenticated);

      LoggerService.info('✅ Login successful!');
      return true;
    } catch (e, stackTrace) {
      _errorMessage = '登录过程出错: $e';
      LoggerService.info('❌ Login error: $e');
      LoggerService.info('❌ Stack trace: $stackTrace');
      _setState(AuthState.error);
      return false;
    }
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

      LoggerService.info('✅ 登出完成');
    } catch (e) {
      LoggerService.error('❌ 登出过程出错', error: e);
      // Still reset state even if cleanup fails
      _connection = null;
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
      return await login(
        userId: credentials.userId,
        ecPassword: credentials.ecPassword,
        password: credentials.password,
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
        return true;
      } else {
        LoggerService.warning('❌ 静默重登录失败');
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
      final ecLoginStatus = await _connection!.ecLogin();

      if (!ecLoginStatus.success) {
        LoggerService.warning('❌ 静默重登录: EC登录失败');
        return false;
      }

      // 执行UAAP登录
      LoggerService.info('🔐 静默重登录: 执行UAAP登录...');
      final uaapLoginStatus = await _connection!.uaapLogin();

      if (!uaapLoginStatus.success) {
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
    } else if (status.failMaybeAttacked) {
      return '登录频繁，请稍后重试';
    } else if (status.failNetworkError) {
      return 'EC系统网络连接失败';
    } else {
      return 'EC系统登录失败';
    }
  }

  /// Get user-friendly error message for UAAP login status
  String _getUaapLoginErrorMessage(dynamic status) {
    if (status.failInvalidCredentials) {
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
    super.dispose();
  }
}
