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

  const TeacherEvaluationTaskState({
    required this.course,
    this.status = TeacherEvaluationTaskStatus.pending,
    this.message = '等待开始',
    this.countdownSeconds = 0,
  });

  TeacherEvaluationTaskState copyWith({
    TeacherEvaluationTaskStatus? status,
    String? message,
    int? countdownSeconds,
  }) =>
      TeacherEvaluationTaskState(
        course: course,
        status: status ?? this.status,
        message: message ?? this.message,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      );
}

class TeacherEvaluationProvider extends ChangeNotifier {
  final TeacherEvaluationService service;
  int _runId = 0;

  TeacherEvaluationState _state = TeacherEvaluationState.initial;
  bool _isRunning = false;
  String _closedMessage = '';
  String _indexToken = '';
  String? _errorMessage;
  List<TeacherEvaluationCourse> _courses = [];
  List<TeacherEvaluationTaskState> _tasks = [];
  List<String> _logs = [];

  TeacherEvaluationProvider(this.service);

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
      _indexToken = data.tokenValue;
      _courses = [];
      _tasks = [];
      _addLog('评价暂未开启');
      notifyListeners();
      return;
    }

    _state = TeacherEvaluationState.loaded;
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

    final futures = <Future<void>>[];
    try {
      for (var i = 0; i < pending.length; i++) {
        if (!_isCurrentRun(runId)) break;
        if (i > 0) await Future.delayed(_startInterval);
        if (!_isCurrentRun(runId)) break;
        futures.add(_runTask(runId, pending[i], pending.length, _indexToken));
      }
      await Future.wait(futures);
      if (_isCurrentRun(runId)) await _refreshAfterBatch();
    } finally {
      if (_isCurrentRun(runId)) {
        _isRunning = false;
        notifyListeners();
      }
    }
  }

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
    String indexToken,
  ) async {
    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.preparing, '正在访问评价页并生成表单');
    final prepare = await service.prepareEvaluation(course, pendingCount, indexToken);
    final prepared = prepare.data;
    if (!_isCurrentRun(runId)) return;
    if (!prepare.success || prepared == null) {
      _failTask(course, prepare.error ?? '准备评价表单失败');
      return;
    }

    for (var second = _waitBeforeSubmit.inSeconds; second >= 1; second--) {
      if (!_isCurrentRun(runId)) return;
      _updateTask(course, TeacherEvaluationTaskStatus.waiting, '等待提交', second);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.submitting, '正在提交评价');
    final submit = await service.submitEvaluation(prepared);
    final submitResult = submit.data;
    if (!submit.success || submitResult?.success != true) {
      _failTask(course, submitResult?.message ?? submit.error ?? '提交评价失败');
      return;
    }

    if (!_isCurrentRun(runId)) return;
    _updateTask(course, TeacherEvaluationTaskStatus.verifying, '正在刷新课程列表验证');
    final verified = await service.verifyCourseEvaluated(course);
    if (verified.success && verified.data == true) {
      _updateTask(course, TeacherEvaluationTaskStatus.success, '提交成功，服务器已确认');
      _addLog('${course.displayName} 提交成功');
    } else {
      _failTask(course, verified.error ?? '评教未生效，服务器未确认');
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

  void _failTask(TeacherEvaluationCourse course, String message) {
    _updateTask(course, TeacherEvaluationTaskStatus.failed, message);
    _addLog('${course.displayName} 失败：$message');
  }

  void _updateTask(
    TeacherEvaluationCourse course,
    TeacherEvaluationTaskStatus status,
    String message, [
    int countdown = 0,
  ]) {
    _tasks = _tasks.map((task) {
      if (task.course.matches(course)) {
        return task.copyWith(status: status, message: message, countdownSeconds: countdown);
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
