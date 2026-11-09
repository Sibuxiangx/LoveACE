import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jwc/teacher_evaluation.dart';
import '../services/jwc/teacher_evaluation_service.dart';

enum TeacherEvaluationState { initial, loading, loaded, closed, error }
enum TeacherEvaluationTaskStatus { pending, preparing, waiting, submitting, verifying, success, failed, cancelled }

class TeacherEvaluationTaskState {
  final TeacherEvaluationCourse course;
  final TeacherEvaluationTaskStatus status;
  final String message;
  final int countdownSeconds;
  /// 轻量错误分类：prepareFailed / submitFailed / verifyMismatch / verifyUnknown / unknown
  final String errorKind;

  const TeacherEvaluationTaskState({
    required this.course,
    this.status = TeacherEvaluationTaskStatus.pending,
    this.message = '等待开始',
    this.countdownSeconds = 0,
    this.errorKind = '',
  });

  TeacherEvaluationTaskState copyWith({
    TeacherEvaluationTaskStatus? status,
    String? message,
    int? countdownSeconds,
    String? errorKind,
  }) =>
      TeacherEvaluationTaskState(
        course: course,
        status: status ?? this.status,
        message: message ?? this.message,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        errorKind: errorKind ?? this.errorKind,
      );
}

class TeacherEvaluationProvider extends ChangeNotifier {
  final TeacherEvaluationService service;
  int _runId = 0;
  TeacherEvalScoreMode _scoreMode = TeacherEvalScoreMode.random;

  TeacherEvaluationState _state = TeacherEvaluationState.initial;
  bool _isRunning = false;
  String _closedMessage = '';
  String? _errorMessage;
  List<TeacherEvaluationCourse> _courses = [];
  List<TeacherEvaluationTaskState> _tasks = [];
  List<String> _logs = [];

  TeacherEvaluationProvider(this.service) {
    _loadScoreMode();
  }

  TeacherEvalScoreMode get scoreMode => _scoreMode;

  /// 保存评分方式；运行中的批次已在开始时取得自己的模式，不受影响
  Future<void> setScoreMode(TeacherEvalScoreMode mode) async {
    if (_scoreMode == mode) return;
    _scoreMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scoreModeKey, mode.name);
  }

  Future<void> _loadScoreMode() async {
    final prefs = await SharedPreferences.getInstance();
    _scoreMode = TeacherEvalScoreMode.fromStored(prefs.getString(_scoreModeKey));
    notifyListeners();
  }

  TeacherEvaluationState get state => _state;
  bool get isRunning => _isRunning;
  String get closedMessage => _closedMessage;
  String? get errorMessage => _errorMessage;
  List<TeacherEvaluationCourse> get courses => _courses;
  List<TeacherEvaluationTaskState> get tasks => _tasks;
  List<String> get logs => _logs;
  List<TeacherEvaluationCourse> get pendingCourses => _courses.where((course) => !course.isEvaluated).toList();
  int get evaluatedCount => _courses.where((course) => course.isEvaluated).length;

  Future<void> load() async {
    stop(resetRunning: false);
    _state = TeacherEvaluationState.loading;
    _errorMessage = null;
    _closedMessage = '';
    _tasks = [];
    notifyListeners();

    final result = await service.loadCourses();
    final data = result.data;
    if (!result.success || data == null) {
      _state = TeacherEvaluationState.error;
      _errorMessage = result.error ?? '获取评教课程失败';
      _addLog(_errorMessage!);
      notifyListeners();
      return;
    }

    if (data.isClosed) {
      _state = TeacherEvaluationState.closed;
      _closedMessage = data.closedMessage.isNotEmpty ? data.closedMessage : '评价暂未开启';
      _courses = [];
      _tasks = [];
      _addLog('评价暂未开启');
      notifyListeners();
      return;
    }

    _state = TeacherEvaluationState.loaded;
    _courses = data.courses;
    _tasks = [];
    _errorMessage = null;
    _addLog('已加载 ${data.courses.length} 门课程，待评 ${pendingCourses.length} 门');
    notifyListeners();
  }

  Future<void> startBatch() async {
    final pending = pendingCourses;
    if (_isRunning || pending.isEmpty) return;
    final scoreMode = _scoreMode;

    final runId = ++_runId;
    _isRunning = true;
    _tasks = pending.map((course) => TeacherEvaluationTaskState(course: course)).toList();
    _errorMessage = null;
    _addLog('批量评教已启动，请保持 App 前台；已提交评价无法撤回');
    notifyListeners();

    try {
      await _runRound(runId, pending, scoreMode);
      if (!_isCurrentRun(runId)) return;

      // 批后补偿：仅当存在 prepareFailed/submitFailed 失败课程，且列表刷新成功时才进行
      if (!_tasks.any(_isRetryableFailure)) return;
      if (!await _refreshAfterBatch() || !_isCurrentRun(runId)) return;
      final retryCourses = _collectRetryCourses();
      if (retryCourses.isEmpty) {
        _addLog('批后补偿：失败课程刷新后均已确认已评，无需重试');
        return;
      }
      _addLog('批后补偿：${retryCourses.length} 门课程将自动重试一轮');
      notifyListeners();
      await _runRound(runId, retryCourses, scoreMode);
      if (_isCurrentRun(runId)) await _refreshAfterBatch();
    } finally {
      if (_isCurrentRun(runId)) {
        _isRunning = false;
        notifyListeners();
      }
    }
  }

  /// 按标准间隔启动一轮任务并等待全部完成
  Future<void> _runRound(
    int runId,
    List<TeacherEvaluationCourse> courses,
    TeacherEvalScoreMode scoreMode,
  ) async {
    final futures = <Future<void>>[];
    for (var i = 0; i < courses.length; i++) {
      if (!_isCurrentRun(runId)) break;
      if (i > 0) await Future.delayed(_startInterval);
      if (!_isCurrentRun(runId)) break;
      futures.add(_runTask(runId, courses[i], courses.length, scoreMode));
    }
    await Future.wait(futures);
  }

  /// 收集失败课程，剔除刷新后已确认已评的，并把剩余任务重置为待重试
  List<TeacherEvaluationCourse> _collectRetryCourses() {
    final refreshed = _courses;
    final retryCourses = _tasks
        .where(_isRetryableFailure)
        .map((task) => task.course)
        .where((course) {
      final refreshedCourse = refreshed.firstWhere(
        (item) => item.matches(course),
        orElse: () => course,
      );
      return !refreshedCourse.isEvaluated;
    }).toList();
    if (retryCourses.isNotEmpty) {
      _tasks = _tasks.map((task) {
        if (task.status == TeacherEvaluationTaskStatus.failed &&
            retryCourses.any((item) => item.matches(task.course))) {
          return task.copyWith(
            status: TeacherEvaluationTaskStatus.pending,
            message: '批后重试等待中',
            errorKind: '',
          );
        }
        return task;
      }).toList();
    }
    return retryCourses;
  }

  bool _isRetryableFailure(TeacherEvaluationTaskState task) =>
      task.status == TeacherEvaluationTaskStatus.failed && _retryableErrorKinds.contains(task.errorKind);

  void stop({bool resetRunning = true}) {
    _runId++;
    if (!resetRunning) return;
    _isRunning = false;
    _tasks = _tasks.map((task) {
      if (task.status.isActive) {
        return task.copyWith(
          status: TeacherEvaluationTaskStatus.cancelled,
          message: '已停止',
          countdownSeconds: 0,
        );
      }
      return task;
    }).toList();
    _addLog('批量评教已停止；已提交的评价不会撤回');
    notifyListeners();
  }

  Future<void> _runTask(
    int runId,
    TeacherEvaluationCourse course,
    int pendingCount,
    TeacherEvalScoreMode scoreMode,
  ) async {
    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.preparing, '正在访问评价页并生成表单');
    var prepare = await service.prepareEvaluation(course, pendingCount, scoreMode);
    if (!prepare.success && prepare.retryable) {
      // 瞬时失败（网络抖动/HTTP 5xx）立即重试一次
      _addLog('${course.displayName} 准备失败，立即重试一次');
      _updateTask(course, TeacherEvaluationTaskStatus.preparing, '准备失败，立即重试');
      prepare = await service.prepareEvaluation(course, pendingCount, scoreMode);
    }
    if (!_isCurrentRun(runId)) return;
    final firstPrepared = prepare.data;
    if (!prepare.success || firstPrepared == null) {
      _failTask(course, prepare.error ?? '准备评价表单失败', errorKind: 'prepareFailed');
      return;
    }

    // 最多提交两次；提交结果不确定时先核实，核实失败或第二次仍未生效即结束，绝不再次提交
    var prepared = firstPrepared;
    for (var attempt = 1; ; attempt++) {
      final isRetry = attempt > 1;
      await _awaitSubmitWait(runId, course, isRetry ? '重试等待提交' : '等待提交');
      if (!_isCurrentRun(runId)) return;
      _updateTask(course, TeacherEvaluationTaskStatus.submitting, isRetry ? '正在重新提交评价' : '正在提交评价');
      final submit = await service.submitEvaluation(prepared);
      if (!_isCurrentRun(runId)) return;
      if (submit.success && submit.data?.success == true) break;

      _updateTask(course, TeacherEvaluationTaskStatus.verifying, '提交结果不确定，正在核实');
      final check = await service.verifyCourseEvaluated(course);
      if (!_isCurrentRun(runId)) return;
      if (!check.success) {
        _failTask(course, '提交结果无法核实，未重新提交，请稍后刷新查看', errorKind: 'verifyUnknown');
        return;
      }
      if (check.data == true) {
        _updateTask(course, TeacherEvaluationTaskStatus.success, '提交成功（响应异常，服务器已确认）');
        _addLog('${course.displayName} 提交成功（响应异常，已核实）');
        return;
      }
      if (isRetry) {
        _failTask(course, submit.data?.message ?? submit.error ?? '提交评价失败', errorKind: 'submitFailed');
        return;
      }

      // 服务器确认未记录：重新准备（每次取新 token）后再提交一次
      _addLog('${course.displayName} 提交未生效，重新准备后提交一次');
      _updateTask(course, TeacherEvaluationTaskStatus.preparing, '提交未生效，重新准备表单');
      final retryPrepare = await service.prepareEvaluation(course, pendingCount, scoreMode);
      if (!_isCurrentRun(runId)) return;
      final retryPrepared = retryPrepare.data;
      if (!retryPrepare.success || retryPrepared == null) {
        _failTask(course, retryPrepare.error ?? '重试准备评价表单失败', errorKind: 'submitFailed');
        return;
      }
      prepared = retryPrepared;
    }

    // 提交已返回成功：刷新课程列表确认服务器记录
    _updateTask(course, TeacherEvaluationTaskStatus.verifying, '正在刷新课程列表验证');
    final verified = await service.verifyCourseEvaluated(course);
    if (!_isCurrentRun(runId)) return;
    if (!verified.success) {
      _failTask(course, '提交已返回成功，但刷新列表失败，请稍后刷新查看', errorKind: 'verifyUnknown');
    } else if (verified.data == true) {
      _updateTask(course, TeacherEvaluationTaskStatus.success, '提交成功，服务器已确认');
      _addLog('${course.displayName} 提交成功');
    } else {
      _failTask(course, '评教未生效，服务器未确认', errorKind: 'verifyMismatch');
    }
  }

  /// 单门评价页提交前等待：防止评价页 token 生成后过快提交
  Future<void> _awaitSubmitWait(int runId, TeacherEvaluationCourse course, String label) async {
    for (var second = _waitBeforeSubmit.inSeconds; second >= 1; second--) {
      if (!_isCurrentRun(runId)) return;
      _updateTask(course, TeacherEvaluationTaskStatus.waiting, label, second);
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// 刷新课程列表；失败返回 false，批后补偿据此跳过
  Future<bool> _refreshAfterBatch() async {
    final result = await service.loadCourses();
    final data = result.data;
    if (result.success && data != null && !data.isClosed) {
      _courses = data.courses;
      _addLog('批量任务结束，已刷新课程列表');
      notifyListeners();
      return true;
    }
    _addLog('批量任务结束后刷新失败：${result.error ?? '评价已关闭或返回异常'}');
    return false;
  }

  void _failTask(TeacherEvaluationCourse course, String message, {String errorKind = 'unknown'}) {
    _updateTask(course, TeacherEvaluationTaskStatus.failed, message, 0, errorKind);
    _addLog('${course.displayName} 失败[$errorKind]：$message');
  }

  void _updateTask(
    TeacherEvaluationCourse course,
    TeacherEvaluationTaskStatus status,
    String message, [
    int countdown = 0,
    String? errorKind,
  ]) {
    _tasks = _tasks.map((task) {
      if (task.course.matches(course)) {
        return task.copyWith(
          status: status,
          message: message,
          countdownSeconds: countdown,
          errorKind: errorKind,
        );
      }
      return task;
    }).toList();
    notifyListeners();
  }

  void _addLog(String message) {
    _logs = [..._logs, message].takeLast(80).toList();
  }

  bool _isCurrentRun(int runId) => _isRunning && _runId == runId;

  @override
  void dispose() {
    stop(resetRunning: false);
    super.dispose();
  }

  static const _startInterval = Duration(seconds: 6);
  static const _waitBeforeSubmit = Duration(seconds: 140);
  static const _retryableErrorKinds = {'prepareFailed', 'submitFailed'};
  static const _scoreModeKey = 'teacher_eval_score_mode';
}

extension on TeacherEvaluationTaskStatus {
  bool get isActive => switch (this) {
        TeacherEvaluationTaskStatus.pending ||
        TeacherEvaluationTaskStatus.preparing ||
        TeacherEvaluationTaskStatus.waiting ||
        TeacherEvaluationTaskStatus.submitting ||
        TeacherEvaluationTaskStatus.verifying => true,
        TeacherEvaluationTaskStatus.success ||
        TeacherEvaluationTaskStatus.failed ||
        TeacherEvaluationTaskStatus.cancelled => false,
      };
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    return list.skip(list.length > count ? list.length - count : 0);
  }
}
