import 'package:flutter/foundation.dart';
import '../models/labor_club/labor_club_progress_info.dart';
import '../models/labor_club/labor_club_activity.dart';
import '../models/labor_club/labor_club_info.dart';
import '../models/labor_club/activity_detail.dart';
import '../models/labor_club/sign_in_request.dart';
import '../models/labor_club/sign_in_response.dart';
import '../services/labor_club/labor_club_service.dart';
import '../services/cache_manager.dart';
import '../services/logger_service.dart';

/// 劳动俱乐部页面状态枚举
enum LaborClubState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 劳动俱乐部状态管理
///
/// 管理劳动俱乐部进度、俱乐部列表、活动列表的加载、刷新和错误处理
/// 提供统一的状态管理和错误处理机制
/// 支持缓存机制，减少不必要的网络请求
class LaborClubProvider extends ChangeNotifier {
  final LaborClubService service;

  /// 缓存键
  static const String _cacheKeyProgress = 'labor_club_progress';
  static const String _cacheKeyClubs = 'labor_club_clubs';
  static const String _cacheKeyJoinedActivities =
      'labor_club_joined_activities';
  static const String _cacheKeyAllActivities = 'labor_club_all_activities';

  /// 缓存有效期（默认30分钟）
  static const Duration _cacheDuration = Duration(minutes: 30);

  /// 当前状态
  LaborClubState _state = LaborClubState.initial;

  /// 劳动修课进度信息
  LaborClubProgressInfo? _progressInfo;

  /// 已加入的俱乐部列表
  List<LaborClubInfo>? _clubs;

  /// 已加入的活动列表
  List<LaborClubActivity>? _joinedActivities;

  /// 所有活动列表（从所有俱乐部聚合）
  List<LaborClubActivity>? _allActivities;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 获取当前状态
  LaborClubState get state => _state;

  /// 获取劳动修课进度信息
  LaborClubProgressInfo? get progressInfo => _progressInfo;

  /// 获取已加入的俱乐部列表
  List<LaborClubInfo>? get clubs => _clubs;

  /// 获取已加入的活动列表
  List<LaborClubActivity>? get joinedActivities => _joinedActivities;

  /// 获取所有活动列表
  List<LaborClubActivity>? get allActivities => _allActivities;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 创建劳动俱乐部Provider实例
  ///
  /// [service] 劳动俱乐部服务实例
  LaborClubProvider(this.service);

  /// 加载劳动俱乐部数据
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
      LoggerService.info('📦 尝试从缓存加载劳动俱乐部数据');

      // 读取进度信息缓存
      final cachedProgress = await CacheManager.get<LaborClubProgressInfo>(
        key: _cacheKeyProgress,
        fromJson: (json) => LaborClubProgressInfo.fromJson(json),
      );

      // 读取俱乐部列表缓存
      final cachedClubsWrapper = await CacheManager.get<Map<String, dynamic>>(
        key: _cacheKeyClubs,
        fromJson: (json) => json,
      );

      List<LaborClubInfo>? cachedClubs;
      if (cachedClubsWrapper != null && cachedClubsWrapper['list'] != null) {
        cachedClubs = (cachedClubsWrapper['list'] as List)
            .map((item) => LaborClubInfo.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      // 读取已加入活动列表缓存
      final cachedJoinedActivitiesWrapper =
          await CacheManager.get<Map<String, dynamic>>(
            key: _cacheKeyJoinedActivities,
            fromJson: (json) => json,
          );

      List<LaborClubActivity>? cachedJoinedActivities;
      if (cachedJoinedActivitiesWrapper != null &&
          cachedJoinedActivitiesWrapper['list'] != null) {
        cachedJoinedActivities = (cachedJoinedActivitiesWrapper['list'] as List)
            .map(
              (item) =>
                  LaborClubActivity.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }

      // 读取所有活动列表缓存
      final cachedAllActivitiesWrapper =
          await CacheManager.get<Map<String, dynamic>>(
            key: _cacheKeyAllActivities,
            fromJson: (json) => json,
          );

      List<LaborClubActivity>? cachedAllActivities;
      if (cachedAllActivitiesWrapper != null &&
          cachedAllActivitiesWrapper['list'] != null) {
        cachedAllActivities = (cachedAllActivitiesWrapper['list'] as List)
            .map(
              (item) =>
                  LaborClubActivity.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }

      // 如果所有缓存都存在，使用缓存数据
      if (cachedProgress != null &&
          cachedClubs != null &&
          cachedJoinedActivities != null &&
          cachedAllActivities != null) {
        _progressInfo = cachedProgress;
        _clubs = cachedClubs;
        _joinedActivities = cachedJoinedActivities;
        _allActivities = cachedAllActivities;
        _state = LaborClubState.loaded;
        _errorMessage = null;
        _isRetryable = false;
        notifyListeners();

        LoggerService.info('✅ 从缓存加载劳动俱乐部数据成功');
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
    _state = LaborClubState.loading;
    _errorMessage = null;
    _isRetryable = false;
    notifyListeners();

    try {
      LoggerService.info('🌐 从网络加载劳动俱乐部数据');

      // 获取劳动修课进度
      final progressResponse = await service.getProgress();

      if (!progressResponse.success) {
        // 进度信息获取失败
        _state = LaborClubState.error;
        _errorMessage = progressResponse.error ?? '获取劳动修课进度失败';
        _isRetryable = progressResponse.retryable;
        notifyListeners();
        return;
      }

      // 获取已加入的俱乐部列表
      final clubsResponse = await service.getJoinedClubs();

      if (!clubsResponse.success) {
        // 俱乐部列表获取失败
        _state = LaborClubState.error;
        _errorMessage = clubsResponse.error ?? '获取俱乐部列表失败';
        _isRetryable = clubsResponse.retryable;
        notifyListeners();
        return;
      }

      // 获取已加入的活动列表
      final joinedActivitiesResponse = await service.getJoinedActivities();

      if (!joinedActivitiesResponse.success) {
        // 已加入活动列表获取失败
        _state = LaborClubState.error;
        _errorMessage = joinedActivitiesResponse.error ?? '获取已加入活动列表失败';
        _isRetryable = joinedActivitiesResponse.retryable;
        notifyListeners();
        return;
      }

      // 并发获取所有已加入活动的签到列表
      final joinedActivities = joinedActivitiesResponse.data ?? [];
      if (joinedActivities.isNotEmpty) {
        LoggerService.info('✍️ 开始并发获取 ${joinedActivities.length} 个活动的签到列表');

        final signListFutures = joinedActivities.map((activity) async {
          try {
            final signListResponse = await service.getSignList(activity.id);
            if (signListResponse.success) {
              activity.signList = signListResponse.data;
              LoggerService.info('✍️ 活动 ${activity.title} 签到列表获取成功');
            } else {
              LoggerService.warning(
                '⚠️ 活动 ${activity.title} 签到列表获取失败: ${signListResponse.error}',
              );
            }
          } catch (e) {
            LoggerService.warning('⚠️ 活动 ${activity.title} 签到列表获取异常: $e');
          }
        });

        // 等待所有签到列表请求完成
        await Future.wait(signListFutures);
        LoggerService.info('✅ 所有签到列表获取完成');
      }

      // 获取所有俱乐部的活动列表
      final allActivitiesList = <LaborClubActivity>[];
      final clubs = clubsResponse.data ?? [];

      for (final club in clubs) {
        final clubActivitiesResponse = await service.getClubActivities(club.id);

        if (clubActivitiesResponse.success) {
          final activities = clubActivitiesResponse.data ?? [];
          allActivitiesList.addAll(activities);
        } else {
          // 如果某个俱乐部的活动获取失败，记录日志但继续处理其他俱乐部
          LoggerService.warning(
            '⚠️ 获取俱乐部 ${club.name} 的活动列表失败: ${clubActivitiesResponse.error}',
          );
        }
      }

      // 所有请求都成功，更新数据
      _progressInfo = progressResponse.data;
      _clubs = clubs;
      _joinedActivities = joinedActivitiesResponse.data ?? [];
      _allActivities = allActivitiesList;
      _state = LaborClubState.loaded;
      _errorMessage = null;
      _isRetryable = false;

      // 保存到缓存
      await _saveToCache();

      notifyListeners();

      LoggerService.info('✅ 从网络加载劳动俱乐部数据成功');
    } catch (e) {
      // 捕获未预期的异常
      _state = LaborClubState.error;
      _errorMessage = '加载数据时发生错误: ${e.toString()}';
      _isRetryable = true; // 未知错误默认可重试
      notifyListeners();

      LoggerService.error('❌ 从网络加载数据失败', error: e);
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      // 保存进度信息
      if (_progressInfo != null) {
        await CacheManager.set(
          key: _cacheKeyProgress,
          data: _progressInfo!,
          duration: _cacheDuration,
          toJson: (info) => info.toJson(),
        );
      }

      // 保存俱乐部列表（包装成Map）
      if (_clubs != null) {
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyClubs,
          data: {'list': _clubs!.map((club) => club.toJson()).toList()},
          duration: _cacheDuration,
          toJson: (d) => d,
        );
      }

      // 保存已加入活动列表（包装成Map）
      if (_joinedActivities != null) {
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyJoinedActivities,
          data: {
            'list': _joinedActivities!
                .map((activity) => activity.toJson())
                .toList(),
          },
          duration: _cacheDuration,
          toJson: (d) => d,
        );
      }

      // 保存所有活动列表（包装成Map）
      if (_allActivities != null) {
        await CacheManager.set<Map<String, dynamic>>(
          key: _cacheKeyAllActivities,
          data: {
            'list': _allActivities!
                .map((activity) => activity.toJson())
                .toList(),
          },
          duration: _cacheDuration,
          toJson: (d) => d,
        );
      }

      LoggerService.info('💾 劳动俱乐部数据已保存到缓存');
    } catch (e) {
      LoggerService.error('❌ 保存数据到缓存失败', error: e);
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    await CacheManager.remove(_cacheKeyProgress);
    await CacheManager.remove(_cacheKeyClubs);
    await CacheManager.remove(_cacheKeyJoinedActivities);
    await CacheManager.remove(_cacheKeyAllActivities);
  }

  /// 刷新劳动俱乐部数据
  ///
  /// 清除缓存并重新从网络加载数据
  Future<void> refresh() async {
    await loadData(forceRefresh: true);
  }

  /// 获取进行中的活动列表
  ///
  /// 已加入且未开始的活动（活动开始时间晚于当前时间）
  List<LaborClubActivity> get ongoingActivities {
    if (_joinedActivities == null) return [];

    final now = DateTime.now();
    return _joinedActivities!.where((activity) {
      try {
        final startTime = DateTime.parse(activity.startTime);
        // 已加入且活动未开始
        return startTime.isAfter(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();
  }

  /// 获取已结束的活动列表
  ///
  /// 已加入且活动已开始的活动（包括进行中和已结束）
  List<LaborClubActivity> get finishedActivities {
    if (_joinedActivities == null) return [];

    final now = DateTime.now();
    return _joinedActivities!.where((activity) {
      try {
        final startTime = DateTime.parse(activity.startTime);
        // 已加入且活动已开始（包括进行中和已结束）
        return startTime.isBefore(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();
  }

  /// 检查活动是否已加入
  ///
  /// [activityId] 活动ID
  bool isActivityJoined(String activityId) {
    if (_joinedActivities == null) return false;
    return _joinedActivities!.any((activity) => activity.id == activityId);
  }

  /// 获取可报名的活动列表
  ///
  /// 当前时间在报名时间段内且人数未满且活动未开始
  List<LaborClubActivity> get availableActivities {
    if (_allActivities == null) return [];

    final now = DateTime.now();
    return _allActivities!.where((activity) {
      try {
        final signUpStartTime = DateTime.parse(activity.signUpStartTime);
        final signUpEndTime = DateTime.parse(activity.signUpEndTime);
        final startTime = DateTime.parse(activity.startTime);
        return signUpStartTime.isBefore(now) &&
            signUpEndTime.isAfter(now) &&
            activity.memberNum < activity.peopleNum &&
            startTime.isAfter(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();
  }

  /// 获取已满员的活动列表
  ///
  /// 当前时间在报名时间段内且人数已满且活动未开始
  List<LaborClubActivity> get fullActivities {
    if (_allActivities == null) return [];

    final now = DateTime.now();
    return _allActivities!.where((activity) {
      try {
        final signUpStartTime = DateTime.parse(activity.signUpStartTime);
        final signUpEndTime = DateTime.parse(activity.signUpEndTime);
        final startTime = DateTime.parse(activity.startTime);
        return signUpStartTime.isBefore(now) &&
            signUpEndTime.isAfter(now) &&
            activity.memberNum >= activity.peopleNum &&
            startTime.isAfter(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();
  }

  /// 获取未开始报名的活动列表
  ///
  /// 报名开始时间晚于当前时间
  List<LaborClubActivity> get notStartedActivities {
    if (_allActivities == null) return [];

    final now = DateTime.now();
    final activities = _allActivities!.where((activity) {
      try {
        final signUpStartTime = DateTime.parse(activity.signUpStartTime);
        return signUpStartTime.isAfter(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();

    // 按报名开始时间排序（从近到远）
    activities.sort((a, b) {
      try {
        final timeA = DateTime.parse(a.signUpStartTime);
        final timeB = DateTime.parse(b.signUpStartTime);
        return timeA.compareTo(timeB);
      } catch (e) {
        return 0;
      }
    });

    return activities;
  }

  /// 获取已过期的活动列表
  ///
  /// 活动开始时间早于当前时间且报名时间已过
  List<LaborClubActivity> get expiredActivities {
    if (_allActivities == null) return [];

    final now = DateTime.now();
    return _allActivities!.where((activity) {
      try {
        final startTime = DateTime.parse(activity.startTime);
        final signUpEndTime = DateTime.parse(activity.signUpEndTime);
        return startTime.isBefore(now) && signUpEndTime.isBefore(now);
      } catch (e) {
        LoggerService.warning('⚠️ 解析活动时间失败: ${activity.id}', error: e);
        return false;
      }
    }).toList();
  }

  /// 报名活动
  ///
  /// [activityId] 活动ID
  /// [reason] 报名理由（可选）
  ///
  /// 返回是否报名成功
  Future<bool> applyActivity(String activityId, {String reason = ''}) async {
    try {
      LoggerService.info('✍️ 正在报名活动: $activityId');

      final response = await service.applyActivity(activityId, reason: reason);

      if (response.success) {
        LoggerService.info('✅ 报名活动成功');
        // 报名成功后，刷新数据
        await refresh();
        return true;
      } else {
        LoggerService.warning('⚠️ 报名活动失败: ${response.error}');
        return false;
      }
    } catch (e) {
      LoggerService.error('❌ 报名活动异常', error: e);
      return false;
    }
  }

  /// 扫码签到
  ///
  /// [qrContent] 二维码内容
  /// [location] 地理位置
  ///
  /// 返回签到响应，无论成功或失败都返回 SignInResponse（除非发生网络异常）
  /// 这样 UI 层可以读取并显示服务器返回的消息
  Future<SignInResponse?> scanSignIn(String qrContent, String location) async {
    try {
      LoggerService.info('📷 正在扫码签到');

      final request = SignInRequest(content: qrContent, location: location);
      final response = await service.scanSignIn(request);

      // 无论成功还是失败，只要有响应数据就返回
      // 这样 UI 可以显示服务器返回的消息
      if (response.data != null) {
        if (response.success) {
          LoggerService.info('✅ 扫码签到成功: ${response.data!.msg}');
        } else {
          LoggerService.warning('⚠️ 扫码签到失败: ${response.data!.msg}');
        }
        return response.data;
      } else {
        LoggerService.warning('⚠️ 扫码签到响应数据为空');
        return null;
      }
    } catch (e) {
      LoggerService.error('❌ 扫码签到异常', error: e);
      return null;
    }
  }

  /// 获取活动详情
  ///
  /// [activityId] 活动ID
  ///
  /// 返回活动详情
  Future<ActivityDetail?> getActivityDetail(String activityId) async {
    try {
      LoggerService.info('📄 正在获取活动详情: $activityId');

      final response = await service.getActivityDetail(activityId);

      if (response.success && response.data != null) {
        final detail = response.data!;

        // 如果签到列表为空，尝试从已加载的活动列表中获取签到信息
        if (detail.signList.isEmpty) {
          LoggerService.info('📝 活动详情中签到列表为空，尝试从已加载的活动中获取');

          // 在已加入的活动列表中查找
          final activity = _joinedActivities?.firstWhere(
            (a) => a.id == activityId,
            orElse: () => LaborClubActivity(id: ''),
          );

          if (activity != null &&
              activity.id.isNotEmpty &&
              activity.signList != null &&
              activity.signList!.isNotEmpty) {
            // 使用已加载的签到列表
            final updatedDetail = ActivityDetail(
              id: detail.id,
              title: detail.title,
              startTime: detail.startTime,
              endTime: detail.endTime,
              chargeUserName: detail.chargeUserName,
              clubName: detail.clubName,
              memberNum: detail.memberNum,
              peopleNum: detail.peopleNum,
              formData: detail.formData,
              flowData: detail.flowData,
              teacherList: detail.teacherList,
              signList: activity.signList!,
              signUpStartTime: detail.signUpStartTime,
              signUpEndTime: detail.signUpEndTime,
            );
            LoggerService.info('✅ 获取活动详情成功，使用已加载的签到列表');
            return updatedDetail;
          }
        }

        LoggerService.info('✅ 获取活动详情成功');
        return detail;
      } else {
        LoggerService.warning('⚠️ 获取活动详情失败: ${response.error}');
        return null;
      }
    } catch (e) {
      LoggerService.error('❌ 获取活动详情异常', error: e);
      return null;
    }
  }
}
