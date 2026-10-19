import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/jwc/teacher_evaluation.dart';
import '../services/jwc/teacher_evaluation_service.dart';

enum TeacherEvaluationState { initial, loading, loaded, closed, error }
enum TeacherEvaluationTaskStatus { pending, preparing, waiting, submitting, verifying, success, failed, cancelled }

class TeacherEvaluationTaskState {
  final TeacherEvaluationCourse course;
  final TeacherEvaluationTaskStatus status;
  final String message;
  final int countdownSeconds;
  /// 轻量错误分类：prepareFailed / submitFailed / verifyMismatch / unknown
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
  int _loadId = 0;
  int _protectionAttempt = 0;

  TeacherEvaluationState _state = TeacherEvaluationState.initial;
  bool _isRunning = false;
  String _closedMessage = '';
  String _indexToken = '';
  String? _errorMessage;
  List<TeacherEvaluationCourse> _courses = [];
  List<TeacherEvaluationTaskState> _tasks = [];
  List<String> _logs = [];

  /// 首次访问保护倒计时（秒），0 表示未处于保护等待
  int _protectionWaitSeconds = 0;
  int _protectionWaitTotalSeconds = 0;

  TeacherEvaluationProvider(this.service);

  TeacherEvaluationState get state => _state;
  bool get isRunning => _isRunning;
  String get closedMessage => _closedMessage;
  String? get errorMessage => _errorMessage;
  List<TeacherEvaluationCourse> get courses => _courses;
  List<TeacherEvaluationTaskState> get tasks => _tasks;
  List<String> get logs => _logs;
  int get protectionWaitSeconds => _protectionWaitSeconds;
  int get protectionWaitTotalSeconds => _protectionWaitTotalSeconds;
  List<TeacherEvaluationCourse> get pendingCourses => _courses.where((course) => !course.isEvaluated).toList();
  int get evaluatedCount => _courses.where((course) => course.isEvaluated).length;

  Future<void> load() async {
    stop(resetRunning: false);
    final loadId = ++_loadId;
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
      _indexToken = data.tokenValue;
      _courses = [];
      _tasks = [];
      _addLog('评价暂未开启');
      notifyListeners();
      return;
    }

    if (data.protection.requiresInitialWait) {
      // 首次访问保护：显示倒计时，等待后重新拉取 index / 课程列表
      if (_protectionAttempt >= _maxProtectionWaits) {
        _state = TeacherEvaluationState.error;
        _protectionWaitSeconds = 0;
        _protectionWaitTotalSeconds = 0;
        _errorMessage = '首次访问保护未解除，请稍后手动刷新重试';
        _addLog('首次访问保护未解除，已停止自动重试');
        notifyListeners();
        return;
      }
      _protectionAttempt++;
      final waitSeconds = data.protection.waitSeconds;
      _state = TeacherEvaluationState.loaded;
      _indexToken = data.tokenValue;
      _courses = [];
      _tasks = [];
      _protectionWaitTotalSeconds = waitSeconds;
      _protectionWaitSeconds = waitSeconds;
      _addLog('首次评教需阅读须知，等待 $waitSeconds 秒后继续');
      notifyListeners();
      for (var second = waitSeconds; second >= 1; second--) {
        if (loadId != _loadId) return; // 已被新的加载请求取代
        _protectionWaitSeconds = second;
        notifyListeners();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (loadId != _loadId) return;
      _protectionWaitSeconds = 0;
      _protectionWaitTotalSeconds = 0;
      _addLog('保护等待结束，重新加载评教页');
      await load();
      return;
    }

    _protectionAttempt = 0;
    _state = TeacherEvaluationState.loaded;
    _protectionWaitSeconds = 0;
    _protectionWaitTotalSeconds = 0;
    _indexToken = data.tokenValue;
    _courses = data.courses;
    _tasks = [];
    _errorMessage = null;
    _addLog('已加载 ${data.courses.length} 门课程，待评 ${pendingCourses.length} 门');
    notifyListeners();
  }

  Future<void> startBatch() async {
    final pending = pendingCourses;
    if (_isRunning || pending.isEmpty || _indexToken.isEmpty) return;

    final runId = ++_runId;
    _isRunning = true;
    _tasks = pending.map((course) => TeacherEvaluationTaskState(course: course)).toList();
    _errorMessage = null;
    _addLog('批量评教已启动，请保持 App 前台；已提交评价无法撤回');
    notifyListeners();

    try {
      await _runRound(runId, pending, _indexToken);
      if (!_isCurrentRun(runId)) return;

      // 批后补偿：刷新列表，对失败且仍未评的课程补跑一轮
      var retryCourses = _collectRetryCourses();
      if (retryCourses.isNotEmpty) {
        _addLog('批后补偿：${retryCourses.length} 门课程将自动重试一轮');
        notifyListeners();
        await _refreshAfterBatch();
        retryCourses = _collectRetryCourses();
        if (retryCourses.isNotEmpty) {
          await _runRound(runId, retryCourses, _indexToken);
          if (_isCurrentRun(runId)) await _refreshAfterBatch();
        } else {
          _addLog('批后补偿：失败课程刷新后均已确认已评，无需重试');
        }
      }
    } finally {
      if (_isCurrentRun(runId)) {
        _isRunning = false;
        notifyListeners();
      }
    }
  }

  /// 按标准间隔启动一轮任务并等待全部完成
  Future<void> _runRound(int runId, List<TeacherEvaluationCourse> courses, String indexToken) async {
    final futures = <Future<void>>[];
    for (var i = 0; i < courses.length; i++) {
      if (!_isCurrentRun(runId)) break;
      if (i > 0) await Future.delayed(_startInterval);
      if (!_isCurrentRun(runId)) break;
      futures.add(_runTask(runId, courses[i], courses.length, indexToken));
    }
    await Future.wait(futures);
  }

  /// 收集失败课程，剔除刷新后已确认已评的，并把剩余任务重置为待重试
  List<TeacherEvaluationCourse> _collectRetryCourses() {
    final refreshed = _courses;
    final retryCourses = _tasks
        .where((task) => task.status == TeacherEvaluationTaskStatus.failed)
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

  void stop({bool resetRunning = true}) {
    _runId++;
    if (!resetRunning) return;
    _isRunning = false;
    _protectionWaitSeconds = 0;
    _protectionWaitTotalSeconds = 0;
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
    String indexToken,
  ) async {
    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.preparing, '正在访问评价页并生成表单');
    var prepare = await service.prepareEvaluation(course, pendingCount, indexToken);
    if ((!prepare.success || prepare.data == null) && prepare.retryable) {
      // 瞬时失败（网络抖动/HTTP 5xx）立即重试一次
      _addLog('${course.displayName} 准备失败，立即重试一次');
      _updateTask(course, TeacherEvaluationTaskStatus.preparing, '准备失败，立即重试');
      prepare = await service.prepareEvaluation(course, pendingCount, indexToken);
    }
    var prepared = prepare.data;
    if (!_isCurrentRun(runId)) return;
    if (!prepare.success || prepared == null) {
      _failTask(course, prepare.error ?? '准备评价表单失败', errorKind: 'prepareFailed');
      return;
    }

    await _awaitSubmitWait(runId, course, '等待提交');

    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.submitting, '正在提交评价');
    final submit = await service.submitEvaluation(prepared);
    final submitResult = submit.data;
    if (!submit.success || submitResult?.success != true) {
      if (!_isCurrentRun(runId)) return;
      // 验证兜底：submit 响应异常但服务器实际已记录时按成功处理
      _updateTask(course, TeacherEvaluationTaskStatus.verifying, '提交响应异常，正在核实');
      final fallback = await service.verifyCourseEvaluated(course);
      if (!_isCurrentRun(runId)) return;
      if (fallback.success && fallback.data == true) {
        _updateTask(course, TeacherEvaluationTaskStatus.success, '提交成功（响应异常，服务器已确认）');
        _addLog('${course.displayName} 提交成功（响应异常，已核实）');
        return;
      }
      // 立即重试一次完整流程：刷新 index token → 重新 prepare（不复用旧评价页 token）→ 等待 → 提交
      _addLog('${course.displayName} 提交失败，刷新 token 后重试一次');
      _updateTask(course, TeacherEvaluationTaskStatus.preparing, '提交失败，重新准备表单');
      final refreshedToken = await service.fetchIndexToken();
      final retryPrepare = await service.prepareEvaluation(
        course, pendingCount, (refreshedToken.data?.isNotEmpty ?? false) ? refreshedToken.data! : indexToken,
      );
      final retryPrepared = retryPrepare.data;
      if (!_isCurrentRun(runId)) return;
      if (!retryPrepare.success || retryPrepared == null) {
        _failTask(course, retryPrepare.error ?? '重试准备评价表单失败', errorKind: 'submitFailed');
        return;
      }

      await _awaitSubmitWait(runId, course, '重试等待提交');

      if (!_isCurrentRun(runId)) return;
      _updateTask(course, TeacherEvaluationTaskStatus.submitting, '正在重新提交评价');
      final retrySubmit = await service.submitEvaluation(retryPrepared);
      final retrySubmitResult = retrySubmit.data;
      if (!retrySubmit.success || retrySubmitResult?.success != true) {
        _failTask(course, retrySubmitResult?.message ?? retrySubmit.error ?? '提交评价失败', errorKind: 'submitFailed');
        return;
      }
    }

    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.verifying, '正在刷新课程列表验证');
    final verified = await service.verifyCourseEvaluated(course);
    if (!_isCurrentRun(runId)) return;
    if (verified.success && verified.data == true) {
      _updateTask(course, TeacherEvaluationTaskStatus.success, '提交成功，服务器已确认');
      _addLog('${course.displayName} 提交成功');
    } else {
      _failTask(course, verified.error ?? '评教未生效，服务器未确认', errorKind: 'verifyMismatch');
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

  Future<void> _refreshAfterBatch() async {
    final result = await service.loadCourses();
    final data = result.data;
    if (result.success && data != null && !data.isClosed) {
      _courses = data.courses;
      _indexToken = data.tokenValue;
      _addLog('批量任务结束，已刷新课程列表');
      notifyListeners();
    } else if (result.error != null) {
      _addLog('批量任务结束后刷新失败：${result.error}');
    }
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

  /// 首次访问保护：最多自动等待重载次数（超过则要求手动刷新）
  static const _maxProtectionWaits = 2;
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
