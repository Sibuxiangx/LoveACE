import 'package:flutter/foundation.dart';
import '../models/jwc/term_score_response.dart';
import '../services/jwc/jwc_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';
import '../utils/csv_exporter/csv_exporter.dart';

/// 学期成绩页面状态枚举
enum TermScoreState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 学期成绩状态管理
///
/// 管理成绩数据的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持按学期分离的缓存机制，减少不必要的网络请求
/// 支持成绩记录的展开/收起状态管理
class TermScoreProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 缓存有效期（默认30分钟）
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// 当前状态
  TermScoreState _state = TermScoreState.initial;

  /// 成绩数据
  TermScoreResponse? _scoreData;

  /// 当前查询的学期代码
  String? _currentTermCode;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 展开状态管理：记录索引 → 是否展开
  final Map<int, bool> _expandedRecords = {};

  /// 获取当前状态
  TermScoreState get state => _state;

  /// 获取成绩数据
  TermScoreResponse? get scoreData => _scoreData;

  /// 获取当前学期代码
  String? get currentTermCode => _currentTermCode;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 获取展开状态
  Map<int, bool> get expandedRecords => _expandedRecords;

  /// 创建学期成绩Provider实例
  ///
  /// [jwcService] 教务系统服务实例
  TermScoreProvider(this.jwcService);

  /// 生成缓存键
  ///
  /// 每个学期使用独立的缓存键
  String _getCacheKey(String termCode) => 'term_score_$termCode';

  /// 加载指定学期的成绩数据
  ///
  /// 每次调用都会先尝试从缓存读取，如果缓存不存在或已过期则从网络获取
  /// 手动刷新时会清除缓存并强制从网络获取
  ///
  /// [termCode] 学期代码
  /// [forceRefresh] 是否强制刷新（清除缓存）
  Future<void> loadScore(String termCode, {bool forceRefresh = false}) async {
    // 如果切换到不同的学期，清空旧数据并重置状态
    if (_currentTermCode != null && _currentTermCode != termCode) {
      LoggerService.info('🔄 切换学期，清空旧数据');
      _scoreData = null;
      _state = TermScoreState.initial;
      _expandedRecords.clear();
      notifyListeners();
    }

    // 更新当前学期代码
    _currentTermCode = termCode;

    // 如果强制刷新，清除缓存
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await CacheManager.remove(_getCacheKey(termCode));
      await _loadFromNetwork(termCode);
      return;
    }

    // 尝试从缓存加载
    final cacheLoaded = await _loadFromCache(termCode);
    if (cacheLoaded) {
      LoggerService.info('✅ 使用缓存数据');
      return;
    }

    // 缓存不存在或已过期，从网络加载
    LoggerService.info('📭 缓存不可用，从网络加载');
    await _loadFromNetwork(termCode);
  }

  /// 从缓存加载成绩数据
  ///
  /// [termCode] 学期代码
  /// 返回 true 表示成功从缓存加载，false 表示缓存不可用
  Future<bool> _loadFromCache(String termCode) async {
    try {
      LoggerService.info('📦 尝试从缓存加载成绩数据，学期: $termCode');

      final cached = await CacheManager.get<TermScoreResponse>(
        key: _getCacheKey(termCode),
        fromJson: (json) => TermScoreResponse.fromJson(json),
      );

      if (cached != null) {
        _scoreData = cached;
        _state = TermScoreState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        // 重置展开状态
        _expandedRecords.clear();
        notifyListeners();

        LoggerService.info('✅ 从缓存加载成绩数据成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有成绩数据');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载成绩数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载成绩数据
  ///
  /// [termCode] 学期代码
  Future<void> _loadFromNetwork(String termCode) async {
    // 设置加载状态
    _state = TermScoreState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载成绩数据，学期: $termCode');

      // 获取成绩数据
      final response = await jwcService.score.getTermScore(termCode);

      if (!response.success) {
        // 成绩数据获取失败
        _state = TermScoreState.error;
        _errorMessage = response.error ?? '获取成绩数据失败';
        _isRetryable = response.retryable;
        notifyListeners();
        LoggerService.error('❌ 加载成绩数据失败: $_errorMessage');
        return;
      }

      // 请求成功，更新数据
      _scoreData = response.data;
      _state = TermScoreState.loaded;
      _errorMessage = null;
      _isRetryable = false;
      // 重置展开状态
      _expandedRecords.clear();

      // 保存到缓存
      await _saveToCache(termCode);

      notifyListeners();

      LoggerService.info('✅ 从网络加载成绩数据成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = TermScoreState.error;
      _errorMessage = '加载成绩数据时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载成绩数据失败', error: e);
    }
  }

  /// 保存成绩数据到缓存
  ///
  /// [termCode] 学期代码
  Future<void> _saveToCache(String termCode) async {
    try {
      if (_scoreData != null) {
        await CacheManager.set<TermScoreResponse>(
          key: _getCacheKey(termCode),
          data: _scoreData!,
          duration: _cacheDuration,
          toJson: (d) => d.toJson(),
        );
        LoggerService.info('💾 成绩数据已保存到缓存');
      }
    } catch (e) {
      LoggerService.error('❌ 保存成绩数据到缓存失败', error: e);
    }
  }

  /// 刷新当前学期的成绩数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    if (_currentTermCode != null) {
      await loadScore(_currentTermCode!, forceRefresh: true);
    }
  }

  /// 切换成绩记录的展开/收起状态
  ///
  /// [index] 成绩记录的索引
  void toggleRecordExpansion(int index) {
    _expandedRecords[index] = !(_expandedRecords[index] ?? false);
    notifyListeners();
  }

  /// 检查指定索引的记录是否展开
  ///
  /// [index] 成绩记录的索引
  /// 返回 true 表示展开，false 表示收起
  bool isRecordExpanded(int index) {
    return _expandedRecords[index] ?? false;
  }

  /// 导出当前学期成绩为CSV
  ///
  /// 导出前会强制刷新数据以确保数据最新
  Future<void> exportToCSV() async {
    if (_currentTermCode == null) {
      throw Exception('没有可导出的学期数据');
    }

    // 强制刷新数据
    await loadScore(_currentTermCode!, forceRefresh: true);

    // 检查数据是否加载成功
    if (_state != TermScoreState.loaded || _scoreData == null) {
      throw Exception('数据加载失败，无法导出');
    }

    // 导出CSV
    final exporter = CsvExporter();
    await exporter.exportTermScores(_scoreData!.records, _currentTermCode!);

    LoggerService.info('✅ 学期成绩CSV导出完成');
  }
}
