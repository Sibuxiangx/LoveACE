import Foundation

@MainActor @Observable
final class TeacherEvaluationViewModel {
    var isLoading = false
    var isEvaluating = false
    var courses: [TeacherEvaluationCourse] = []
    var tasks: [TeacherEvaluationTask] = []
    var logs: [String] = []
    var error: String?
    var isEvaluationClosed = false
    var lastResult: TeacherEvaluationBatchResult?
    var evaluationStrategy: EvaluationStrategy = .smart

    private var service: TeacherEvaluationService?
    private var launcherTask: Task<Void, Never>?
    private var activeTasks: [Task<TeacherEvaluationResult, Never>] = []
    private let launchIntervalSeconds = 6
    private let countdownSeconds = 140

    var pendingCourses: [TeacherEvaluationCourse] { courses.filter { !$0.isEvaluated } }
    var evaluatedCourses: [TeacherEvaluationCourse] { courses.filter(\.isEvaluated) }
    var totalCount: Int { courses.count }
    var pendingCount: Int { pendingCourses.count }
    var evaluatedCount: Int { evaluatedCourses.count }
    var completedTaskCount: Int { tasks.filter(\.isFinished).count }
    var successfulTaskCount: Int { tasks.filter(\.isSuccess).count }
    var progress: Double { tasks.isEmpty ? 0 : Double(completedTaskCount) / Double(tasks.count) }

    func initialize(service: TeacherEvaluationService) {
        self.service = service
    }

    func loadCourses() {
        guard let service else { return }
        Task {
            isLoading = true
            error = nil
            isEvaluationClosed = false
            let result = await service.fetchCourses()
            if result.success, let data = result.data {
                courses = data
            } else if Self.isClosedMessage(result.error) {
                courses = []
                tasks = []
                isEvaluationClosed = true
            } else {
                error = result.error ?? "加载课程失败"
            }
            isLoading = false
        }
    }

    func startConcurrentEvaluation() {
        guard !isEvaluating else { return }
        guard service != nil else {
            error = "评教服务未初始化"
            return
        }
        guard !isEvaluationClosed else {
            error = "评价暂未开启"
            return
        }
        let pending = pendingCourses
        guard !pending.isEmpty else {
            error = "没有待评课程"
            return
        }

        isEvaluating = true
        error = nil
        lastResult = nil
        logs.removeAll()
        tasks = pending.enumerated().map { index, course in
            TeacherEvaluationTask(taskId: index + 1, course: course)
        }
        addLog("开始并发批量评教，共 \(pending.count) 门课程")

        launcherTask = Task { [weak self] in
            guard let self else { return }
            await self.runConcurrentEvaluation()
        }
    }

    func cancelEvaluation() {
        guard isEvaluating else { return }
        launcherTask?.cancel()
        activeTasks.forEach { $0.cancel() }
        markUnfinishedTasksAsCancelled()
        addLog("已请求中断评教任务")
        isEvaluating = false
    }

    func clearResult() {
        lastResult = nil
    }

    private func runConcurrentEvaluation() async {
        guard !tasks.isEmpty else {
            isEvaluating = false
            return
        }

        let startTime = Date()
        var runners: [Task<TeacherEvaluationResult, Never>] = []

        for task in tasks {
            if Task.isCancelled { break }
            if task.taskId > 1 {
                addLog("等待 \(launchIntervalSeconds) 秒后启动下一个任务（\(task.taskId)/\(tasks.count)）")
                do {
                    try await Task.sleep(for: .seconds(launchIntervalSeconds))
                } catch {
                    break
                }
            }

            addLog("启动任务 \(task.taskId)：\(task.course.displayName)")
            let runner = Task { [weak self] in
                guard let self else {
                    return TeacherEvaluationResult(course: task.course, success: false, errorMessage: "任务已释放")
                }
                return await self.executeTask(taskId: task.taskId)
            }
            activeTasks.append(runner)
            runners.append(runner)
        }

        if Task.isCancelled {
            activeTasks.forEach { $0.cancel() }
            markUnfinishedTasksAsCancelled()
            isEvaluating = false
            activeTasks.removeAll()
            launcherTask = nil
            return
        }

        addLog("所有任务已启动，等待完成...")
        var results: [TeacherEvaluationResult] = []
        for runner in runners {
            results.append(await runner.value)
        }

        let success = results.filter(\.success).count
        let failed = results.count - success
        lastResult = TeacherEvaluationBatchResult(
            total: results.count,
            success: success,
            failed: failed,
            results: results,
            duration: Date().timeIntervalSince(startTime)
        )

        if failed > 0 {
            addLog("并发评教完成：成功 \(success)/\(results.count)，失败 \(failed)")
        } else {
            addLog("并发评教完成：全部 \(results.count) 门课程成功")
        }

        await refreshCoursesAfterEvaluation()
        isEvaluating = false
        activeTasks.removeAll()
        launcherTask = nil
    }

    private func executeTask(taskId: Int) async -> TeacherEvaluationResult {
        guard let service, let task = tasks.first(where: { $0.taskId == taskId }) else {
            return TeacherEvaluationResult(course: TeacherEvaluationCourse(
                legacyId: "", name: "未知课程", teacher: "", evaluatedPeople: "", evaluatedPeopleNumber: "",
                coureSequenceNumber: "", evaluationContentNumber: "", questionnaireCode: "", questionnaireName: "", isEvaluated: false
            ), success: false, errorMessage: "任务不存在")
        }

        let course = task.course
        updateTask(taskId, status: .preparing, message: "访问评价页面", startTime: Date())
        addLog("任务 \(taskId) [\(course.displayName)]：访问评价页面")

        if Task.isCancelled { return failTask(taskId, course: course, message: "已取消") }

        let prepared = await service.prepareEvaluation(course: course, totalCourses: tasks.count, strategy: evaluationStrategy)
        guard prepared.success, let formData = prepared.data else {
            return failTask(taskId, course: course, message: prepared.error ?? "无法访问评价页面")
        }

        updateTask(taskId, status: .preparing, message: "解析问卷")
        addLog("任务 \(taskId) [\(course.displayName)]：解析问卷")
        updateTask(taskId, status: .preparing, message: "生成答案")
        addLog("任务 \(taskId) [\(course.displayName)]：生成答案")

        updateTask(taskId, status: .countdown, message: "等待提交", countdownRemaining: countdownSeconds, countdownTotal: countdownSeconds)
        addLog("任务 \(taskId) [\(course.displayName)]：开始等待 \(countdownSeconds) 秒")
        for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
            if Task.isCancelled { return failTask(taskId, course: course, message: "已取消") }
            updateTask(taskId, countdownRemaining: remaining, countdownTotal: countdownSeconds)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return failTask(taskId, course: course, message: "已取消")
            }
        }

        updateTask(taskId, status: .submitting, message: "提交评价", countdownRemaining: 0, countdownTotal: countdownSeconds)
        addLog("任务 \(taskId) [\(course.displayName)]：提交评价")
        let submit = await service.submitEvaluation(formData: formData)
        guard submit.success else {
            return failTask(taskId, course: course, message: submit.error ?? "提交失败")
        }

        updateTask(taskId, status: .verifying, message: "验证结果")
        addLog("任务 \(taskId) [\(course.displayName)]：验证结果")
        let verify = await service.fetchCourses()
        guard verify.success, let updatedCourses = verify.data else {
            return failTask(taskId, course: course, message: verify.error ?? "无法验证结果")
        }
        let updatedCourse = updatedCourses.first { course.matches($0) }
        guard updatedCourse?.isEvaluated == true else {
            return failTask(taskId, course: course, message: "评教未生效，服务器未确认")
        }

        updateTask(taskId, status: .completed, message: "完成", endTime: Date())
        addLog("任务 \(taskId) [\(course.displayName)]：评教完成")
        return TeacherEvaluationResult(course: course, success: true)
    }

    private func refreshCoursesAfterEvaluation() async {
        guard let service else { return }
        addLog("刷新课程列表...")
        let result = await service.fetchCourses()
        if result.success, let data = result.data {
            courses = data
            addLog("课程列表已更新")
        } else if let error = result.error {
            addLog("课程列表刷新失败：\(error)")
        }
    }

    private func failTask(_ taskId: Int, course: TeacherEvaluationCourse, message: String) -> TeacherEvaluationResult {
        updateTask(taskId, status: .failed, message: "失败", errorMessage: message, endTime: Date())
        addLog("任务 \(taskId) [\(course.displayName)]：\(message)")
        return TeacherEvaluationResult(course: course, success: false, errorMessage: message)
    }

    private func updateTask(
        _ taskId: Int,
        status: TeacherEvaluationTaskStatus? = nil,
        message: String? = nil,
        errorMessage: String? = nil,
        countdownRemaining: Int? = nil,
        countdownTotal: Int? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        guard let index = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        if let status { tasks[index].status = status }
        if let message { tasks[index].statusMessage = message }
        if let errorMessage { tasks[index].errorMessage = errorMessage }
        if let countdownRemaining { tasks[index].countdownRemaining = countdownRemaining }
        if let countdownTotal { tasks[index].countdownTotal = countdownTotal }
        if let startTime { tasks[index].startTime = startTime }
        if let endTime { tasks[index].endTime = endTime }
    }

    private func markUnfinishedTasksAsCancelled() {
        for index in tasks.indices where !tasks[index].isFinished {
            tasks[index].status = .failed
            tasks[index].statusMessage = "已取消"
            tasks[index].errorMessage = "用户已中断任务"
            tasks[index].endTime = Date()
        }
    }

    private func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 120 { logs.removeFirst(logs.count - 120) }
    }

    private static func isClosedMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains("评价暂未开启") || message.contains("评估开关已关闭")
    }
}
