import 'package:flutter/foundation.dart';
import '../models/jwc/plan_completion_info.dart';
import '../models/jwc/plan_option.dart';
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

  /// 需要选择培养方案（多培养方案用户）
  needSelection,
}

/// 培养方案状态管理
///
/// 管理培养方案完成情况的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
/// 支持多培养方案用户选择
class TrainingPlanProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存键前缀
  static const String _cacheKeyPrefix = 'training_plan_completion';

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

  /// 培养方案选项列表（多培养方案用户）
  PlanSelectionResponse? _planSelectionResponse;

  /// 当前选中的培养方案ID
  String? _selectedPlanId;

  /// 获取当前状态
  TrainingPlanState get state => _state;

  /// 获取培养方案完成信息
  PlanCompletionInfo? get planInfo => _planInfo;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 获取培养方案选项列表
  PlanSelectionResponse? get planSelectionResponse => _planSelectionResponse;

  /// 获取培养方案选项
  List<PlanOption> get planOptions => _planSelectionResponse?.options ?? [];

  /// 获取当前选中的培养方案ID
  String? get selectedPlanId => _selectedPlanId;

  /// 是否为多培养方案用户
  bool get hasMultiplePlans => planOptions.length > 1;

  /// 创建培养方案Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  TrainingPlanProvider(this.jwcService);

  /// 获取缓存键（根据培养方案ID）
  String _getCacheKey(String? planId) {
    if (planId != null && planId.isNotEmpty) {
      return '${_cacheKeyPrefix}_$planId';
    }
    return _cacheKeyPrefix;
  }

  /// 加载培养方案数据
  ///
  /// 每次调用都会先尝试从缓存读取，如果缓存不存在或已过期则从网络获取
  /// 手动刷新时会清除缓存并强制从网络获取
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存）
  /// [planId] 可选的培养方案ID，用于多培养方案用户选择具体方案
  Future<void> loadData({bool forceRefresh = false, String? planId}) async {
    // 如果指定了 planId，更新选中的方案
    if (planId != null) {
      _selectedPlanId = planId;
    }

    final cacheKey = _getCacheKey(_selectedPlanId);

    // 如果强制刷新，清除缓存
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await CacheManager.remove(cacheKey);
      await _loadFromNetwork(forceRefresh: true);
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
    await _loadFromNetwork(forceRefresh: false);
  }

  /// 选择培养方案并加载数据
  ///
  /// [planId] 培养方案ID
  Future<void> selectPlan(String planId) async {
    LoggerService.info('📚 选择培养方案: $planId');
    _selectedPlanId = planId;
    await loadData(forceRefresh: true, planId: planId);
  }

  /// 返回培养方案选择页面
  void backToSelection() {
    _state = TrainingPlanState.needSelection;
    _planInfo = null;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();
  }

  /// 从缓存加载数据
  ///
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache() async {
    try {
      final cacheKey = _getCacheKey(_selectedPlanId);
      LoggerService.info('📦 尝试从缓存加载培养方案数据: $cacheKey');

      final cached = await CacheManager.get<PlanCompletionInfo>(
        key: cacheKey,
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
  ///
  /// [forceRefresh] 是否强制刷新（忽略 Service 层缓存）
  Future<void> _loadFromNetwork({bool forceRefresh = false}) async {
    // 设置加载状态
    _state = TrainingPlanState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载培养方案数据 (forceRefresh: $forceRefresh)');

      // 获取培养方案完成信息
      final response = await jwcService.plan.getPlanCompletion(
        planId: _selectedPlanId,
        forceRefresh: forceRefresh,
      );

      // 检查是否需要选择培养方案
      if (response.needsSelection) {
        LoggerService.info('📚 检测到多培养方案，需要用户选择');
        _planSelectionResponse = response.selectionData as PlanSelectionResponse;
        _state = TrainingPlanState.needSelection;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();
        return;
      }

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
        final cacheKey = _getCacheKey(_selectedPlanId);
        await CacheManager.set(
          key: cacheKey,
          data: _planInfo!,
          duration: _cacheDuration,
          toJson: (info) => info.toJson(),
        );
        LoggerService.info('💾 培养方案数据已保存到缓存: $cacheKey');
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

  /// 重置状态（用于切换培养方案时）
  void reset() {
    _state = TrainingPlanState.initial;
    _planInfo = null;
    _errorMessage = null;
    _isRetryable = false;
    _selectedPlanId = null;
    // 不清除 _planSelectionResponse，保留选项列表
    notifyListeners();
  }

  /// 导出培养方案完成情况为CSV
  ///
  /// 导出前会强制刷新数据以确保数据最新
  /// [planId] 可选的培养方案ID，用于多培养方案用户导出指定方案
  Future<void> exportToCSV({String? planId}) async {
    // 如果指定了不同的 planId，需要先加载该方案
    final targetPlanId = planId ?? _selectedPlanId;

    if (targetPlanId != null && targetPlanId != _selectedPlanId) {
      // 临时切换到目标方案进行导出
      final originalPlanId = _selectedPlanId;
      _selectedPlanId = targetPlanId;

      try {
        await loadData(forceRefresh: true, planId: targetPlanId);

        if (_state != TrainingPlanState.loaded || _planInfo == null) {
          throw Exception('数据加载失败，无法导出');
        }

        final exporter = CsvExporter();
        await exporter.exportPlanCompletionInfo(_planInfo!);
        LoggerService.info('✅ 培养方案完成情况CSV导出完成');
      } finally {
        // 恢复原来的方案
        if (originalPlanId != targetPlanId) {
          _selectedPlanId = originalPlanId;
          if (originalPlanId != null) {
            await loadData(forceRefresh: false, planId: originalPlanId);
          }
        }
      }
    } else {
      // 导出当前方案
      await loadData(forceRefresh: true);

      if (_state != TrainingPlanState.loaded || _planInfo == null) {
        throw Exception('数据加载失败，无法导出');
      }

      final exporter = CsvExporter();
      await exporter.exportPlanCompletionInfo(_planInfo!);
      LoggerService.info('✅ 培养方案完成情况CSV导出完成');
    }
  }

  /// 导出指定培养方案为CSV（不切换当前方案）
  ///
  /// 直接加载并导出指定方案，不影响当前显示的方案
  Future<void> exportPlanToCSV(String planId) async {
    LoggerService.info('📤 导出培养方案: $planId');

    // 直接获取指定方案的数据
    final response = await jwcService.plan.getPlanCompletion(planId: planId);

    if (!response.success || response.data == null) {
      throw Exception(response.error ?? '获取培养方案失败');
    }

    final exporter = CsvExporter();
    await exporter.exportPlanCompletionInfo(response.data!);
    LoggerService.info('✅ 培养方案完成情况CSV导出完成');
  }
}
