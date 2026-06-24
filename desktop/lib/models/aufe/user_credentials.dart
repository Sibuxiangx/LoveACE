import '../../services/secure_value_store.dart';

/// User credentials for authentication
class UserCredentials {
  final String userId;
  final String ecPassword;
  final String password;

  UserCredentials({
    required this.userId,
    required this.ecPassword,
    required this.password,
  });

  factory UserCredentials.fromJson(Map<String, dynamic> json) {
    return UserCredentials(
      userId: json['userId'] as String? ?? '',
      ecPassword: json['ecPassword'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'userId': userId, 'ecPassword': ecPassword, 'password': password};
  }

  /// Save credentials securely using the platform credential store.
  Future<void> saveSecurely() async {
    await SecureValueStore.write(key: 'user_id', value: userId);
    await SecureValueStore.write(key: 'ec_password', value: ecPassword);
    await SecureValueStore.write(key: 'password', value: password);
  }

  /// Load credentials from the platform credential store.
  static Future<UserCredentials?> loadSecurely() async {
    final userId = await SecureValueStore.read(key: 'user_id');
    final ecPassword = await SecureValueStore.read(key: 'ec_password');
    final password = await SecureValueStore.read(key: 'password');

    if (userId == null || ecPassword == null || password == null) {
      return null;
    }

    return UserCredentials(
      userId: userId,
      ecPassword: ecPassword,
      password: password,
    );
  }

  /// Clear credentials from the platform credential store.
  static Future<void> clearSecurely() async {
    await SecureValueStore.delete(key: 'user_id');
    await SecureValueStore.delete(key: 'ec_password');
    await SecureValueStore.delete(key: 'password');
  }

  // ==================== 记住密码功能（独立存储）====================

  /// 保存「记住密码」的凭证（独立于会话凭证）
  Future<void> saveRemembered() async {
    await SecureValueStore.write(key: 'remembered_user_id', value: userId);
    await SecureValueStore.write(
      key: 'remembered_ec_password',
      value: ecPassword,
    );
    await SecureValueStore.write(key: 'remembered_password', value: password);
    await SecureValueStore.write(
      key: 'remember_password_enabled',
      value: 'true',
    );
  }

  /// 加载「记住密码」的凭证
  static Future<UserCredentials?> loadRemembered() async {
    final enabled = await SecureValueStore.read(
      key: 'remember_password_enabled',
    );
    if (enabled != 'true') {
      return null;
    }

    final userId = await SecureValueStore.read(key: 'remembered_user_id');
    final ecPassword = await SecureValueStore.read(
      key: 'remembered_ec_password',
    );
    final password = await SecureValueStore.read(key: 'remembered_password');

    if (userId == null || ecPassword == null || password == null) {
      return null;
    }

    return UserCredentials(
      userId: userId,
      ecPassword: ecPassword,
      password: password,
    );
  }

  /// 清除「记住密码」的凭证
  static Future<void> clearRemembered() async {
    await SecureValueStore.delete(key: 'remembered_user_id');
    await SecureValueStore.delete(key: 'remembered_ec_password');
    await SecureValueStore.delete(key: 'remembered_password');
    await SecureValueStore.delete(key: 'remember_password_enabled');
  }

  /// 检查是否启用了「记住密码」
  static Future<bool> isRememberPasswordEnabled() async {
    final enabled = await SecureValueStore.read(
      key: 'remember_password_enabled',
    );
    return enabled == 'true';
  }

  @override
  String toString() {
    return 'UserCredentials(userId: $userId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserCredentials &&
        other.userId == userId &&
        other.ecPassword == ecPassword &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(userId, ecPassword, password);
}
