import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/isim/electricity_info.dart';
import '../services/isim/isim_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 电费查询页面状态枚举
enum ElectricityState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 电费信息状态管理
///
/// 管理电费信息的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
/// 支持房间绑定管理，持久化存储用户绑定的房间信息
class ElectricityProvider extends ChangeNotifier {
  final ISIMService isimService;

  /// 缓存键
  static const String _cacheKey = 'electricity_info';

  /// 缓存有效期（15分钟）
  static const Duration _cacheDuration = Duration(minutes: 15);

  /// 房间绑定存储键前缀
  static const String _roomBindingPrefix = 'electricity_room_';

  /// 当前状态
  ElectricityState _state = ElectricityState.initial;

  /// 电费信息
  ElectricityInfo? _electricityInfo;

  /// 绑定的房间代码
  String? _boundRoomCode;

  /// 绑定的房间显示文本
  String? _boundRoomDisplay;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  ElectricityState get state => _state;

  /// 获取电费信息
  ElectricityInfo? get electricityInfo => _electricityInfo;

  /// 获取绑定的房间代码
  String? get boundRoomCode => _boundRoomCode;

  /// 获取绑定的房间显示文本
  String? get boundRoomDisplay => _boundRoomDisplay;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建电费Provider实例
  ///
  /// [isimService] ISIM服务实例
  ElectricityProvider(this.isimService);

  /// 从缓存加载数据
  ///
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载电费数据');

      // 读取电费信息缓存
      final cachedElectricityInfo = await CacheManager.get<ElectricityInfo>(
        key: _cacheKey,
        fromJson: (json) => ElectricityInfo.fromJson(json),
      );

      // 如果缓存存在，使用缓存数据
      if (cachedElectricityInfo != null) {
        _electricityInfo = cachedElectricityInfo;
        _state = ElectricityState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载电费数据成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有电费数据');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载电费数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = ElectricityState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载电费数据');

      // 检查房间是否已绑定
      if (_boundRoomCode == null || _boundRoomCode!.isEmpty) {
        _state = ElectricityState.error;
        _errorMessage = '请先绑定房间';
        _isRetryable = false;
        notifyListeners();
        LoggerService.warning('⚠️ 房间未绑定，无法加载电费数据');
        return;
      }

      // 获取电费信息
      final response = await isimService.getElectricityInfo(
        _boundRoomCode!,
        displayText: _boundRoomDisplay,
      );

      if (response.success) {
        // 请求成功，更新数据
        _electricityInfo = response.data;
        _state = ElectricityState.loaded;
        _errorMessage = null;
        _isRetryable = false;

        // 保存到缓存
        await _saveToCache();

        LoggerService.info('✅ 从网络加载电费数据成功');
      } else {
        // 请求失败
        _state = ElectricityState.error;
        _errorMessage = response.error ?? '获取电费信息失败';
        _isRetryable = response.retryable;
        LoggerService.error('❌ 加载电费数据失败: $_errorMessage');
      }
    } catch (e) {
      // 捕获未预期的异常
      _state = ElectricityState.error;
      _errorMessage = '加载电费数据时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      LoggerService.error('❌ 从网络加载电费数据失败', error: e);
    }

    notifyListeners();
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      if (_electricityInfo != null) {
        await CacheManager.set(
          key: _cacheKey,
          data: _electricityInfo!,
          duration: _cacheDuration,
          toJson: (info) => info.toJson(),
        );
        LoggerService.info('💾 电费数据已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存电费数据到缓存失败', error: e);
    }
  }

  /// 生成用户特定的房间绑定键
  ///
  /// [userId] 用户ID
  ///
  /// 返回用户特定的存储键
  String _getRoomBindingKey(String userId) {
    return '$_roomBindingPrefix$userId';
  }

  /// 加载绑定的房间信息
  ///
  /// 从 SharedPreferences 中加载用户绑定的房间信息
  ///
  /// [userId] 用户ID
  Future<void> loadBoundRoom(String userId) async {
    try {
      LoggerService.info('🔌 加载用户绑定的房间信息: $userId');

      final prefs = await SharedPreferences.getInstance();
      final key = _getRoomBindingKey(userId);

      // 读取房间代码和显示文本
      _boundRoomCode = prefs.getString(key);
      _boundRoomDisplay = prefs.getString('${key}_display');

      if (_boundRoomCode != null && _boundRoomCode!.isNotEmpty) {
        LoggerService.info('✅ 已加载绑定的房间: $_boundRoomCode ($_boundRoomDisplay)');
        notifyListeners();
      } else {
        LoggerService.info('📭 用户未绑定房间');
      }
    } catch (e) {
      LoggerService.error('❌ 加载绑定房间信息失败', error: e);
    }
  }

  /// 绑定房间
  ///
  /// 将房间代码和显示文本保存到 SharedPreferences
  /// 清除现有缓存并重新加载数据
  ///
  /// [roomCode] 房间代码（如 "1-101"）
  /// [displayText] 房间显示文本（如 "1号楼101室"）
  /// [userId] 用户ID
  Future<void> bindRoom(
    String roomCode,
    String displayText,
    String userId,
  ) async {
    try {
      LoggerService.info('🔌 绑定房间: $roomCode ($displayText)');

      final prefs = await SharedPreferences.getInstance();
      final key = _getRoomBindingKey(userId);

      // 保存房间代码和显示文本
      await prefs.setString(key, roomCode);
      await prefs.setString('${key}_display', displayText);

      // 更新内存中的绑定信息
      _boundRoomCode = roomCode;
      _boundRoomDisplay = displayText;

      // 清除现有缓存
      LoggerService.info('🔌 清除现有电费数据缓存');
      await CacheManager.remove(_cacheKey);

      // 重置状态
      _electricityInfo = null;
      _state = ElectricityState.initial;
      _errorMessage = null;
      _isRetryable = false;

      notifyListeners();

      LoggerService.info('✅ 房间绑定成功: $roomCode');
    } catch (e) {
      LoggerService.error('❌ 绑定房间失败', error: e);
      rethrow;
    }
  }

  /// 解绑房间
  ///
  /// 清除房间绑定信息和缓存数据
  ///
  /// [userId] 用户ID
  Future<void> unbindRoom(String userId) async {
    try {
      LoggerService.info('🔌 解绑房间');

      final prefs = await SharedPreferences.getInstance();
      final key = _getRoomBindingKey(userId);

      // 删除房间绑定信息
      await prefs.remove(key);
      await prefs.remove('${key}_display');

      // 清除缓存
      await CacheManager.remove(_cacheKey);

      // 重置状态
      _boundRoomCode = null;
      _boundRoomDisplay = null;
      _electricityInfo = null;
      _state = ElectricityState.initial;
      _errorMessage = null;
      _isRetryable = false;

      notifyListeners();

      LoggerService.info('✅ 房间解绑成功');
    } catch (e) {
      LoggerService.error('❌ 解绑房间失败', error: e);
      rethrow;
    }
  }

  /// 加载电费数据
  ///
  /// 每次调用都会先尝试从缓存读取，如果缓存不存在或已过期则从网络获取
  /// 手动刷新时会清除缓存并强制从网络获取
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存）
  Future<void> loadData({bool forceRefresh = false}) async {
    // 如果强制刷新，清除缓存
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await CacheManager.remove(_cacheKey);
      await _loadFromNetwork();
      return;
    }

    // 尝试从缓存加载
    final cacheLoaded = await _loadFromCache();
    if (cacheLoaded) {
      LoggerService.info('✅ 使用缓存数据');
      return;
    }

    // 缓存不存在或已过期，从网络加载
    LoggerService.info('📭 缓存不可用，从网络加载');
    await _loadFromNetwork();
  }

  /// 刷新电费数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }
}
