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

  /// 是否正在使用班级课表作为中间课表数据源
  bool _usingClassCurriculum = false;

  /// 当前班级课表名称
  String? _classCurriculumName;

  /// 筛选：校区
  String? _filterCampus;

  /// 筛选：只显示培养方案内课程
  bool _filterPlanOnly = true;

  /// 筛选：只显示不在培养方案内课程
  bool _filterOutOfPlanOnly = false;

  /// 筛选：隐藏已修课程
  bool _filterHidePassed = true;

  /// 筛选：隐藏已完成分类的课程
  bool _filterHideCompletedCategory = true;

  /// 培养方案课程代码集合（用于快速查找）
  final Set<String> _planCourseCodes = {};

  /// 课程代码到培养方案路径的映射
  final Map<String, String> _courseCodeToPlanPath = {};

  /// 课程代码到通过状态的映射
  final Map<String, bool> _courseCodeToPassed = {};

  /// 课程代码到成绩的映射
  final Map<String, String?> _courseCodeToScore = {};

  /// 课程代码到所属分类是否已完成的映射
  final Map<String, bool> _courseCodeToCategoryCompleted = {};

  /// 开课记录索引，避免页面构建时反复全量扫描开课数据。
  List<CourseScheduleRecord>? _indexedAvailableCourses;
  Map<String, List<CourseScheduleRecord>> _availableCoursesByKey = const {};
  Map<String, List<CourseScheduleRecord>> _availableCoursesByCode = const {};
  List<String> _availableCampuses = const [];

  /// 筛选结果缓存，选中课程或时间格时可直接复用。
  List<CourseScheduleRecord>? _filteredCoursesCache;
  Map<(int, int), List<CourseScheduleRecord>> _filteredCoursesByTimeSlotCache =
      const {};

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
    return (_loadingProgressCompleted / _loadingProgressTotal)
        .clamp(0.0, 1.0)
        .toDouble();
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
  bool get filterOutOfPlanOnly => _filterOutOfPlanOnly;
  bool get filterHidePassed => _filterHidePassed;
  bool get filterHideCompletedCategory => _filterHideCompletedCategory;
  int? get selectedDay => _selectedDay;
  int? get selectedSession => _selectedSession;
  bool get usingClassCurriculum => _usingClassCurriculum;
  String? get classCurriculumName => _classCurriculumName;

  /// 开课数据刷新时间
  DateTime? get courseDataRefreshTime => _selectionData?.courseDataRefreshTime;

  /// 可用课程列表
  List<CourseScheduleRecord> get availableCourses =>
      _selectionData?.availableCourses ?? const [];

  /// 班级课表课程列表（仅作为基准课表）
  List<CourseScheduleRecord> get classCurriculumCourses =>
      _selectionData?.classCurriculumCourses ?? [];

  /// 当前模拟选课的课程（新增的）
  List<String> get currentSelectedCourses =>
      _selectionData?.currentSelectedCourses ?? [];

  /// 模拟退课的课程（从原始课表中移除的）
  List<String> get removedCourses => _selectionData?.removedCourses ?? [];

  /// 基准课表快照
  List<String> get baseScheduleSnapshot =>
      _selectionData?.baseScheduleSnapshot ?? [];

  /// 是否检测到课表变化（内部使用）
  bool _scheduleChanged = false;

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
    _usingClassCurriculum = false;
    _classCurriculumName = null;
    _planCourseCodes.clear();
    _courseCodeToPlanPath.clear();
    _courseCodeToPassed.clear();
    _courseCodeToScore.clear();
    _courseCodeToCategoryCompleted.clear();
    _clearAvailableCourseCaches();
    _scheduleChanged = false;
    _addedToSchedule = [];
    _removedFromSchedule = [];
    _loadingProgressCompleted = 0;
    _loadingProgressTotal = 0;
    _loadingProgressRecords = 0;
    _loadingMessage = '正在加载...';
    LoggerService.info('🗑️ 智能排课数据已重置');
  }

  /// 初始化数据
  Future<void> initialize(String userId) async {
    // 检测用户切换，如果用户变了，重置所有数据
    if (_currentUserId != null && _currentUserId != userId) {
      LoggerService.info('🔄 检测到用户切换: $_currentUserId -> $userId，重置数据');
      _resetAllData();
      // 清除旧用户的持久化数据（可选，防止数据混乱）
      await _clearPersistedData(_currentUserId!);
    }
    _currentUserId = userId;

    _state = SmartCourseSelectionState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      LoggerService.info('🎯 初始化智能排课数据 (用户: $userId)...');

      // 1. 加载智能选课学期列表
      // 使用“本学期课程安排”页面的 select#zxjxjhh，确保学期代码与开课查询接口一致。
      final termResponse = await jwcService.courseSchedule.getScheduleTerms();
      if (!termResponse.success || termResponse.data == null) {
        throw Exception(termResponse.error ?? '获取学期列表失败');
      }
      _termList = termResponse.data!
          .map(
            (term) => TermItem(
              termCode: term.termCode,
              termName: term.termName,
              isCurrent: term.isSelected,
            ),
          )
          .toList();
      if (_termList!.length <= 1) {
        final classTermResponse = await jwcService.classCurriculum.getTerms();
        if (classTermResponse.success && classTermResponse.data != null) {
          _termList = classTermResponse.data;
        }
      }
      LoggerService.info('📅 获取到 ${_termList!.length} 个学期');

      // 2. 加载持久化数据
      await _loadPersistedData(userId);

      // 3. 如果没有选中学期，默认选择第一个（当前学期）
      if (_selectedTermCode == null && _termList!.isNotEmpty) {
        TermItem? currentTerm;
        for (final term in _termList!) {
          if (term.isCurrent) {
            currentTerm = term;
            break;
          }
        }
        _selectedTermCode = (currentTerm ?? _termList!.first).termCode;
      }

      // 4. 加载培养方案（使用 Service 层缓存，不强制刷新）
      final planResponse = await jwcService.plan.getPlanCompletion(
        planId: _selectedPlanId,
        forceRefresh: false,
      );

      // 检查是否需要选择培养方案
      if (planResponse.needsSelection) {
        LoggerService.info('📚 检测到多培养方案，需要用户选择');
        _planSelectionResponse =
            planResponse.selectionData as PlanSelectionResponse;
        _state = SmartCourseSelectionState.needPlanSelection;
        notifyListeners();
        return;
      }

      if (!planResponse.success || planResponse.data == null) {
        throw Exception(planResponse.error ?? '获取培养方案失败');
      }

      if (planResponse.data!.categories.isEmpty) {
        throw Exception('培养方案为空，请刷新后重试');
      }

      _planCompletion = planResponse.data;
      _buildPlanCourseIndex(); // 构建课程索引
      LoggerService.info('📚 培养方案加载成功，共 ${_planCourseCodes.length} 门课程');

      // 5. 个人模式加载学生课表；班级模式以班级课表作为基准课表，不同步个人快照
      if (_selectedTermCode != null && !_usingClassCurriculum) {
        await _loadStudentSchedule(_selectedTermCode!, userId);
      }

      // 6. 如果没有开课数据或数据为空，自动刷新
      if (_selectionData == null || _selectionData!.availableCourses.isEmpty) {
        LoggerService.info('📭 没有开课数据，自动刷新...');
        if (_usingClassCurriculum && _selectedTermCode != null) {
          await _ensureAvailableCoursesForTerm(userId, _selectedTermCode!);
          await _savePersistedData(userId);
        } else {
          await _refreshCourseDataInternal(userId);
        }
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

      if (planResponse.data!.categories.isEmpty) {
        throw Exception('培养方案为空，请刷新后重试');
      }

      _planCompletion = planResponse.data;
      _buildPlanCourseIndex();
      LoggerService.info('📚 培养方案加载成功，共 ${_planCourseCodes.length} 门课程');

      // 继续加载学生课表
      if (_selectedTermCode != null && !_usingClassCurriculum) {
        await _loadStudentSchedule(_selectedTermCode!, userId);
      }

      // 如果没有开课数据或数据为空，自动刷新
      if (_selectionData == null || _selectionData!.availableCourses.isEmpty) {
        LoggerService.info('📭 没有开课数据，自动刷新...');
        if (_usingClassCurriculum && _selectedTermCode != null) {
          await _ensureAvailableCoursesForTerm(userId, _selectedTermCode!);
          await _savePersistedData(userId);
        } else {
          await _refreshCourseDataInternal(userId);
        }
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
    _invalidateFilteredCoursesCache();
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
        final restored = SmartCourseSelectionData.fromJson(json);
        _selectionData = restored.copyWith(
          availableCourses: List.unmodifiable(restored.availableCourses),
        );

        // v1.1.7 之前班级课表模式会把 availableCourses 覆盖成班级课表。
        // 迁移时先把旧数据挪到 classCurriculumCourses，后续初始化再补全量开课数据。
        if (_selectionData!.usingClassCurriculum &&
            _selectionData!.classCurriculumCourses.isEmpty &&
            _selectionData!.availableCourses.isNotEmpty) {
          _selectionData = _selectionData!.copyWith(
            availableCourses: const [],
            classCurriculumCourses: _selectionData!.availableCourses,
          );
          LoggerService.info('🔁 已迁移旧版班级课表缓存');
        }

        _rebuildAvailableCourseIndexes();

        _selectedTermCode = _selectionData!.termCode;
        _usingClassCurriculum = _selectionData!.usingClassCurriculum;
        _classCurriculumName = _selectionData!.classCurriculumName;
        LoggerService.info(
          '📦 加载持久化数据成功，学期: $_selectedTermCode，班级课表: $_usingClassCurriculum',
        );
      } else {
        LoggerService.info('📭 没有持久化数据');
      }
    } catch (e) {
      LoggerService.error('❌ 加载持久化数据失败', error: e);
    }
  }

  /// 清除持久化数据
  Future<void> _clearPersistedData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      await prefs.remove(key);
      LoggerService.info('🗑️ 已清除用户 $userId 的持久化数据');
    } catch (e) {
      LoggerService.error('❌ 清除持久化数据失败', error: e);
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

  /// 加载学生课表并自动同步变化
  Future<void> _loadStudentSchedule(String termCode, String userId) async {
    try {
      LoggerService.info('📅 加载学生课表: $termCode');
      final response = await jwcService.studentSchedule.getStudentSchedule(
        termCode,
      );
      if (response.success && response.data != null) {
        _studentSchedule = response.data;
        LoggerService.info(
          '✅ 学生课表加载成功，共 ${_studentSchedule!.courses.length} 门课',
        );

        // 检测并自动同步课表变化
        await _checkAndSyncScheduleChanges(userId);
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

  /// 检测课表变化并自动同步
  /// 当原始课表变化时，自动更新快照并清理无效的模拟选课/退课记录
  Future<void> _checkAndSyncScheduleChanges(String userId) async {
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
        '⚠️ 检测到课表变化: 新增 ${_addedToSchedule.length} 门, 移除 ${_removedFromSchedule.length} 门',
      );

      // 自动同步：更新快照并清理无效记录
      await _autoSyncScheduleChanges(userId);
    }
  }

  /// 自动同步课表变化
  Future<void> _autoSyncScheduleChanges(String userId) async {
    if (_selectionData == null || _studentSchedule == null) return;

    final currentKeys = _getCurrentScheduleKeys();
    final currentKeysSet = currentKeys.toSet();

    // 清理无效的模拟选课记录（已经在实际课表中的课程）
    final newSelected = _selectionData!.currentSelectedCourses
        .where((key) => !currentKeysSet.contains(key))
        .toList();

    // 清理无效的退课记录（已经不在实际课表中的课程）
    final newRemoved = _selectionData!.removedCourses
        .where((key) => currentKeysSet.contains(key))
        .toList();

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
    LoggerService.info('✅ 已自动同步课表变化，新基准共 ${currentKeys.length} 门课');
  }

  /// 切换学期
  Future<void> selectTerm(String termCode, String userId) async {
    if (_selectedTermCode == termCode) return;

    _selectedTermCode = termCode;
    _state = SmartCourseSelectionState.loading;
    notifyListeners();

    try {
      // 更新或创建选课数据（确保 userId 和 termCode 都匹配）
      if (_selectionData == null ||
          _selectionData!.userId != userId ||
          _selectionData!.termCode != termCode) {
        _selectionData = SmartCourseSelectionData.empty(userId, termCode);
        _rebuildAvailableCourseIndexes();
      }

      // 加载新学期的课表
      await _loadStudentSchedule(termCode, userId);

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

  Future<List<CourseScheduleRecord>> _fetchAvailableCoursesForTerm(
    String termCode,
  ) async {
    LoggerService.info('🔄 获取全量开课数据: $termCode');

    final response = await jwcService.courseSchedule.queryAllCoursesForTerm(
      termCode: termCode,
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
    return allCourses;
  }

  Future<void> _ensureAvailableCoursesForTerm(
    String userId,
    String termCode, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _selectionData != null &&
        _selectionData!.userId == userId &&
        _selectionData!.termCode == termCode &&
        _selectionData!.availableCourses.isNotEmpty) {
      return;
    }

    _loadingMessage = '正在获取开课数据...';
    notifyListeners();

    final allCourses = await _fetchAvailableCoursesForTerm(termCode);

    _loadingMessage = '正在保存开课数据...';
    notifyListeners();

    if (_selectionData == null ||
        _selectionData!.userId != userId ||
        _selectionData!.termCode != termCode) {
      _selectionData = SmartCourseSelectionData.empty(userId, termCode);
      _rebuildAvailableCourseIndexes();
    }

    _selectionData = _selectionData!.copyWith(
      termCode: termCode,
      availableCourses: List.unmodifiable(allCourses),
      courseDataRefreshTime: DateTime.now(),
    );
    _rebuildAvailableCourseIndexes();
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

      await _ensureAvailableCoursesForTerm(
        userId,
        _selectedTermCode!,
        forceRefresh: true,
      );

      if (!_usingClassCurriculum) {
        await _loadStudentSchedule(_selectedTermCode!, userId);
        if (_selectionData != null &&
            _selectionData!.baseScheduleSnapshot.isEmpty &&
            _studentSchedule != null) {
          await initializeScheduleSnapshot(userId);
        }
      }

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

  Future<void> _switchToPersonalScheduleInternal(String userId) async {
    if (_selectedTermCode == null) return;

    await _ensureAvailableCoursesForTerm(
      userId,
      _selectedTermCode!,
      forceRefresh: true,
    );

    _selectionData = _selectionData!.copyWith(
      classCurriculumCourses: const [],
      usingClassCurriculum: false,
      classCurriculumName: null,
      classCurriculumCode: null,
      currentSelectedCourses: const [],
      removedCourses: const [],
    );
    _usingClassCurriculum = false;
    _classCurriculumName = null;
    _selectedCourse = null;
    _selectedDay = null;
    _selectedSession = null;

    await _loadStudentSchedule(_selectedTermCode!, userId);
    if (_selectionData != null &&
        _selectionData!.baseScheduleSnapshot.isEmpty &&
        _studentSchedule != null) {
      await initializeScheduleSnapshot(userId);
    }

    await _savePersistedData(userId);
  }

  /// 切换回个人课表作为基准课表。
  ///
  /// 这会改变模拟选课的基准，因此需要清除基于班级课表产生的模拟选课/退课记录。
  Future<void> switchToPersonalSchedule(String userId) async {
    if (_selectedTermCode == null) return;

    _state = SmartCourseSelectionState.loading;
    _loadingProgressCompleted = 0;
    _loadingProgressTotal = 0;
    _loadingProgressRecords = 0;
    _loadingMessage = '正在切换到个人课表...';
    notifyListeners();

    try {
      await _switchToPersonalScheduleInternal(userId);
      _state = SmartCourseSelectionState.loaded;
      LoggerService.info('✅ 已切换为个人课表基准');
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '切换个人课表失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 切换个人课表失败', error: e);
    }

    notifyListeners();
  }

  /// 使用班级课表作为当前基准课表
  Future<void> useClassCurriculum({
    required String userId,
    required String planCode,
    required String classCode,
    required String className,
  }) async {
    _state = SmartCourseSelectionState.loading;
    _loadingProgressCompleted = 0;
    _loadingProgressTotal = 0;
    _loadingProgressRecords = 0;
    _loadingMessage = '正在获取班级课表...';
    notifyListeners();

    try {
      _selectedTermCode = planCode;
      if (_selectionData == null ||
          _selectionData!.userId != userId ||
          _selectionData!.termCode != planCode) {
        _selectionData = SmartCourseSelectionData.empty(userId, planCode);
        _rebuildAvailableCourseIndexes();
      }

      await _ensureAvailableCoursesForTerm(userId, planCode);

      _loadingMessage = '正在获取班级课表...';
      notifyListeners();

      final response = await jwcService.classCurriculum.queryClassCurriculum(
        planCode: planCode,
        classCode: classCode,
      );
      if (!response.success || response.data == null) {
        throw Exception(response.error ?? '获取班级课表失败');
      }

      final courses = response.data!;
      _loadingProgressRecords = courses.length;
      _loadingMessage = '正在保存班级课表...';
      notifyListeners();

      _selectionData = _selectionData!.copyWith(
        termCode: planCode,
        classCurriculumCourses: courses,
        courseDataRefreshTime: DateTime.now(),
        usingClassCurriculum: true,
        classCurriculumName: className,
        classCurriculumCode: classCode,
        currentSelectedCourses: [],
        removedCourses: [],
      );
      _usingClassCurriculum = true;
      _classCurriculumName = className;
      _selectedCourse = null;
      _selectedDay = null;
      _selectedSession = null;

      await _savePersistedData(userId);
      _state = SmartCourseSelectionState.loaded;
      LoggerService.info('✅ 已切换为班级基准课表: $classCode，共 ${courses.length} 条');
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '获取班级课表失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 获取班级课表失败', error: e);
    }

    notifyListeners();
  }

  String _courseKeyFromRecord(CourseScheduleRecord course) {
    return '${course.kch}_${course.kxh}';
  }

  void _clearAvailableCourseCaches() {
    _indexedAvailableCourses = null;
    _availableCoursesByKey = const {};
    _availableCoursesByCode = const {};
    _availableCampuses = const [];
    _filteredCoursesCache = null;
    _filteredCoursesByTimeSlotCache = const {};
  }

  void _invalidateFilteredCoursesCache() {
    _filteredCoursesCache = null;
    _filteredCoursesByTimeSlotCache = const {};
  }

  void _rebuildAvailableCourseIndexes() {
    final courses = availableCourses;
    final byKey = <String, List<CourseScheduleRecord>>{};
    final byCode = <String, List<CourseScheduleRecord>>{};
    final campuses = <String>{};
    for (final course in courses) {
      byKey.putIfAbsent(_courseKeyFromRecord(course), () => []).add(course);
      final courseCode = course.kch;
      if (courseCode != null) {
        byCode.putIfAbsent(courseCode, () => []).add(course);
      }
      final campus = course.xqm;
      if (campus != null && campus.isNotEmpty) {
        campuses.add(campus);
      }
    }

    _availableCoursesByKey = {
      for (final entry in byKey.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _availableCoursesByCode = {
      for (final entry in byCode.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _availableCampuses = List.unmodifiable(campuses.toList()..sort());
    _indexedAvailableCourses = courses;
    _invalidateFilteredCoursesCache();
  }

  void _ensureAvailableCourseIndexes() {
    if (!identical(availableCourses, _indexedAvailableCourses)) {
      _rebuildAvailableCourseIndexes();
    }
  }

  /// 获取同一选课键下的所有开课时间段记录。
  List<CourseScheduleRecord> getAvailableCourseRecordsByKey(String courseKey) {
    _ensureAvailableCourseIndexes();
    return _availableCoursesByKey[courseKey] ?? const [];
  }

  CourseTimeSlot? _timeSlotFromRecord(
    CourseScheduleRecord course,
    String courseKey,
  ) {
    if (course.skxq == null || course.skjc == null) return null;
    return CourseTimeSlot(
      weekday: course.skxq ?? 0,
      startSession: course.skjc ?? 0,
      endSession: (course.skjc ?? 0) + (course.cxjc ?? 1) - 1,
      classWeek: course.skzc ?? '',
      courseKey: courseKey,
      courseName: course.kcm ?? '',
    );
  }

  bool _isClassCurriculumCourse(String courseKey) {
    return _usingClassCurriculum &&
        classCurriculumCourses.any((course) {
          return _courseKeyFromRecord(course) == courseKey;
        });
  }

  /// 模拟选课
  Future<void> addCourse(String courseKey, String userId) async {
    if (_selectionData == null) return;

    final newSelected = List<String>.from(
      _selectionData!.currentSelectedCourses,
    );
    final newRemoved = List<String>.from(_selectionData!.removedCourses);

    // 如果是从 removedCourses 中恢复的课程，从 removedCourses 中移除
    if (newRemoved.contains(courseKey)) {
      newRemoved.remove(courseKey);
      _selectionData = _selectionData!.copyWith(removedCourses: newRemoved);
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

    final newSelected = List<String>.from(
      _selectionData!.currentSelectedCourses,
    );
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
    if (((_usingClassCurriculum && _isClassCurriculumCourse(courseKey)) ||
            (!_usingClassCurriculum &&
                _selectionData!.baseScheduleSnapshot.contains(courseKey))) &&
        !newRemoved.contains(courseKey)) {
      newRemoved.add(courseKey);
      _selectionData = _selectionData!.copyWith(removedCourses: newRemoved);
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

    if (_usingClassCurriculum) {
      return _isClassCurriculumCourse(courseKey);
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
    if (_usingClassCurriculum) {
      return _isClassCurriculumCourse(courseKey) &&
          !_selectionData!.removedCourses.contains(courseKey);
    }
    return _selectionData!.baseScheduleSnapshot.contains(courseKey) &&
        !_selectionData!.removedCourses.contains(courseKey);
  }

  /// 获取当前有效的选课列表（原始课表 - 退课 + 新增）
  List<String> getEffectiveSelectedCourses() {
    if (_selectionData == null) return [];

    final effective = <String>{};

    // 添加原始课表中的课程
    if (_usingClassCurriculum) {
      effective.addAll(classCurriculumCourses.map(_courseKeyFromRecord));
    } else {
      effective.addAll(_selectionData!.baseScheduleSnapshot);
    }

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

  /// 同时选中课程与时间段，避免一次课表点击触发两次页面重建。
  void selectCourseAtTimeSlot(
    CourseScheduleRecord? course,
    int day,
    int session,
  ) {
    _selectedCourse = course;
    _selectedDay = day;
    _selectedSession = session;
    notifyListeners();
  }

  /// 设置筛选条件
  void setFilter({
    String? campus,
    bool? planOnly,
    bool? outOfPlanOnly,
    bool? hidePassed,
    bool? hideCompletedCategory,
  }) {
    if (campus != null) {
      _filterCampus = campus.isEmpty ? null : campus;
    }
    if (planOnly != null) {
      _filterPlanOnly = planOnly;
      if (planOnly) _filterOutOfPlanOnly = false;
    }
    if (outOfPlanOnly != null) {
      _filterOutOfPlanOnly = outOfPlanOnly;
      if (outOfPlanOnly) _filterPlanOnly = false;
    }
    if (hidePassed != null) _filterHidePassed = hidePassed;
    if (hideCompletedCategory != null) {
      _filterHideCompletedCategory = hideCompletedCategory;
    }
    _invalidateFilteredCoursesCache();
    notifyListeners();
  }

  /// 清除筛选条件
  void clearFilter() {
    _filterCampus = null;
    _filterPlanOnly = true;
    _filterOutOfPlanOnly = false;
    _filterHidePassed = true;
    _filterHideCompletedCategory = true;
    _invalidateFilteredCoursesCache();
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

  /// 重置选课（清除所有模拟选课/退课，从服务器重新获取课表）
  Future<void> resetSelection(String userId) async {
    if (_selectedTermCode == null) return;

    _state = SmartCourseSelectionState.loading;
    _loadingMessage = '正在重置课表...';
    notifyListeners();

    try {
      // 班级课表模式：重新拉取班级课表
      if (_usingClassCurriculum &&
          _selectionData?.classCurriculumCode != null) {
        LoggerService.info('🔄 重置课表：重新拉取班级课表...');
        final classCode = _selectionData!.classCurriculumCode!;
        final className = _selectionData!.classCurriculumName;
        final planCode = _selectedTermCode!;
        final response = await jwcService.classCurriculum.queryClassCurriculum(
          planCode: planCode,
          classCode: classCode,
        );
        if (!response.success || response.data == null) {
          throw Exception(response.error ?? '获取班级课表失败');
        }

        final courses = response.data!;
        await _ensureAvailableCoursesForTerm(userId, planCode);
        _selectionData = _selectionData!.copyWith(
          termCode: planCode,
          classCurriculumCourses: courses,
          courseDataRefreshTime: DateTime.now(),
          usingClassCurriculum: true,
          classCurriculumName: className,
          classCurriculumCode: classCode,
          currentSelectedCourses: [],
          removedCourses: [],
        );
        _scheduleChanged = false;
        _addedToSchedule = [];
        _removedFromSchedule = [];

        await _savePersistedData(userId);
        _state = SmartCourseSelectionState.loaded;
        LoggerService.info('✅ 班级课表已刷新，共 ${courses.length} 条');
        notifyListeners();
        return;
      }

      // 1. 从服务器重新获取最新课表
      LoggerService.info('🔄 重置课表：从服务器获取最新课表...');
      final response = await jwcService.studentSchedule.getStudentSchedule(
        _selectedTermCode!,
      );
      if (response.success && response.data != null) {
        _studentSchedule = response.data;
        LoggerService.info(
          '✅ 获取最新课表成功，共 ${_studentSchedule!.courses.length} 门课',
        );
      } else {
        throw Exception(response.error ?? '获取课表失败');
      }

      // 2. 重新初始化快照
      await initializeScheduleSnapshot(userId);

      _state = SmartCourseSelectionState.loaded;
      LoggerService.info('🔄 选课已重置');
    } catch (e) {
      _state = SmartCourseSelectionState.error;
      _errorMessage = '重置课表失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 重置课表失败', error: e);
    }

    notifyListeners();
  }

  /// 构建培养方案课程索引
  void _buildPlanCourseIndex() {
    _planCourseCodes.clear();
    _courseCodeToPlanPath.clear();
    _courseCodeToPassed.clear();
    _courseCodeToScore.clear();
    _courseCodeToCategoryCompleted.clear();
    _invalidateFilteredCoursesCache();

    if (_planCompletion == null) return;

    void indexCategory(
      PlanCategory category,
      String path,
      bool parentCompleted,
    ) {
      final currentPath = path.isEmpty
          ? category.categoryName
          : '$path > ${category.categoryName}';

      // 检查当前分类是否已完成：
      // 1. 任一父分类已完成，则子树内课程都属于已完成分类
      // 2. 当前分类有最低学分要求且已达标
      // 3. 无学分要求的叶子课程组，所有直接课程都已通过
      final isCategoryCompleted =
          parentCompleted ||
          (category.minCredits > 0 &&
              category.completedCredits >= category.minCredits) ||
          (category.courses.isNotEmpty &&
              category.subcategories.isEmpty &&
              category.courses.every((c) => c.isPassed));

      for (final course in category.courses) {
        if (course.courseCode.isNotEmpty) {
          _planCourseCodes.add(course.courseCode);
          _courseCodeToPlanPath[course.courseCode] = currentPath;
          _courseCodeToPassed[course.courseCode] = course.isPassed;
          _courseCodeToScore[course.courseCode] = course.score;
          _courseCodeToCategoryCompleted[course.courseCode] =
              (_courseCodeToCategoryCompleted[course.courseCode] ?? false) ||
              isCategoryCompleted;
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

  /// 获取筛选后的可用课程
  List<CourseScheduleRecord> get filteredAvailableCourses {
    _ensureAvailableCourseIndexes();
    final cached = _filteredCoursesCache;
    if (cached != null) return cached;

    var courses = List<CourseScheduleRecord>.from(availableCourses);

    // 只显示培养方案内的课程
    if (_filterPlanOnly) {
      courses = courses.where((c) => isCourseInPlan(c.kch)).toList();
    }

    // 只显示不在培养方案内的课程
    if (_filterOutOfPlanOnly) {
      courses = courses.where((c) => !isCourseInPlan(c.kch)).toList();
    }

    // 隐藏已修课程
    if (_filterHidePassed) {
      courses = courses.where((c) => !isCoursePassed(c.kch)).toList();
    }

    // 隐藏已完成分类的课程
    if (_filterHideCompletedCategory) {
      courses = courses
          .where((c) => !isCourseCategoryCompleted(c.kch))
          .toList();
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

    final result = List<CourseScheduleRecord>.unmodifiable(courses);
    final byTimeSlot = <(int, int), List<CourseScheduleRecord>>{};
    for (final course in result) {
      final day = course.skxq;
      if (day == null) continue;

      final startSession = course.skjc ?? 0;
      final endSession = startSession + (course.cxjc ?? 1) - 1;
      for (var session = startSession; session <= endSession; session++) {
        byTimeSlot.putIfAbsent((day, session), () => []).add(course);
      }
    }

    _filteredCoursesCache = result;
    _filteredCoursesByTimeSlotCache = {
      for (final entry in byTimeSlot.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    return result;
  }

  /// 选择时间段
  void selectTimeSlot(int? day, int? session) {
    _selectedDay = day;
    _selectedSession = session;
    notifyListeners();
  }

  /// 获取指定时间段可选的课程
  List<CourseScheduleRecord> getCoursesForTimeSlot(int day, int session) {
    filteredAvailableCourses;
    return _filteredCoursesByTimeSlotCache[(day, session)] ?? const [];
  }

  /// 检查课程是否在当前学期有开课
  bool isCourseAvailableInTerm(String courseCode) {
    _ensureAvailableCourseIndexes();
    return _availableCoursesByCode.containsKey(courseCode);
  }

  /// 获取课程在当前学期的开课记录
  List<CourseScheduleRecord> getCourseScheduleRecords(String courseCode) {
    _ensureAvailableCourseIndexes();
    return _availableCoursesByCode[courseCode] ?? const [];
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
    _ensureAvailableCourseIndexes();
    return _availableCampuses;
  }

  /// 检查课程是否与当前课表冲突
  bool checkConflict(CourseScheduleRecord course) {
    final existingSlots = <CourseTimeSlot>[];

    // 班级模式下以班级课表作为基准课表；个人模式下以个人课表作为基准课表。
    if (_usingClassCurriculum) {
      for (final existingCourse in classCurriculumCourses) {
        final courseKey = _courseKeyFromRecord(existingCourse);
        if (removedCourses.contains(courseKey)) continue;
        if (existingCourse.skxq == null || existingCourse.skjc == null) {
          continue;
        }

        existingSlots.add(
          CourseTimeSlot(
            weekday: existingCourse.skxq ?? 0,
            startSession: existingCourse.skjc ?? 0,
            endSession:
                (existingCourse.skjc ?? 0) + (existingCourse.cxjc ?? 1) - 1,
            classWeek: existingCourse.skzc ?? '',
            courseKey: courseKey,
            courseName: existingCourse.kcm ?? '',
          ),
        );
      }
    } else if (_studentSchedule != null) {
      for (final existingCourse in _studentSchedule!.courses) {
        final courseKey =
            '${existingCourse.courseCode}_${existingCourse.courseSequence}';
        // 跳过已退课的课程
        if (removedCourses.contains(courseKey)) continue;

        for (final tp in existingCourse.timeAndPlaceList) {
          existingSlots.add(
            CourseTimeSlot(
              weekday: tp.classDay,
              startSession: tp.classSessions,
              endSession: tp.endSession,
              classWeek: tp.classWeek,
              courseKey: courseKey,
              courseName: existingCourse.courseName,
            ),
          );
        }
      }
    }

    // 添加新增选课的时间槽
    for (final selectedKey in currentSelectedCourses) {
      for (final selectedCourse in getAvailableCourseRecordsByKey(
        selectedKey,
      )) {
        final slot = _timeSlotFromRecord(selectedCourse, selectedKey);
        if (slot != null) existingSlots.add(slot);
      }
    }

    // 检查新课程是否冲突。同一课程号_课序号可能有多条时间段记录，需作为同一门课整体检查。
    final newCourseKey = _courseKeyFromRecord(course);
    final newCourseRecords = getAvailableCourseRecordsByKey(newCourseKey);
    final newSlots = (newCourseRecords.isEmpty ? [course] : newCourseRecords)
        .map((record) => _timeSlotFromRecord(record, newCourseKey))
        .whereType<CourseTimeSlot>()
        .toList();

    for (final newSlot in newSlots) {
      for (final slot in existingSlots) {
        if (slot.courseKey != newSlot.courseKey &&
            slot.conflictsWith(newSlot)) {
          return true;
        }
      }
    }

    return false;
  }
}
