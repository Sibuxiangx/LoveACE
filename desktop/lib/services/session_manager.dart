import 'dart:async';
import '../providers/auth_provider.dart';
import 'logger_service.dart';

/// Session Manager for periodic session validation
///
/// Manages automatic session checking to ensure user sessions remain valid.
/// Performs periodic health checks on the authentication session and handles
/// session expiration automatically.
///
/// Usage example:
/// ```dart
/// final sessionManager = SessionManager(authProvider);
///
/// // Start periodic checking (every 5 minutes)
/// sessionManager.startSessionCheck();
///
/// // Stop checking
/// sessionManager.stopSessionCheck();
///
/// // Clean up when done
/// sessionManager.dispose();
/// ```
class SessionManager {
  final AuthProvider authProvider;
  Timer? _sessionCheckTimer;

  /// Interval between session checks (5 minutes)
  static const Duration checkInterval = Duration(minutes: 5);

  /// Creates a SessionManager instance
  ///
  /// [authProvider] - The AuthProvider instance to check session validity
  SessionManager(this.authProvider);

  /// Start periodic session checking
  ///
  /// Initiates a timer that checks session validity every 5 minutes.
  /// If a timer is already running, it will be cancelled and restarted.
  ///
  /// The session check will automatically stop if the session expires.
  void startSessionCheck() {
    // Cancel any existing timer
    _sessionCheckTimer?.cancel();

    LoggerService.info(
      '🔄 Starting session check (interval: ${checkInterval.inMinutes} minutes)',
    );

    // Start periodic checking
    _sessionCheckTimer = Timer.periodic(checkInterval, (_) async {
      await _checkSession();
    });
  }

  /// Stop periodic session checking
  ///
  /// Cancels the active timer and stops all session checks.
  /// Safe to call even if no timer is running.
  void stopSessionCheck() {
    if (_sessionCheckTimer != null) {
      LoggerService.info('⏹️ Stopping session check');
      _sessionCheckTimer?.cancel();
      _sessionCheckTimer = null;
    }
  }

  /// Check if current session is still valid
  ///
  /// Calls AuthProvider.checkSession() to verify session validity.
  /// If the session has expired, automatically stops the periodic checking.
  ///
  /// This is a private method called by the periodic timer.
  Future<void> _checkSession() async {
    LoggerService.info('🔍 Checking session validity...');

    final isValid = await authProvider.checkSession();

    if (!isValid) {
      LoggerService.info('❌ Session expired, stopping periodic checks');
      // Session expired, stop checking
      stopSessionCheck();
    } else {
      LoggerService.info('✅ Session is still valid');
    }
  }

  /// Dispose and clean up resources
  ///
  /// Stops the session check timer and releases resources.
  /// Should be called when the SessionManager is no longer needed.
  void dispose() {
    LoggerService.info('🗑️ Disposing SessionManager');
    stopSessionCheck();
  }
}
