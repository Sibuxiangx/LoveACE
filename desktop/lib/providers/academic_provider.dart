import 'package:flutter/foundation.dart';
import '../models/jwc/academic_info.dart';
import '../models/jwc/training_plan_info.dart';
import '../services/jwc/jwc_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 学术信息页面状态枚举
enum AcademicState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 学术信息状态管理
///
/// 管理学业信息和培养方案信息的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class AcademicProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存键
  static const String _cacheKeyAcademic = 'academic_info';
  static const String _cacheKeyTrainingPlan = 'training_plan_info';

  /// 缓存有效期（默认30分钟）
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// 当前状态
  AcademicState _state = AcademicState.initial;

  /// 学业信息
  AcademicInfo? _academicInfo;

  /// 培养方案信息
  TrainingPlanInfo? _trainingPlanInfo;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  AcademicState get state => _state;

  /// 获取学业信息
  AcademicInfo? get academicInfo => _academicInfo;

  /// 获取培养方案信息
  TrainingPlanInfo? get trainingPlanInfo => _trainingPlanInfo;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建学术信息Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  AcademicProvider(this.jwcService);

  /// 加载学术数据
  ///
  /// 每次调用都会先尝试从缓存读取，如果缓存不存在或已过期则从网络获取
  /// 手动刷新时会清除缓存并强制从网络获取
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存）
  Future<void> loadData({bool forceRefresh = false}) async {
    // 如果强制刷新，清除缓存
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await _clearCache();
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
      LoggerService.info('📦 尝试从缓存加载学术数据');

      // 读取学业信息缓存
      final cachedAcademicInfo = await CacheManager.get<AcademicInfo>(
        key: _cacheKeyAcademic,
        fromJson: (json) => AcademicInfo.fromJson(json),
      );

      // 读取培养方案信息缓存
      final cachedTrainingPlanInfo = await CacheManager.get<TrainingPlanInfo>(
        key: _cacheKeyTrainingPlan,
        fromJson: (json) => TrainingPlanInfo.fromJson(json),
      );

      // 如果两个缓存都存在，使用缓存数据
      if (cachedAcademicInfo != null && cachedTrainingPlanInfo != null) {
        _academicInfo = cachedAcademicInfo;
        _trainingPlanInfo = cachedTrainingPlanInfo;
        _state = AcademicState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载学术数据成功');
        return true;
      }

      LoggerService.info('📭 缓存数据不完整或已过期');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = AcademicState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载学术数据');

      // 获取学业信息
      final academicResponse = await jwcService.academic.getAcademicInfo();

      if (!academicResponse.success) {
        // 学业信息获取失败
        _state = AcademicState.error;
        _errorMessage = academicResponse.error ?? '获取学业信息失败';
        _isRetryable = academicResponse.retryable;
        notifyListeners();
        return;
      }

      // 获取培养方案信息
      final trainingPlanResponse = await jwcService.academic
          .getTrainingPlanInfo();

      if (!trainingPlanResponse.success) {
        // 培养方案信息获取失败
        _state = AcademicState.error;
        _errorMessage = trainingPlanResponse.error ?? '获取培养方案信息失败';
        _isRetryable = trainingPlanResponse.retryable;
        notifyListeners();
        return;
      }

      // 两个请求都成功，更新数据
      _academicInfo = academicResponse.data;
      _trainingPlanInfo = trainingPlanResponse.data;
      _state = AcademicState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 保存到缓存
      await _saveToCache();

      notifyListeners();

      LoggerService.info('✅ 从网络加载学术数据成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = AcademicState.error;
      _errorMessage = '加载数据时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载数据失败', error: e);
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    if (_academicInfo != null) {
      await CacheManager.set(
        key: _cacheKeyAcademic,
        data: _academicInfo!,
        duration: _cacheDuration,
        toJson: (info) => info.toJson(),
      );
    }

    if (_trainingPlanInfo != null) {
      await CacheManager.set(
        key: _cacheKeyTrainingPlan,
        data: _trainingPlanInfo!,
        duration: _cacheDuration,
        toJson: (info) => info.toJson(),
      );
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    await CacheManager.remove(_cacheKeyAcademic);
    await CacheManager.remove(_cacheKeyTrainingPlan);
  }

  /// 刷新学术数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }
}
