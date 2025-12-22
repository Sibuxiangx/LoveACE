import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jwc/course_schedule_record.dart';
import '../models/jwc/plan_category.dart';
import '../models/jwc/plan_completion_info.dart';
import '../models/jwc/plan_option.dart';
import '../models/jwc/smart_course_selection.dart';
import '../models/jwc/student_schedule.dart';
import '../models/jwc/term_item.dart';
import '../services/jwc/jwc_service.dart';
import '../services/logger_service.dart';

/// 智能排课页面状态枚举
enum SmartCourseSelectionState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,

  /// 需要选择培养方案（多培养方案用户）
  needPlanSelection,
}

/// 智能排课状态管理
class SmartCourseSelectionProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 存储键前缀
  static const String _storagePrefix = 'smart_course_selection_';

  /// 当前状态
  SmartCourseSelectionState _state = SmartCourseSelectionState.initial;

  /// 错误消息
  String? _errorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 学期列表
  List<TermItem>? _termList;

  /// 选中的学期代码
  String? _selectedTermCode;

  /// 学生当前课表
  StudentScheduleResponse? _studentSchedule;

  /// 培养方案完成情况
  PlanCompletionInfo? _planCompletion;

  /// 培养方案选项列表（多培养方案用户）
  PlanSelectionResponse? _planSelectionResponse;

  /// 当前选中的培养方案ID
  String? _selectedPlanId;

  /// 智能排课数据（持久化）
  SmartCourseSelectionData? _selectionData;

  /// 当前用户ID（用于检测用户切换）
  String? _currentUserId;

  /// 当前选中的课程（用于右侧详情显示）
  CourseScheduleRecord? _selectedCourse;

  /// 当前选中的时间段（星期几，节次）
  int? _selectedDay;
  int? _selectedSession;

  /// 筛选：校区
  String? _filterCampus;

  /// 筛选：只显示培养方案内课程
  bool _filterPlanOnly = true;

  /// 筛选：隐藏已修课程
  bool _filterHidePassed = true;

  /// 筛选：隐藏已完成分类的课程
  bool _filterHideCompletedCategory = true;

  /// 培养方案课程代码集合（用于快速查找）
  Set<String> _planCourseCodes = {};

  /// 课程代码到培养方案路径的映射
  Map<String, String> _courseCodeToPlanPath = {};

  /// 课程代码到通过状态的映射
  Map<String, bool> _courseCodeToPassed = {};

  /// 课程代码到成绩的映射
  Map<String, String?> _courseCodeToScore = {};

  /// 课程代码到所属分类是否已完成的映射
  Map<String, bool> _courseCodeToCategoryCompleted = {};

  /// 加载进度：已完成页数
  int _loadingProgressCompleted = 0;

  /// 加载进度：总页数
  int _loadingProgressTotal = 0;

  /// 加载进度：已获取记录数
  int _loadingProgressRecords = 0;

  /// 加载进度消息
  String _loadingMessage = '正在加载...';

  // Getters
  SmartCourseSelectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isRetryable => _isRetryable;
  List<TermItem>? get termList => _termList;
  String? get selectedTermCode => _selectedTermCode;
  int get loadingProgressCompleted => _loadingProgressCompleted;
  int get loadingProgressTotal => _loadingProgressTotal;
  int get loadingProgressRecords => _loadingProgressRecords;
  String get loadingMessage => _loadingMessage;
  
  /// 加载进度百分比 (0.0 - 1.0)
  double get loadingProgress {
    if (_loadingProgressTotal <= 0) return 0.0;
    return _loadingProgressCompleted / _loadingProgressTotal;
  }
  StudentScheduleResponse? get studentSchedule => _studentSchedule;
  PlanCompletionInfo? get planCompletion => _planCompletion;
  PlanSelectionResponse? get planSelectionResponse => _planSelectionResponse;
  List<PlanOption> get planOptions => _planSelectionResponse?.options ?? [];
  String? get selectedPlanId => _selectedPlanId;
  bool get hasMultiplePlans => planOptions.length > 1;
  SmartCourseSelectionData? get selectionData => _selectionData;
  CourseScheduleRecord? get selectedCourse => _selectedCourse;
  String? get filterCampus => _filterCampus;
  bool get filterPlanOnly => _filterPlanOnly;
  bool get filterHidePassed => _filterHidePassed;
  bool get filterHideCompletedCategory => _filterHideCompletedCategory;
  int? get selectedDay => _selectedDay;
  int? get selectedSession => _selectedSession;

  /// 开课数据刷新时间
  DateTime? get courseDataRefreshTime => _selectionData?.courseDataRefreshTime;

  /// 可用课程列表
  List<CourseScheduleRecord> get availableCourses =>
      _selectionData?.availableCourses ?? [];

  /// 预设列表
  List<CourseSelectionPreset> get presets => _selectionData?.presets ?? [];

  /// 当前模拟选课的课程（新增的）
  List<String> get currentSelectedCourses =>
      _selectionData?.currentSelectedCourses ?? [];

  /// 模拟退课的课程（从原始课表中移除的）
  List<String> get removedCourses => _selectionData?.removedCourses ?? [];

  /// 基准课表快照
  List<String> get baseScheduleSnapshot =>
      _selectionData?.baseScheduleSnapshot ?? [];

  /// 是否检测到课表变化
  bool _scheduleChanged = false;
  bool get scheduleChanged => _scheduleChanged;

  /// 课表变化详情
  List<String> _addedToSchedule = [];
  List<String> _removedFromSchedule = [];
  List<String> get addedToSchedule => _addedToSchedule;
  List<String> get removedFromSchedule => _removedFromSchedule;

  SmartCourseSelectionProvider(this.jwcService);

  /// 获取存储键
  String _getStorageKey(String userId) => '$_storagePrefix$userId';

  /// 重置所有数据（用户切换时调用）
  void _resetAllData() {
    _selectionData = null;
    _selectedTermCode = null;
    _studentSchedule = null;
    _planCompletion = null;
    _planSelectionResponse = null;
    _selectedPlanId = null;
    _selectedCourse = null;
    _selectedDay = null;
    _selectedSession = null;
    _planCourseCodes.clear();
    _courseCodeToPlanPath.clear();
    _courseCodeToPassed.clear();
    _courseCodeToScore.clear();
    _courseCodeToCategoryCompleted.clear();
    LoggerService.info('🗑️ 智能排课数据已重置');
  }

  /// 初始化数据
  Future<void> initialize(String userId) async {
    // 检测用户切换，如果用户变了，重置所有数据
    if (_currentUserId != null && _currentUserId != userId) {
      LoggerService.info('🔄 检测到用户切换: $_currentUserId -> $userId，重置数据');
      _resetAllData();
    }
    _currentUserId = userId;

    _state = SmartCourseSelectionState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      LoggerService.info('🎯 初始化智能排课数据 (用户: $userId)...');

      // 1. 加载学期列表
      final termResponse = await jwcService.term.getAllTerms();
      if (!termResponse.success || termResponse.data == null) {
        throw Exception(termResponse.error ?? '获取学期列表失败');
      }
      _termList = termResponse.data;
      LoggerService.info('📅 获取到 ${_termList!.length} 个学期');

      // 2. 加载持久化数据
      await _loadPersistedData(userId);

      // 3. 如果没有选中学期，默认选择第一个（当前学期）
      if (_selectedTermCode == null && _termList!.isNotEmpty) {
        _selectedTermCode = _termList!.first.termCode;
      }

      // 4. 加载培养方案（使用 Service 层缓存，不强制刷新）
      final planResponse = await jwcService.plan.getPlanCompletion(
        planId: _selectedPlanId,
        forceRefresh: false,
      );
      
      // 检查是否需要选择培养方案
      if (planResponse.needsSelection) {
        LoggerService.info('📚 检测到多培养方案，需要用户选择');
        _planSelectionResponse = planResponse.selectionData as PlanSelectionResponse;
        _state = SmartCourseSelectionState.needPlanSelection;
        notifyListeners();
        return;
      }
      
      if (planResponse.success && planResponse.data != null) {
        _planCompletion = planResponse.data;
        _buildPlanCourseIndex(); // 构建课程索引
        LoggerService.info('📚 培养方案加载成功，共 ${_planCourseCodes.length} 门课程');
      }

      // 5. 加载学生课表
      if (_selectedTermCode != null) {
        await _loadStudentSchedule(_selectedTermCode!);
      }

      // 6. 如果没有开课数据或数据为空，自动刷新
      if (_selectionData == null || _selectionData!.availableCourses.isEmpty) {
        LoggerService.info('📭 没有开课数据，自动刷新...');
        await _refreshCourseDataInternal(userId);
      }

      // 7. 如果没有课表快照，初始化快照
      if (_selectionData != null &&
          _selectionData!.baseScheduleSnapshot.isEmpty &&
          _studentSchedule != null) {
        LoggerService.info('📸 首次加载，初始化课表快照...');
        await initializeScheduleSnapshot(userId);
      }

      _state = SmartCourseSelectionState.loaded;
      LoggerService.info('✅ 智能排课初始化完成');
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '初始化失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 智能排课初始化失败', error: e);
    }

    notifyListeners();
  }

  /// 选择培养方案并继续初始化
  Future<void> selectPlanAndContinue(String planId, String userId) async {
    LoggerService.info('📚 选择培养方案: $planId');
    _selectedPlanId = planId;
    _state = SmartCourseSelectionState.loading;
    notifyListeners();

    try {
      // 重新加载培养方案（使用 Service 层缓存）
      final planResponse = await jwcService.plan.getPlanCompletion(
        planId: planId,
        forceRefresh: false,
      );
      
      if (!planResponse.success || planResponse.data == null) {
        throw Exception(planResponse.error ?? '获取培养方案失败');
      }

      _planCompletion = planResponse.data;
      _buildPlanCourseIndex();
      LoggerService.info('📚 培养方案加载成功，共 ${_planCourseCodes.length} 门课程');

      // 继续加载学生课表
      if (_selectedTermCode != null) {
        await _loadStudentSchedule(_selectedTermCode!);
      }

      // 如果没有开课数据或数据为空，自动刷新
      if (_selectionData == null || _selectionData!.availableCourses.isEmpty) {
        LoggerService.info('📭 没有开课数据，自动刷新...');
        await _refreshCourseDataInternal(userId);
      }

      _state = SmartCourseSelectionState.loaded;
      LoggerService.info('✅ 智能排课初始化完成');
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '加载培养方案失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 加载培养方案失败', error: e);
    }

    notifyListeners();
  }

  /// 返回培养方案选择页面
  void backToPlanSelection() {
    _state = SmartCourseSelectionState.needPlanSelection;
    _planCompletion = null;
    _planCourseCodes.clear();
    _courseCodeToPlanPath.clear();
    _courseCodeToPassed.clear();
    _courseCodeToScore.clear();
    _courseCodeToCategoryCompleted.clear();
    notifyListeners();
  }

  /// 加载持久化数据
  Future<void> _loadPersistedData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonStr = prefs.getString(key);

      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _selectionData = SmartCourseSelectionData.fromJson(json);
        _selectedTermCode = _selectionData!.termCode;
        LoggerService.info('📦 加载持久化数据成功，学期: $_selectedTermCode');
      } else {
        LoggerService.info('📭 没有持久化数据');
      }
    } catch (e) {
      LoggerService.error('❌ 加载持久化数据失败', error: e);
    }
  }

  /// 保存持久化数据
  Future<void> _savePersistedData(String userId) async {
    if (_selectionData == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final jsonStr = jsonEncode(_selectionData!.toJson());
      await prefs.setString(key, jsonStr);
      LoggerService.info('💾 持久化数据保存成功');
    } catch (e) {
      LoggerService.error('❌ 保存持久化数据失败', error: e);
    }
  }

  /// 加载学生课表并检测变化
  Future<void> _loadStudentSchedule(String termCode) async {
    try {
      LoggerService.info('📅 加载学生课表: $termCode');
      final response =
          await jwcService.studentSchedule.getStudentSchedule(termCode);
      if (response.success && response.data != null) {
        _studentSchedule = response.data;
        LoggerService.info(
            '✅ 学生课表加载成功，共 ${_studentSchedule!.courses.length} 门课');

        // 检测课表变化
        _checkScheduleChanges();
      }
    } catch (e) {
      LoggerService.error('❌ 加载学生课表失败', error: e);
    }
  }

  /// 获取当前课表的课程键列表
  List<String> _getCurrentScheduleKeys() {
    if (_studentSchedule == null) return [];
    return _studentSchedule!.courses
        .map((c) => '${c.courseCode}_${c.courseSequence}')
        .toList();
  }

  /// 检测课表变化
  void _checkScheduleChanges() {
    if (_selectionData == null ||
        _selectionData!.baseScheduleSnapshot.isEmpty) {
      // 没有快照，不需要检测
      _scheduleChanged = false;
      _addedToSchedule = [];
      _removedFromSchedule = [];
      return;
    }

    final currentKeys = _getCurrentScheduleKeys().toSet();
    final snapshotKeys = _selectionData!.baseScheduleSnapshot.toSet();

    // 新增的课程（在当前课表中但不在快照中）
    _addedToSchedule = currentKeys.difference(snapshotKeys).toList();

    // 移除的课程（在快照中但不在当前课表中）
    _removedFromSchedule = snapshotKeys.difference(currentKeys).toList();

    _scheduleChanged =
        _addedToSchedule.isNotEmpty || _removedFromSchedule.isNotEmpty;

    if (_scheduleChanged) {
      LoggerService.warning(
          '⚠️ 检测到课表变化: 新增 ${_addedToSchedule.length} 门, 移除 ${_removedFromSchedule.length} 门');
    }
  }

  /// 切换学期
  Future<void> selectTerm(String termCode, String userId) async {
    if (_selectedTermCode == termCode) return;

    _selectedTermCode = termCode;
    _state = SmartCourseSelectionState.loading;
    notifyListeners();

    try {
      // 加载新学期的课表
      await _loadStudentSchedule(termCode);

      // 更新或创建选课数据（确保 userId 和 termCode 都匹配）
      if (_selectionData == null || 
          _selectionData!.userId != userId || 
          _selectionData!.termCode != termCode) {
        _selectionData = SmartCourseSelectionData.empty(userId, termCode);
      }

      // 自动刷新开课数据
      await _refreshCourseDataInternal(userId);

      await _savePersistedData(userId);

      _state = SmartCourseSelectionState.loaded;
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '切换学期失败: $e';
      _isRetryable = true;
    }

    notifyListeners();
  }

  /// 刷新开课数据（内部方法，不改变状态）
  Future<void> _refreshCourseDataInternal(String userId) async {
    if (_selectedTermCode == null) return;

    try {
      LoggerService.info('🔄 刷新开课数据...');
      
      // 重置进度
      _loadingProgressCompleted = 0;
      _loadingProgressTotal = 0;
      _loadingProgressRecords = 0;
      _loadingMessage = '正在获取开课数据...';
      notifyListeners();

      // 获取学期全部开课数据（带进度回调）
      final response = await jwcService.courseSchedule.queryAllCoursesForTerm(
        termCode: _selectedTermCode!,
        onProgress: (completed, total, records) {
          _loadingProgressCompleted = completed;
          _loadingProgressTotal = total;
          _loadingProgressRecords = records;
          _loadingMessage = '正在获取开课数据 ($completed/$total 页，$records 条)';
          notifyListeners();
        },
      );

      if (!response.success || response.data == null) {
        throw Exception(response.error ?? '获取开课数据失败');
      }

      final allCourses = response.data!;
      LoggerService.info('📊 共获取到 ${allCourses.length} 条开课记录');

      _loadingMessage = '正在保存数据...';
      notifyListeners();

      // 更新数据（确保 userId 匹配）
      if (_selectionData == null || _selectionData!.userId != userId) {
        _selectionData = SmartCourseSelectionData.empty(userId, _selectedTermCode!);
      }
      _selectionData = _selectionData!.copyWith(
        availableCourses: allCourses,
        courseDataRefreshTime: DateTime.now(),
      );

      await _savePersistedData(userId);
      LoggerService.info('✅ 开课数据刷新完成');
    } catch (e) {
      LoggerService.error('❌ 刷新开课数据失败', error: e);
      rethrow;
    }
  }

  /// 刷新开课数据
  Future<void> refreshCourseData(String userId) async {
    if (_selectedTermCode == null) return;

    _state = SmartCourseSelectionState.loading;
    notifyListeners();

    try {
      await _refreshCourseDataInternal(userId);

      _state = SmartCourseSelectionState.loaded;
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '刷新开课数据失败: $e';
      _isRetryable = true;
    }

    notifyListeners();
  }

  /// 模拟选课
  Future<void> addCourse(String courseKey, String userId) async {
    if (_selectionData == null) return;

    final newSelected =
        List<String>.from(_selectionData!.currentSelectedCourses);
    final newRemoved = List<String>.from(_selectionData!.removedCourses);

    // 如果是从 removedCourses 中恢复的课程，从 removedCourses 中移除
    if (newRemoved.contains(courseKey)) {
      newRemoved.remove(courseKey);
      _selectionData = _selectionData!.copyWith(
        removedCourses: newRemoved,
      );
      await _savePersistedData(userId);
      notifyListeners();
      LoggerService.info('🔄 恢复原有课程: $courseKey');
      return;
    }

    // 否则添加到 currentSelectedCourses
    if (!newSelected.contains(courseKey)) {
      newSelected.add(courseKey);
      _selectionData = _selectionData!.copyWith(
        currentSelectedCourses: newSelected,
      );
      await _savePersistedData(userId);
      notifyListeners();
      LoggerService.info('➕ 模拟选课: $courseKey');
    }
  }

  /// 模拟退课
  Future<void> removeCourse(String courseKey, String userId) async {
    if (_selectionData == null) return;

    final newSelected =
        List<String>.from(_selectionData!.currentSelectedCourses);
    final newRemoved = List<String>.from(_selectionData!.removedCourses);

    // 如果是从 currentSelectedCourses 中移除的课程
    if (newSelected.remove(courseKey)) {
      _selectionData = _selectionData!.copyWith(
        currentSelectedCourses: newSelected,
      );
      await _savePersistedData(userId);
      notifyListeners();
      LoggerService.info('➖ 模拟退课（新增课程）: $courseKey');
      return;
    }

    // 如果是从原始课表中移除的课程，添加到 removedCourses
    if (_selectionData!.baseScheduleSnapshot.contains(courseKey) &&
        !newRemoved.contains(courseKey)) {
      newRemoved.add(courseKey);
      _selectionData = _selectionData!.copyWith(
        removedCourses: newRemoved,
      );
      await _savePersistedData(userId);
      notifyListeners();
      LoggerService.info('➖ 模拟退课（原有课程）: $courseKey');
    }
  }

  /// 判断课程是否在当前选课表中（包括原始课表和新增课程，排除已退课程）
  bool isCourseInSchedule(String courseKey) {
    if (_selectionData == null) return false;

    // 在 removedCourses 中的课程不显示
    if (_selectionData!.removedCourses.contains(courseKey)) {
      return false;
    }

    // 在 currentSelectedCourses 中的课程显示
    if (_selectionData!.currentSelectedCourses.contains(courseKey)) {
      return true;
    }

    // 在 baseScheduleSnapshot 中的课程显示
    if (_selectionData!.baseScheduleSnapshot.contains(courseKey)) {
      return true;
    }

    return false;
  }

  /// 判断课程是否是新增的（不在原始课表中）
  bool isCourseAdded(String courseKey) {
    if (_selectionData == null) return false;
    return _selectionData!.currentSelectedCourses.contains(courseKey) &&
        !_selectionData!.baseScheduleSnapshot.contains(courseKey);
  }

  /// 判断课程是否是原始课表中的
  bool isCourseFromOriginalSchedule(String courseKey) {
    if (_selectionData == null) return false;
    return _selectionData!.baseScheduleSnapshot.contains(courseKey) &&
        !_selectionData!.removedCourses.contains(courseKey);
  }

  /// 获取当前有效的选课列表（原始课表 - 退课 + 新增）
  List<String> getEffectiveSelectedCourses() {
    if (_selectionData == null) return [];

    final effective = <String>{};

    // 添加原始课表中的课程
    effective.addAll(_selectionData!.baseScheduleSnapshot);

    // 移除已退课程
    effective.removeAll(_selectionData!.removedCourses);

    // 添加新增课程
    effective.addAll(_selectionData!.currentSelectedCourses);

    return effective.toList();
  }

  /// 选中课程（显示详情）
  void selectCourse(CourseScheduleRecord? course) {
    _selectedCourse = course;
    notifyListeners();
  }

  /// 设置筛选条件
  void setFilter({
    String? campus,
    bool? planOnly,
    bool? hidePassed,
    bool? hideCompletedCategory,
  }) {
    if (campus != null) {
      _filterCampus = campus.isEmpty ? null : campus;
    }
    if (planOnly != null) _filterPlanOnly = planOnly;
    if (hidePassed != null) _filterHidePassed = hidePassed;
    if (hideCompletedCategory != null) _filterHideCompletedCategory = hideCompletedCategory;
    notifyListeners();
  }

  /// 清除筛选条件
  void clearFilter() {
    _filterCampus = null;
    _filterPlanOnly = true;
    _filterHidePassed = true;
    _filterHideCompletedCategory = true;
    notifyListeners();
  }

  /// 初始化课表快照（首次加载或用户确认重置时调用）
  Future<void> initializeScheduleSnapshot(String userId) async {
    if (_selectionData == null || _studentSchedule == null) return;

    final currentKeys = _getCurrentScheduleKeys();

    _selectionData = _selectionData!.copyWith(
      baseScheduleSnapshot: currentKeys,
      snapshotTime: DateTime.now(),
      // 重置选课状态
      currentSelectedCourses: [],
      removedCourses: [],
    );

    // 清除变化标记
    _scheduleChanged = false;
    _addedToSchedule = [];
    _removedFromSchedule = [];

    await _savePersistedData(userId);
    notifyListeners();
    LoggerService.info('📸 课表快照已初始化，共 ${currentKeys.length} 门课');
  }

  /// 接受课表变化（将当前课表作为新的基准）
  Future<void> acceptScheduleChanges(String userId) async {
    if (_selectionData == null || _studentSchedule == null) return;

    final currentKeys = _getCurrentScheduleKeys();
    final newSelected =
        List<String>.from(_selectionData!.currentSelectedCourses);
    final newRemoved = List<String>.from(_selectionData!.removedCourses);

    // 处理移除的课程：如果用户之前手动选了，需要从 currentSelectedCourses 中移除
    for (final key in _removedFromSchedule) {
      newSelected.remove(key);
      newRemoved.remove(key);
    }

    _selectionData = _selectionData!.copyWith(
      baseScheduleSnapshot: currentKeys,
      snapshotTime: DateTime.now(),
      currentSelectedCourses: newSelected,
      removedCourses: newRemoved,
    );

    // 清除变化标记
    _scheduleChanged = false;
    _addedToSchedule = [];
    _removedFromSchedule = [];

    await _savePersistedData(userId);
    notifyListeners();
    LoggerService.info('✅ 已接受课表变化，新基准共 ${currentKeys.length} 门课');
  }

  /// 忽略课表变化（保持用户的选课状态）
  void ignoreScheduleChanges() {
    _scheduleChanged = false;
    // 不清除 _addedToSchedule 和 _removedFromSchedule，下次加载时会重新检测
    notifyListeners();
    LoggerService.info('🙈 已忽略课表变化');
  }

  /// 重置选课（清除所有模拟选课/退课，恢复到当前课表状态）
  Future<void> resetSelection(String userId) async {
    await initializeScheduleSnapshot(userId);
    LoggerService.info('🔄 选课已重置');
  }

  /// 构建培养方案课程索引
  void _buildPlanCourseIndex() {
    _planCourseCodes.clear();
    _courseCodeToPlanPath.clear();
    _courseCodeToPassed.clear();
    _courseCodeToScore.clear();
    _courseCodeToCategoryCompleted.clear();

    if (_planCompletion == null) return;

    void indexCategory(PlanCategory category, String path, bool parentCompleted) {
      final currentPath = path.isEmpty ? category.categoryName : '$path > ${category.categoryName}';
      
      // 检查当前分类是否已完成（所有课程都通过）
      final isCategoryCompleted = parentCompleted || 
          (category.courses.isNotEmpty && category.courses.every((c) => c.isPassed));
      
      for (final course in category.courses) {
        if (course.courseCode.isNotEmpty) {
          _planCourseCodes.add(course.courseCode);
          _courseCodeToPlanPath[course.courseCode] = currentPath;
          _courseCodeToPassed[course.courseCode] = course.isPassed;
          _courseCodeToScore[course.courseCode] = course.score;
          _courseCodeToCategoryCompleted[course.courseCode] = isCategoryCompleted;
        }
      }
      
      for (final sub in category.subcategories) {
        indexCategory(sub, currentPath, isCategoryCompleted);
      }
    }

    for (final category in _planCompletion!.categories) {
      indexCategory(category, '', false);
    }
  }

  /// 检查课程是否在培养方案内
  bool isCourseInPlan(String? courseCode) {
    if (courseCode == null) return false;
    return _planCourseCodes.contains(courseCode);
  }

  /// 获取课程的培养方案路径
  String? getCoursePlanPath(String? courseCode) {
    if (courseCode == null) return null;
    return _courseCodeToPlanPath[courseCode];
  }

  /// 检查课程所属分类是否已完成
  bool isCourseCategoryCompleted(String? courseCode) {
    if (courseCode == null) return false;
    return _courseCodeToCategoryCompleted[courseCode] ?? false;
  }

  /// 检查课程是否已通过
  bool isCoursePassed(String? courseCode) {
    if (courseCode == null) return false;
    return _courseCodeToPassed[courseCode] ?? false;
  }

  /// 获取课程成绩
  String? getCourseScore(String? courseCode) {
    if (courseCode == null) return null;
    return _courseCodeToScore[courseCode];
  }

  /// 获取筛选后的可用课程（只包含培养方案内的课程）
  List<CourseScheduleRecord> get filteredAvailableCourses {
    var courses = availableCourses;

    // 只显示培养方案内的课程
    if (_filterPlanOnly) {
      courses = courses.where((c) => isCourseInPlan(c.kch)).toList();
    }

    // 隐藏已修课程
    if (_filterHidePassed) {
      courses = courses.where((c) => !isCoursePassed(c.kch)).toList();
    }

    // 隐藏已完成分类的课程
    if (_filterHideCompletedCategory) {
      courses = courses.where((c) => !isCourseCategoryCompleted(c.kch)).toList();
    }

    // 校区筛选
    if (_filterCampus != null && _filterCampus!.isNotEmpty) {
      courses = courses.where((c) => c.xqm == _filterCampus).toList();
    }

    // 排序：未修优先，然后按课程名排序
    courses.sort((a, b) {
      final aIsPassed = isCoursePassed(a.kch);
      final bIsPassed = isCoursePassed(b.kch);
      if (aIsPassed != bIsPassed) {
        return aIsPassed ? 1 : -1; // 未修优先
      }
      return (a.kcm ?? '').compareTo(b.kcm ?? '');
    });

    return courses;
  }

  /// 选择时间段
  void selectTimeSlot(int? day, int? session) {
    _selectedDay = day;
    _selectedSession = session;
    notifyListeners();
  }

  /// 获取指定时间段可选的课程
  List<CourseScheduleRecord> getCoursesForTimeSlot(int day, int session) {
    return filteredAvailableCourses.where((c) {
      if (c.skxq != day) return false;
      final startSession = c.skjc ?? 0;
      final endSession = startSession + (c.cxjc ?? 1) - 1;
      return session >= startSession && session <= endSession;
    }).toList();
  }

  /// 检查课程是否在当前学期有开课
  bool isCourseAvailableInTerm(String courseCode) {
    return availableCourses.any((c) => c.kch == courseCode);
  }

  /// 获取课程在当前学期的开课记录
  List<CourseScheduleRecord> getCourseScheduleRecords(String courseCode) {
    return availableCourses.where((c) => c.kch == courseCode).toList();
  }

  /// 获取培养方案中在当前学期有开课的未完成课程数量
  int get availableUncompletedCoursesCount {
    if (_planCompletion == null) return 0;
    
    int count = 0;
    void countCourses(PlanCategory category) {
      for (final course in category.courses) {
        if (!course.isPassed && isCourseAvailableInTerm(course.courseCode)) {
          count++;
        }
      }
      for (final sub in category.subcategories) {
        countCourses(sub);
      }
    }
    
    for (final category in _planCompletion!.categories) {
      countCourses(category);
    }
    return count;
  }

  /// 获取所有校区列表
  List<String> get allCampuses {
    final campuses = availableCourses
        .map((c) => c.xqm)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    campuses.sort();
    return campuses;
  }

  /// 保存预设
  Future<void> savePreset(String name, String userId) async {
    if (_selectionData == null || _selectedTermCode == null) return;

    final preset = CourseSelectionPreset.create(
      name: name,
      termCode: _selectedTermCode!,
      selectedCourses: List.from(_selectionData!.currentSelectedCourses),
    );

    final newPresets = List<CourseSelectionPreset>.from(_selectionData!.presets);
    newPresets.add(preset);

    _selectionData = _selectionData!.copyWith(presets: newPresets);
    await _savePersistedData(userId);
    notifyListeners();

    LoggerService.info('💾 保存预设: $name');
  }

  /// 加载预设
  Future<void> loadPreset(String presetId, String userId) async {
    if (_selectionData == null) return;

    final preset = _selectionData!.presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => throw Exception('预设不存在'),
    );

    _selectionData = _selectionData!.copyWith(
      currentPresetId: presetId,
      currentSelectedCourses: List.from(preset.selectedCourses),
    );

    await _savePersistedData(userId);
    notifyListeners();

    LoggerService.info('📂 加载预设: ${preset.name}');
  }

  /// 删除预设
  Future<void> deletePreset(String presetId, String userId) async {
    if (_selectionData == null) return;

    final newPresets = _selectionData!.presets.where((p) => p.id != presetId).toList();

    _selectionData = _selectionData!.copyWith(
      presets: newPresets,
      currentPresetId: _selectionData!.currentPresetId == presetId
          ? null
          : _selectionData!.currentPresetId,
    );

    await _savePersistedData(userId);
    notifyListeners();

    LoggerService.info('🗑️ 删除预设: $presetId');
  }

  /// 新建选课表（重置到当前课表状态）
  Future<void> newSelectionTable(String userId) async {
    if (_selectionData == null) return;

    // 重新初始化快照，清除所有模拟选课/退课
    await initializeScheduleSnapshot(userId);

    _selectionData = _selectionData!.copyWith(
      currentPresetId: null,
    );

    await _savePersistedData(userId);
    notifyListeners();

    LoggerService.info('🆕 新建选课表（已重置到当前课表状态）');
  }

  /// 检查课程是否与当前课表冲突
  bool checkConflict(CourseScheduleRecord course) {
    final existingSlots = <CourseTimeSlot>[];

    // 从原始课表中获取时间槽（只包含未被退课的）
    if (_studentSchedule != null) {
      for (final existingCourse in _studentSchedule!.courses) {
        final courseKey =
            '${existingCourse.courseCode}_${existingCourse.courseSequence}';
        // 跳过已退课的课程
        if (removedCourses.contains(courseKey)) continue;

        for (final tp in existingCourse.timeAndPlaceList) {
          existingSlots.add(CourseTimeSlot(
            weekday: tp.classDay,
            startSession: tp.classSessions,
            endSession: tp.endSession,
            classWeek: tp.classWeek,
            courseKey: courseKey,
            courseName: existingCourse.courseName,
          ));
        }
      }
    }

    // 添加新增选课的时间槽
    for (final selectedKey in currentSelectedCourses) {
      final selectedCourse = availableCourses.firstWhere(
        (c) => '${c.kch}_${c.kxh}' == selectedKey,
        orElse: () => CourseScheduleRecord(),
      );

      if (selectedCourse.skxq == null) continue;

      existingSlots.add(CourseTimeSlot(
        weekday: selectedCourse.skxq ?? 0,
        startSession: selectedCourse.skjc ?? 0,
        endSession: (selectedCourse.skjc ?? 0) + (selectedCourse.cxjc ?? 1) - 1,
        classWeek: selectedCourse.skzc ?? '',
        courseKey: selectedKey,
        courseName: selectedCourse.kcm ?? '',
      ));
    }

    // 检查新课程是否冲突
    final newSlot = CourseTimeSlot(
      weekday: course.skxq ?? 0,
      startSession: course.skjc ?? 0,
      endSession: (course.skjc ?? 0) + (course.cxjc ?? 1) - 1,
      classWeek: course.skzc ?? '',
      courseKey: '${course.kch}_${course.kxh}',
      courseName: course.kcm ?? '',
    );

    for (final slot in existingSlots) {
      if (slot.courseKey != newSlot.courseKey && slot.conflictsWith(newSlot)) {
        return true;
      }
    }

    return false;
  }
}
