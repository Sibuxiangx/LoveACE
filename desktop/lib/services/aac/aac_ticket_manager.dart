import '../logger_service.dart';
import '../secure_value_store.dart';

/// AAC Ticket管理器
///
/// 负责管理用户的AAC系统ticket，支持多账户隔离存储
class AACTicketManager {
  static const String _keyPrefix = 'aac_ticket_';

  /// 获取用户的AAC ticket
  ///
  /// [userId] - 用户ID（学号）
  /// 返回解密后的ticket，如果不存在则返回null
  static Future<String?> getTicket(String userId) async {
    try {
      final key = _getKey(userId);
      final encryptedTicket = await SecureValueStore.read(key: key);

      if (encryptedTicket == null) {
        LoggerService.info('📭 用户 $userId 的AAC ticket不存在');
        return null;
      }

      // 这里简化处理，实际项目中ticket已经是可用的字符串
      // 如果需要解密，可以在这里添加解密逻辑
      LoggerService.info('📦 成功获取用户 $userId 的AAC ticket');
      return encryptedTicket;
    } catch (e) {
      LoggerService.error('❌ 获取AAC ticket失败', error: e);
      return null;
    }
  }

  /// 保存用户的AAC ticket
  ///
  /// [userId] - 用户ID（学号）
  /// [ticket] - ticket字符串
  static Future<void> saveTicket(String userId, String ticket) async {
    try {
      final key = _getKey(userId);
      await SecureValueStore.write(key: key, value: ticket);
      LoggerService.info('💾 成功保存用户 $userId 的AAC ticket');
    } catch (e) {
      LoggerService.error('❌ 保存AAC ticket失败', error: e);
      rethrow;
    }
  }

  /// 删除用户的AAC ticket
  ///
  /// [userId] - 用户ID（学号）
  static Future<void> deleteTicket(String userId) async {
    try {
      final key = _getKey(userId);
      await SecureValueStore.delete(key: key);
      LoggerService.info('🗑️ 成功删除用户 $userId 的AAC ticket');
    } catch (e) {
      LoggerService.error('❌ 删除AAC ticket失败', error: e);
      rethrow;
    }
  }

  /// 检查用户是否有AAC ticket
  ///
  /// [userId] - 用户ID（学号）
  static Future<bool> hasTicket(String userId) async {
    final ticket = await getTicket(userId);
    return ticket != null && ticket.isNotEmpty;
  }

  /// 生成存储key
  static String _getKey(String userId) {
    return '$_keyPrefix$userId';
  }

  /// 清除所有AAC tickets（用于调试或重置）
  static Future<void> clearAllTickets() async {
    try {
      final allKeys = await SecureValueStore.readAll();
      for (final key in allKeys.keys) {
        if (key.startsWith(_keyPrefix)) {
          await SecureValueStore.delete(key: key);
        }
      }
      LoggerService.info('🗑️ 已清除所有AAC tickets');
    } catch (e) {
      LoggerService.error('❌ 清除所有AAC tickets失败', error: e);
      rethrow;
    }
  }
}
