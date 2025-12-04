import 'package:flutter/foundation.dart';
import '../models/jwc/exam_info.dart';
import '../models/jwc/exam_info_response.dart';
import '../services/jwc/jwc_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 考试信息页面状态枚举
enum ExamState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 考试信息状态管理
///
/// 管理考试信息的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class ExamProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存键
  static const String _cacheKey = 'exam_info';

  /// 缓存有效期（默认15分钟）
  static const Duration _cacheDuration = Duration(minutes: 15);

  /// 当前状态
  ExamState _state = ExamState.initial;

  /// 考试信息列表
  List<UnifiedExamInfo> _exams = [];

  /// 考试总数
  int _totalCount = 0;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  ExamState get state => _state;

  /// 获取考试信息列表
  List<UnifiedExamInfo> get exams => _exams;

  /// 获取考试总数
  int get totalCount => _totalCount;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建考试信息Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  ExamProvider(this.jwcService);

  /// 从缓存加载数据
  ///
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载考试信息');

      // 读取考试信息缓存
      final cachedExamInfo = await CacheManager.get<ExamInfoResponse>(
        key: _cacheKey,
        fromJson: (json) => ExamInfoResponse.fromJson(json),
      );

      // 如果缓存存在，使用缓存数据
      if (cachedExamInfo != null) {
        _exams = cachedExamInfo.exams;
        _totalCount = cachedExamInfo.totalCount;
        _state = ExamState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载考试信息成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有考试信息');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载考试信息失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    // 设置加载状态
    _state = ExamState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载考试信息');

      // 获取考试信息
      final examResponse = await jwcService.exam.getExamInfo();

      if (!examResponse.success) {
        // 考试信息获取失败
        _state = ExamState.error;
        _errorMessage = examResponse.error ?? '获取考试信息失败';
        _isRetryable = examResponse.retryable;
        notifyListeners();
        LoggerService.error('❌ 加载考试信息失败: $_errorMessage');
        return;
      }

      // 请求成功，更新数据
      _exams = examResponse.data!.exams;
      _totalCount = examResponse.data!.totalCount;
      _state = ExamState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 保存到缓存
      await _saveToCache();

      notifyListeners();

      LoggerService.info('✅ 从网络加载考试信息成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = ExamState.error;
      _errorMessage = '加载考试信息时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载考试信息失败', error: e);
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      // 构造 ExamInfoResponse 对象
      final examInfoResponse = ExamInfoResponse(
        exams: _exams,
        totalCount: _totalCount,
      );

      // 保存到缓存
      await CacheManager.set(
        key: _cacheKey,
        data: examInfoResponse,
        duration: _cacheDuration,
        toJson: (response) => response.toJson(),
      );

      LoggerService.info('💾 考试信息已保存到缓存');
    } catch (e) {
      LoggerService.error('❌ 保存考试信息到缓存失败', error: e);
    }
  }

  /// 加载考试数据
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

  /// 刷新考试数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }
}
