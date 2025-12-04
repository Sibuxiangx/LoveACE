import 'package:flutter/foundation.dart';
import '../models/jwc/plan_completion_info.dart';
import '../services/jwc/jwc_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';
import '../utils/csv_exporter/csv_exporter.dart';

/// 培养方案页面状态枚举
enum TrainingPlanState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 培养方案状态管理
///
/// 管理培养方案完成情况的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class TrainingPlanProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存键
  static const String _cacheKey = 'training_plan_completion';

  /// 缓存有效期（60分钟）
  static const Duration _cacheDuration = Duration(minutes: 60);

  /// 当前状态
  TrainingPlanState _state = TrainingPlanState.initial;

  /// 培养方案完成信息
  PlanCompletionInfo? _planInfo;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  TrainingPlanState get state => _state;

  /// 获取培养方案完成信息
  PlanCompletionInfo? get planInfo => _planInfo;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建培养方案Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  TrainingPlanProvider(this.jwcService);

  /// 加载培养方案数据
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
      LoggerService.info('📦 尝试从缓存加载培养方案数据');

      final cached = await CacheManager.get<PlanCompletionInfo>(
        key: _cacheKey,
        fromJson: (json) => PlanCompletionInfo.fromJson(json),
      );

      if (cached != null) {
        _planInfo = cached;
        _state = TrainingPlanState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载培养方案数据成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有培养方案数据');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载培养方案数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = TrainingPlanState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载培养方案数据');

      // 获取培养方案完成信息
      final response = await jwcService.plan.getPlanCompletion();

      if (!response.success) {
        // 培养方案信息获取失败
        _state = TrainingPlanState.error;
        _errorMessage = response.error ?? '获取培养方案失败';
        _isRetryable = response.retryable;
        notifyListeners();
        LoggerService.error('❌ 加载培养方案数据失败: $_errorMessage');
        return;
      }

      // 请求成功，更新数据
      _planInfo = response.data;
      _state = TrainingPlanState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 保存到缓存
      await _saveToCache();

      notifyListeners();

      LoggerService.info('✅ 从网络加载培养方案数据成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = TrainingPlanState.error;
      _errorMessage = '加载数据时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载培养方案数据失败', error: e);
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      if (_planInfo != null) {
        await CacheManager.set(
          key: _cacheKey,
          data: _planInfo!,
          duration: _cacheDuration,
          toJson: (info) => info.toJson(),
        );
        LoggerService.info('💾 培养方案数据已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存培养方案数据到缓存失败', error: e);
    }
  }

  /// 刷新培养方案数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }

  /// 导出培养方案完成情况为CSV
  ///
  /// 导出前会强制刷新数据以确保数据最新
  Future<void> exportToCSV() async {
    // 强制刷新数据
    await loadData(forceRefresh: true);

    // 检查数据是否加载成功
    if (_state != TrainingPlanState.loaded || _planInfo == null) {
      throw Exception('数据加载失败，无法导出');
    }

    // 导出CSV
    final exporter = CsvExporter();
    await exporter.exportPlanCompletionInfo(_planInfo!);

    LoggerService.info('✅ 培养方案完成情况CSV导出完成');
  }
}
