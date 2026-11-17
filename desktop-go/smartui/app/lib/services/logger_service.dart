import 'package:flutter/foundation.dart';

/// Logs to the webview's console. The desktop app's file logger does not exist here.
class LoggerService {
  static void debug(String message, {dynamic error, StackTrace? stackTrace}) {
    _log('DEBUG', message, error, stackTrace);
  }

  static void info(String message, {dynamic error, StackTrace? stackTrace}) {
    _log('INFO', message, error, stackTrace);
  }

  static void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    _log('WARN', message, error, stackTrace);
  }

  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    _log('ERROR', message, error, stackTrace);
  }

  static void _log(String level, String message, dynamic error, StackTrace? stackTrace) {
    debugPrint('[$level] $message${error == null ? '' : ' $error'}');
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }
}
