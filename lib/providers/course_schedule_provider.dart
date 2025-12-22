import 'package:flutter/foundation.dart';
import '../models/jwc/course_schedule_record.dart';
import '../services/jwc/course_schedule_service.dart';
import '../services/jwc/jwc_service.dart';
import '../services/logger_service.dart';

/// 课程开课查询状态枚举
enum CourseScheduleState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 学期列表加载状态
enum ScheduleTermState {
  /// 初始状态
  initial,

  /// 加载中
  loading,

  /// 加载完成
  loaded,

  /// 加载失败
  error,
}

/// 课程开课查询排序选项
enum CourseScheduleSortOption {
  /// 默认排序
  defaultOrder,

  /// 按教师排序
  byTeacher,

  /// 按星期排序
  byWeekday,

  /// 按余量排序（从多到少）
  byCapacityDesc,

  /// 按余量排序（从少到多）
  byCapacityAsc,
}

extension CourseScheduleSortOptionExtension on CourseScheduleSortOption {
  String get label {
    switch (this) {
      case CourseScheduleSortOption.defaultOrder:
        return '默认排序';
      case CourseScheduleSortOption.byTeacher:
        return '按教师';
      case CourseScheduleSortOption.byWeekday:
        return '按星期';
      case CourseScheduleSortOption.byCapacityDesc:
        return '余量从多到少';
      case CourseScheduleSortOption.byCapacityAsc:
        return '余量从少到多';
    }
  }
}

/// 课程开课查询状态管理
///
/// 管理课程开课查询的加载、筛选和排序
class CourseScheduleProvider extends ChangeNotifier {
  final JWCService jwcService;

  /// 当前状态
  CourseScheduleState _state = CourseScheduleState.initial;

  /// 学期列表加载状态
  // ignore: prefer_final_fields
  ScheduleTermState _termState = ScheduleTermState.initial;

  /// 学期列表
  List<ScheduleTermItem>? _termList;

  /// 选中的学期代码
  String? _selectedTermCode;

  /// 原始查询结果
  List<CourseScheduleRecord>? _records;

  /// 错误消息
  String? _errorMessage;

  /// 学期列表错误消息
  String? _termErrorMessage;

  /// 是否可重试
  bool _isRetryable = false;

  /// 当前查询的课程号
  String? _currentCourseCode;

  /// 当前查询的学期代码
  String? _currentTermCode;

  /// 筛选：校区
  String? _filterCampus;

  /// 筛选：星期
  int? _filterWeekday;

  /// 筛选：教师（搜索关键词）
  String _filterTeacher = '';

  /// 筛选：只显示有余量的课程
  bool _filterHasCapacity = false;

  /// 排序方式
  CourseScheduleSortOption _sortOption = CourseScheduleSortOption.defaultOrder;

  /// 获取当前状态
  CourseScheduleState get state => _state;

  /// 获取学期列表加载状态
  ScheduleTermState get termState => _termState;

  /// 获取学期列表
  List<ScheduleTermItem>? get termList => _termList;

  /// 获取选中的学期代码
  String? get selectedTermCode => _selectedTermCode;

  /// 获取错误消息
  String? get errorMessage => _errorMessage;

  /// 获取学期列表错误消息
  String? get termErrorMessage => _termErrorMessage;

  /// 获取是否可重试
  bool get isRetryable => _isRetryable;

  /// 获取当前查询的课程号
  String? get currentCourseCode => _currentCourseCode;

  /// 获取当前查询的学期代码
  String? get currentTermCode => _currentTermCode;

  /// 获取筛选后的记录
  List<CourseScheduleRecord> get filteredRecords {
    if (_records == null) return [];

    var result = _records!.where((record) {
      // 校区筛选
      if (_filterCampus != null &&
          _filterCampus!.isNotEmpty &&
          record.xqm != _filterCampus) {
        return false;
      }

      // 星期筛选
      if (_filterWeekday != null && record.skxq != _filterWeekday) {
        return false;
      }

      // 教师筛选
      if (_filterTeacher.isNotEmpty) {
        final teacher = record.teacherName?.toLowerCase() ?? '';
        if (!teacher.contains(_filterTeacher.toLowerCase())) {
          return false;
        }
      }

      // 余量筛选
      if (_filterHasCapacity && (record.bkskyl == null || record.bkskyl! <= 0)) {
        return false;
      }

      return true;
    }).toList();

    // 排序
    switch (_sortOption) {
      case CourseScheduleSortOption.defaultOrder:
        break;
      case CourseScheduleSortOption.byTeacher:
        result.sort((a, b) =>
            (a.teacherName ?? '').compareTo(b.teacherName ?? ''));
      case CourseScheduleSortOption.byWeekday:
        result.sort((a, b) => (a.skxq ?? 0).compareTo(b.skxq ?? 0));
      case CourseScheduleSortOption.byCapacityDesc:
        result.sort((a, b) => (b.bkskyl ?? 0).compareTo(a.bkskyl ?? 0));
      case CourseScheduleSortOption.byCapacityAsc:
        result.sort((a, b) => (a.bkskyl ?? 0).compareTo(b.bkskyl ?? 0));
    }

    return result;
  }

  /// 获取原始记录数量
  int get totalCount => _records?.length ?? 0;

  /// 获取筛选后记录数量
  int get filteredCount => filteredRecords.length;

  /// 获取可用的校区列表
  List<String> get availableCampuses {
    if (_records == null) return [];
    final campuses = _records!
        .map((r) => r.xqm)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    campuses.sort();
    return campuses;
  }

  /// 获取筛选条件
  String? get filterCampus => _filterCampus;
  int? get filterWeekday => _filterWeekday;
  String get filterTeacher => _filterTeacher;
  bool get filterHasCapacity => _filterHasCapacity;
  CourseScheduleSortOption get sortOption => _sortOption;

  /// 是否有活跃的筛选条件
  bool get hasActiveFilters =>
      _filterCampus != null ||
      _filterWeekday != null ||
      _filterTeacher.isNotEmpty ||
      _filterHasCapacity;

  CourseScheduleProvider(this.jwcService);

  /// 加载学期列表
  Future<void> loadTermList() async {
    // 如果已经加载过，不重复加载
    if (_termState == ScheduleTermState.loaded && _termList != null) {
      return;
    }

    _termState = ScheduleTermState.loading;
    _termErrorMessage = null;
    notifyListeners();

    try {
      LoggerService.info('📅 加载开课查询学期列表');

      final response = await jwcService.courseSchedule.getScheduleTerms();

      if (response.success && response.data != null) {
        _termList = response.data;
        _termState = ScheduleTermState.loaded;
        _termErrorMessage = null;

        // 选择最新的学期（根据学期代码排序）
        if (_termList!.isNotEmpty && _selectedTermCode == null) {
          _selectedTermCode = _findLatestTermCode(_termList!);
        }

        LoggerService.info('✅ 学期列表加载成功，共 ${_termList!.length} 个学期，默认选择: $_selectedTermCode');
      } else {
        _termState = ScheduleTermState.error;
        _termErrorMessage = response.error ?? '加载学期列表失败';
        LoggerService.error('❌ 学期列表加载失败: $_termErrorMessage');
      }
    } catch (e) {
      _termState = ScheduleTermState.error;
      _termErrorMessage = '加载学期列表失败: $e';
      LoggerService.error('❌ 学期列表加载异常', error: e);
    }

    notifyListeners();
  }

  /// 根据学期代码找到最新的学期
  /// 学期代码格式: "2025-2026-1-1" (起始年-结束年-学期序号-1)
  /// 学期序号: 1=秋季学期, 2=春季学期
  /// 排序规则: 先按年份降序，再按学期序号降序（秋季在前）
  String _findLatestTermCode(List<ScheduleTermItem> terms) {
    if (terms.isEmpty) return '';

    // 解析学期代码并排序
    final sortedTerms = List<ScheduleTermItem>.from(terms);
    sortedTerms.sort((a, b) {
      final aParts = a.termCode.split('-');
      final bParts = b.termCode.split('-');

      // 解析年份和学期序号
      final aYear = int.tryParse(aParts.isNotEmpty ? aParts[0] : '0') ?? 0;
      final bYear = int.tryParse(bParts.isNotEmpty ? bParts[0] : '0') ?? 0;
      final aSemester = int.tryParse(aParts.length > 2 ? aParts[2] : '0') ?? 0;
      final bSemester = int.tryParse(bParts.length > 2 ? bParts[2] : '0') ?? 0;

      // 先按年份降序
      if (aYear != bYear) {
        return bYear.compareTo(aYear);
      }

      // 年份相同，按学期序号降序（2春季 > 1秋季，但实际上秋季先开始）
      // 实际上 1=秋季 应该在 2=春季 之前（同一学年秋季先开始）
      // 但如果是不同学年，2025-2026-2（春季）比 2025-2026-1（秋季）晚
      return bSemester.compareTo(aSemester);
    });

    return sortedTerms.first.termCode;
  }

  /// 设置选中的学期
  void setSelectedTermCode(String? termCode) {
    _selectedTermCode = termCode;
    notifyListeners();
  }

  /// 查询课程开课情况
  Future<void> queryCourseSchedule({
    required String courseCode,
    required String termCode,
  }) async {
    _state = CourseScheduleState.loading;
    _errorMessage = null;
    _isRetryable = false;
    _currentCourseCode = courseCode;
    _currentTermCode = termCode;
    notifyListeners();

    try {
      LoggerService.info('🔍 查询课程开课情况: $courseCode, 学期: $termCode');

      final response = await jwcService.courseSchedule.queryCourseScheduleAll(
        courseCode: courseCode,
        termCode: termCode,
      );

      if (response.success) {
        _records = response.data;
        _state = CourseScheduleState.loaded;
        _errorMessage = null;
        _isRetryable = false;

        // 重置筛选条件
        _resetFilters();

        LoggerService.info('✅ 查询成功，共 ${_records?.length ?? 0} 条记录');
      } else {
        _state = CourseScheduleState.error;
        _errorMessage = response.error ?? '查询失败';
        _isRetryable = response.retryable;
        LoggerService.error('❌ 查询失败: $_errorMessage');
      }
    } catch (e) {
      _state = CourseScheduleState.error;
      _errorMessage = '查询失败: $e';
      _isRetryable = true;
      LoggerService.error('❌ 查询异常', error: e);
    }

    notifyListeners();
  }

  /// 重置筛选条件
  void _resetFilters() {
    _filterCampus = null;
    _filterWeekday = null;
    _filterTeacher = '';
    _filterHasCapacity = false;
    _sortOption = CourseScheduleSortOption.defaultOrder;
  }

  /// 设置校区筛选
  void setFilterCampus(String? campus) {
    _filterCampus = campus;
    notifyListeners();
  }

  /// 设置星期筛选
  void setFilterWeekday(int? weekday) {
    _filterWeekday = weekday;
    notifyListeners();
  }

  /// 设置教师筛选
  void setFilterTeacher(String teacher) {
    _filterTeacher = teacher;
    notifyListeners();
  }

  /// 设置余量筛选
  void setFilterHasCapacity(bool hasCapacity) {
    _filterHasCapacity = hasCapacity;
    notifyListeners();
  }

  /// 设置排序方式
  void setSortOption(CourseScheduleSortOption option) {
    _sortOption = option;
    notifyListeners();
  }

  /// 清除所有筛选条件
  void clearFilters() {
    _resetFilters();
    notifyListeners();
  }

  /// 重置查询状态（保留学期列表）
  void reset() {
    _state = CourseScheduleState.initial;
    _records = null;
    _errorMessage = null;
    _isRetryable = false;
    _currentCourseCode = null;
    _currentTermCode = null;
    _resetFilters();
    // 不重置学期列表和选中的学期
    notifyListeners();
  }

  /// 完全重置（包括学期列表）
  void fullReset() {
    reset();
    _termState = ScheduleTermState.initial;
    _termList = null;
    _selectedTermCode = null;
    _termErrorMessage = null;
    notifyListeners();
  }
}
