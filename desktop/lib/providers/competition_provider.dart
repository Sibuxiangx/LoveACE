import 'package:flutter/foundation.dart';
import '../models/competition/competition_full_response.dart';
import '../services/competition/competition_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 竞赛信息页面状态枚举
enum CompetitionState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 竞赛信息状态管理
///
/// 管理学科竞赛获奖信息和学分汇总的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class CompetitionProvider extends ChangeNotifier {
  final CompetitionService service;

  /// 缓存键
  static const String _cacheKey = 'competition_info';

  /// 缓存有效期（默认30分钟）
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// 当前状态
  CompetitionState _state = CompetitionState.initial;

  /// 竞赛信息
  CompetitionFullResponse? _competitionInfo;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  CompetitionState get state => _state;

  /// 获取竞赛信息
  CompetitionFullResponse? get competitionInfo => _competitionInfo;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建竞赛信息Provider实例
  ///
  /// [service] 竞赛信息服务实例
  CompetitionProvider(this.service);

  /// 加载竞赛数据
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

  /// 从缓存加载数据
  ///
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载竞赛信息');

      final cached = await CacheManager.get<CompetitionFullResponse>(
        key: _cacheKey,
        fromJson: (json) => CompetitionFullResponse.fromJson(json),
      );

      if (cached != null) {
        _competitionInfo = cached;
        _state = CompetitionState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载竞赛信息成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有竞赛信息');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载竞赛信息失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = CompetitionState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载竞赛信息');

      final response = await service.getCompetitionInfo();

      if (response.success) {
        _competitionInfo = response.data;
        _state = CompetitionState.loaded;
        _errorMessage = null;
        _isRetryable = false;

        // 保存到缓存
        await _saveToCache();

        LoggerService.info('✅ 从网络加载竞赛信息成功，共 ${_competitionInfo?.totalAwardsCount ?? 0} 项获奖');
      } else {
        _state = CompetitionState.error;
        _errorMessage = response.error ?? '加载竞赛信息失败';
        _isRetryable = response.retryable;
        LoggerService.error('❌ 加载竞赛信息失败: $_errorMessage');
      }
    } catch (e) {
      // 捕获未预期的异常
      _state = CompetitionState.error;
      _errorMessage = '加载竞赛信息失败: $e';
      _isRetryable = true; // 未知错误默认可重试
      LoggerService.error('❌ 加载竞赛信息异常', error: e);
    }

    notifyListeners();
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      if (_competitionInfo != null) {
        await CacheManager.set(
          key: _cacheKey,
          data: _competitionInfo!,
          duration: _cacheDuration,
          toJson: (d) => d.toJson(),
        );
        LoggerService.info('💾 竞赛信息已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存竞赛信息到缓存失败', error: e);
    }
  }

  /// 刷新竞赛数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }
}
