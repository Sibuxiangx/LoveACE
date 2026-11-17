import 'package:flutter/foundation.dart';

/// The signed-in school account as the webview knows it. Only the student id is needed:
/// the page keys its saved plan by it. The desktop app's login stays on the Go side.
class AuthProvider extends ChangeNotifier {
  AuthProvider(String userId)
    : _credentials = userId.isEmpty ? null : SmartCredentials(userId: userId);

  final SmartCredentials? _credentials;

  SmartCredentials? get credentials => _credentials;
}

class SmartCredentials {
  const SmartCredentials({required this.userId});

  final String userId;
}
