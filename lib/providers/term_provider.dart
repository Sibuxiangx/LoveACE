import 'package:flutter/foundation.dart';
import '../models/jwc/term_item.dart';
import '../services/jwc/jwc_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 学期列表页面状态枚举
enum TermState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 学期列表状态管理
///
/// 管理学期列表的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class TermProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存键
  static const String _cacheKey = 'term_list';

  /// 缓存有效期（默认30分钟）
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// 当前状态
  TermState _state = TermState.initial;

  /// 学期列表
  List<TermItem>? _termList;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  TermState get state => _state;

  /// 获取学期列表
  List<TermItem>? get termList => _termList;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建学期列表Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  TermProvider(this.jwcService);

  /// 加载学期列表数据
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

  /// 从缓存加载学期列表
  ///
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载学期列表');

      // 读取学期列表缓存（包装成Map格式）
      final cachedListWrapper = await CacheManager.get<Map<String, dynamic>>(
        key: _cacheKey,
        fromJson: (json) => json,
      );

      List<TermItem>? cachedList;
      if (cachedListWrapper != null && cachedListWrapper['list'] != null) {
        cachedList = (cachedListWrapper['list'] as List)
            .map((item) => TermItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      if (cachedList != null && cachedList.isNotEmpty) {
        _termList = cachedList;
        _state = TermState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载学期列表成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有学期列表数据');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载学期列表失败', error: e);
      return false;
    }
  }

  /// 从网络加载学期列表
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = TermState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载学期列表');

      // 获取学期列表
      final response = await jwcService.term.getAllTerms();

      if (!response.success) {
        // 学期列表获取失败
        _state = TermState.error;
        _errorMessage = response.error ?? '获取学期列表失败';
        _isRetryable = response.retryable;
        notifyListeners();
        LoggerService.error('❌ 加载学期列表失败: $_errorMessage');
        return;
      }

      // 请求成功，更新数据
      _termList = response.data;
      _state = TermState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 保存到缓存
      await _saveToCache();

      notifyListeners();

      LoggerService.info('✅ 从网络加载学期列表成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = TermState.error;
      _errorMessage = '加载学期列表时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载学期列表失败', error: e);
    }
  }

  /// 保存学期列表到缓存
  Future<void> _saveToCache() async {
    try {
      if (_termList != null) {
        // 将列表包装成Map以符合CacheManager的要求
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKey,
          data: {'list': _termList!.map((item) => item.toJson()).toList()},
          duration: _cacheDuration,
          toJson: (d) => d,
        );
        LoggerService.info('💾 学期列表已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存学期列表到缓存失败', error: e);
    }
  }

  /// 刷新学期列表数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }
}
