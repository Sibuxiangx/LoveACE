import 'package:flutter/foundation.dart';
import '../models/aac/aac_credit_info.dart';
import '../services/aac/aac_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';
import '../utils/csv_exporter/csv_exporter.dart';

/// AAC状态枚举
enum AACState { initial, loading, loaded, error }

/// AAC Provider
///
/// 管理爱安财数据的状态和缓存
class AACProvider extends ChangeNotifier {
  final AACService service;

  static const String _cacheKeyInfo = 'aac_credit_info';
  static const String _cacheKeyList = 'aac_credit_list';
  static const Duration _cacheDuration = Duration(minutes: 30);

  AACState _state = AACState.initial;
  AACCreditInfo? _creditInfo;
  List<AACCreditCategory>? _creditList;
  String? _errorMessage;
  bool _isRetryable = false;

  AACState get state => _state;
  AACCreditInfo? get creditInfo => _creditInfo;
  List<AACCreditCategory>? get creditList => _creditList;
  String? get errorMessage => _errorMessage;
  bool get isRetryable => _isRetryable;

  AACProvider(this.service);

  /// 加载数据
  Future<void> loadData({bool forceRefresh = false}) async {
    // 如果强制刷新，清除缓存
    if (forceRefresh) {
      LoggerService.info('🔄 强制刷新，清除缓存');
      await CacheManager.remove(_cacheKeyInfo);
      await CacheManager.remove(_cacheKeyList);
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
  Future<bool> _loadFromCache() async {
    try {
      LoggerService.info('📦 尝试从缓存加载爱安财数据');

      final cachedInfo = await CacheManager.get<AACCreditInfo>(
        key: _cacheKeyInfo,
        fromJson: (json) => AACCreditInfo.fromJson(json),
      );

      final cachedListWrapper = await CacheManager.get<Map<String, dynamic>>(
        key: _cacheKeyList,
        fromJson: (json) => json,
      );

      List<AACCreditCategory>? cachedList;
      if (cachedListWrapper != null && cachedListWrapper['list'] != null) {
        cachedList = (cachedListWrapper['list'] as List)
            .map(
              (item) =>
                  AACCreditCategory.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }

      if (cachedInfo != null && cachedList != null && cachedList.isNotEmpty) {
        _creditInfo = cachedInfo;
        _creditList = cachedList;
        _state = AACState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();
        LoggerService.info('✅ 从缓存加载爱安财数据成功');
        return true;
      }

      LoggerService.info('📭 缓存中没有爱安财数据');
      return false;
    } catch (e) {
      LoggerService.error('❌ 从缓存加载爱安财数据失败', error: e);
      return false;
    }
  }

  /// 从网络加载数据
  Future<void> _loadFromNetwork() async {
    _state = AACState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 开始从网络加载爱安财数据');

      // 并行请求总分和明细
      final infoResponse = await service.getCreditInfo();
      final listResponse = await service.getCreditList();

      if (infoResponse.success && listResponse.success) {
        _creditInfo = infoResponse.data;
        _creditList = listResponse.data;
        _state = AACState.loaded;
        _errorMessage = null;
        _isRetryable = false;

        // 保存到缓存
        await _saveToCache();

        LoggerService.info('✅ 从网络加载爱安财数据成功');
      } else {
        _state = AACState.error;
        _errorMessage = infoResponse.error ?? listResponse.error ?? '加载失败';
        _isRetryable = infoResponse.retryable || listResponse.retryable;
        LoggerService.error('❌ 加载爱安财数据失败: $_errorMessage');
      }
    } catch (e) {
      _state = AACState.error;
      _errorMessage = '加载爱安财数据失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 加载爱安财数据异常', error: e);
    }

    notifyListeners();
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      if (_creditInfo != null) {
        await CacheManager.set(
          key: _cacheKeyInfo,
          data: _creditInfo!,
          duration: _cacheDuration,
          toJson: (d) => d.toJson(),
        );
      }

      if (_creditList != null) {
        // 将列表包装成Map以符合CacheManager的要求
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyList,
          data: {'list': _creditList!.map((item) => item.toJson()).toList()},
          duration: _cacheDuration,
          toJson: (d) => d,
        );
      }

      LoggerService.info('💾 爱安财数据已保存到缓存');
    } catch (e) {
      LoggerService.error('❌ 保存爱安财数据到缓存失败', error: e);
    }
  }

  /// 刷新数据（强制从网络加载）
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }

  /// 重置AAC ticket
  Future<void> resetTicket() async {
    try {
      await service.resetTicket();
      // 清除缓存
      await CacheManager.remove(_cacheKeyInfo);
      await CacheManager.remove(_cacheKeyList);
      // 重置状态
      _state = AACState.initial;
      _creditInfo = null;
      _creditList = null;
      _errorMessage = null;
      _isRetryable = false;
      notifyListeners();
      LoggerService.info('✅ AAC ticket已重置');
    } catch (e) {
      LoggerService.error('❌ 重置AAC ticket失败', error: e);
      rethrow;
    }
  }

  /// 导出爱安财分数为CSV
  ///
  /// 导出前会强制刷新数据以确保数据最新
  Future<void> exportToCSV() async {
    // 强制刷新数据
    await loadData(forceRefresh: true);

    // 检查数据是否加载成功
    if (_state != AACState.loaded || _creditList == null) {
      throw Exception('数据加载失败，无法导出');
    }

    // 导出CSV
    final exporter = CsvExporter();
    await exporter.exportAACScores(_creditList!);

    LoggerService.info('✅ 爱安财分数CSV导出完成');
  }
}
