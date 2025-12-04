import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

/// 缓存项，包含数据和过期时间
class CacheItem<T> {
  final T data;
  final DateTime expiresAt;

  CacheItem({required this.data, required this.expiresAt});

  /// 检查缓存是否已过期
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 转换为JSON
  Map<String, dynamic> toJson(dynamic Function(T) toJsonT) {
    return {'data': toJsonT(data), 'expiresAt': expiresAt.toIso8601String()};
  }

  /// 从JSON创建
  factory CacheItem.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) {
    return CacheItem(
      data: fromJsonT(json['data']),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

/// 基于 SharedPreferences 的缓存管理器
///
/// 提供带过期机制的缓存功能，专门为 Provider 提供数据缓存
class CacheManager {
  static const String _keyPrefix = 'cache_';

  /// 保存缓存数据
  ///
  /// [key] 缓存键
  /// [data] 要缓存的数据
  /// [duration] 缓存有效期
  /// [toJson] 数据序列化函数
  static Future<bool> set<T>({
    required String key,
    required T data,
    required Duration duration,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiresAt = DateTime.now().add(duration);

      final cacheItem = CacheItem(data: data, expiresAt: expiresAt);

      final jsonString = jsonEncode(cacheItem.toJson(toJson));
      final success = await prefs.setString('$_keyPrefix$key', jsonString);

      if (success) {
        LoggerService.info('💾 缓存已保存: $key (过期时间: $expiresAt)');
      } else {
        LoggerService.warning('⚠️ 缓存保存失败: $key');
      }

      return success;
    } catch (e) {
      LoggerService.error('❌ 保存缓存时出错: $key', error: e);
      return false;
    }
  }

  /// 获取缓存数据
  ///
  /// [key] 缓存键
  /// [fromJson] 数据反序列化函数
  ///
  /// 返回缓存的数据，如果缓存不存在或已过期则返回 null
  static Future<T?> get<T>({
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_keyPrefix$key');

      if (jsonString == null) {
        LoggerService.info('📭 缓存未命中: $key');
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final cacheItem = CacheItem.fromJson(
        json,
        (data) => fromJson(data as Map<String, dynamic>),
      );

      if (cacheItem.isExpired) {
        LoggerService.info('⏰ 缓存已过期: $key');
        await remove(key);
        return null;
      }

      LoggerService.info('✅ 缓存命中: $key (过期时间: ${cacheItem.expiresAt})');
      return cacheItem.data;
    } catch (e) {
      LoggerService.error('❌ 读取缓存时出错: $key', error: e);
      return null;
    }
  }

  /// 删除指定缓存
  ///
  /// [key] 缓存键
  static Future<bool> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove('$_keyPrefix$key');

      if (success) {
        LoggerService.info('🗑️ 缓存已删除: $key');
      }

      return success;
    } catch (e) {
      LoggerService.error('❌ 删除缓存时出错: $key', error: e);
      return false;
    }
  }

  /// 清除所有缓存
  static Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_keyPrefix));

      for (final key in keys) {
        await prefs.remove(key);
      }

      LoggerService.info('🧹 所有缓存已清除');
      return true;
    } catch (e) {
      LoggerService.error('❌ 清除缓存时出错', error: e);
      return false;
    }
  }

  /// 检查缓存是否存在且未过期
  ///
  /// [key] 缓存键
  static Future<bool> has(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_keyPrefix$key');

      if (jsonString == null) {
        return false;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final expiresAt = DateTime.parse(json['expiresAt'] as String);

      if (DateTime.now().isAfter(expiresAt)) {
        await remove(key);
        return false;
      }

      return true;
    } catch (e) {
      LoggerService.error('❌ 检查缓存时出错: $key', error: e);
      return false;
    }
  }
}
