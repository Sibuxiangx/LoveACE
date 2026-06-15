import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';

/// 固定功能管理器 Provider
///
/// 管理用户在首页固定的功能列表
/// 最多支持固定 3 个功能
class PinnedFeaturesProvider extends ChangeNotifier {
  static const String _storageKey = 'pinned_features';
  static const int maxPinnedCount = 3;

  List<String> _pinnedFeatureIds = [];

  /// 已固定的功能 ID 列表
  List<String> get pinnedFeatureIds => _pinnedFeatureIds;

  /// 是否已固定指定功能
  bool isPinned(String featureId) {
    return _pinnedFeatureIds.contains(featureId);
  }

  /// 是否可以继续固定功能
  bool get canPinMore => _pinnedFeatureIds.length < maxPinnedCount;

  /// 已固定功能数量
  int get pinnedCount => _pinnedFeatureIds.length;

  PinnedFeaturesProvider() {
    _loadPinnedFeatures();
  }

  /// 从本地存储加载固定功能列表
  Future<void> _loadPinnedFeatures() async {
    try {
      LoggerService.info('📌 加载固定功能列表');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_storageKey);

      if (stored != null) {
        _pinnedFeatureIds = stored;
        LoggerService.info('✅ 加载固定功能成功，共 ${_pinnedFeatureIds.length} 个');
      } else {
        LoggerService.info('📭 没有固定功能');
      }

      notifyListeners();
    } catch (e) {
      LoggerService.error('❌ 加载固定功能失败', error: e);
    }
  }

  /// 保存固定功能列表到本地存储
  Future<void> _savePinnedFeatures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, _pinnedFeatureIds);
      LoggerService.info('💾 保存固定功能成功');
    } catch (e) {
      LoggerService.error('❌ 保存固定功能失败', error: e);
    }
  }

  /// 固定功能
  ///
  /// 返回 true 表示固定成功，false 表示已达到上限或已固定
  Future<bool> pinFeature(String featureId) async {
    if (_pinnedFeatureIds.contains(featureId)) {
      LoggerService.warning('⚠️ 功能已固定: $featureId');
      return false;
    }

    if (_pinnedFeatureIds.length >= maxPinnedCount) {
      LoggerService.warning('⚠️ 已达到固定功能上限 ($maxPinnedCount)');
      return false;
    }

    _pinnedFeatureIds.add(featureId);
    await _savePinnedFeatures();
    notifyListeners();

    LoggerService.info('📌 固定功能成功: $featureId');
    return true;
  }

  /// 取消固定功能
  Future<void> unpinFeature(String featureId) async {
    if (!_pinnedFeatureIds.contains(featureId)) {
      LoggerService.warning('⚠️ 功能未固定: $featureId');
      return;
    }

    _pinnedFeatureIds.remove(featureId);
    await _savePinnedFeatures();
    notifyListeners();

    LoggerService.info('📌 取消固定功能: $featureId');
  }

  /// 切换固定状态
  Future<bool> togglePin(String featureId) async {
    if (isPinned(featureId)) {
      await unpinFeature(featureId);
      return false;
    } else {
      return await pinFeature(featureId);
    }
  }

  /// 清除所有固定功能
  Future<void> clearAll() async {
    _pinnedFeatureIds.clear();
    await _savePinnedFeatures();
    notifyListeners();

    LoggerService.info('🗑️ 清除所有固定功能');
  }
}
