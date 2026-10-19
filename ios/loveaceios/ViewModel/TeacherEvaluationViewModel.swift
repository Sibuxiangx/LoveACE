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
    /// 首次访问保护倒计时（秒），0 表示未处于保护等待
    var protectionWaitSeconds = 0
    var protectionWaitTotalSeconds = 0

    private var service: TeacherEvaluationService?
    private var launcherTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var activeTasks: [Task<TeacherEvaluationResult, Never>] = []
    private var protectionAttempt = 0
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
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            error = nil
            isEvaluationClosed = false
            let result = await service.fetchCourses()
            if Task.isCancelled { return }
            let protection = await service.indexProtection
            if protection.requiresInitialWait {
                // 首次访问保护：显示倒计时，等待后重新拉取 index / 课程列表
                if protectionAttempt >= Self.maxProtectionWaits {
                    protectionWaitSeconds = 0
                    protectionWaitTotalSeconds = 0
                    isLoading = false
                    error = "首次访问保护未解除，请稍后手动刷新重试"
                    addLog("首次访问保护未解除，已停止自动重试")
                    return
                }
                protectionAttempt += 1
                let waitSeconds = protection.waitSeconds
                protectionWaitTotalSeconds = waitSeconds
                protectionWaitSeconds = waitSeconds
                courses = []
                tasks = []
                isLoading = false
                addLog("首次评教需阅读须知，等待 \(waitSeconds) 秒后继续")
                while protectionWaitSeconds > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    protectionWaitSeconds = max(protectionWaitSeconds - 1, 0)
                }
                protectionWaitTotalSeconds = 0
                addLog("保护等待结束，重新加载评教页")
                loadCourses()
                return
            }
            protectionAttempt = 0
            protectionWaitSeconds = 0
            protectionWaitTotalSeconds = 0
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
        var results = await runTaskBatch(Array(tasks))
        if Task.isCancelled {
            activeTasks.forEach { $0.cancel() }
            markUnfinishedTasksAsCancelled()
            isEvaluating = false
            activeTasks.removeAll()
            launcherTask = nil
            return
        }

        // 批后补偿：刷新列表，对失败且仍未评的课程补跑一轮
        if results.contains(where: { !$0.success }) {
            await refreshCoursesAfterEvaluation()
            let stillPending = tasks
                .filter { $0.status == .failed }
                .filter { task in courses.first { $0.matches(task.course) }?.isEvaluated != true }
            if !stillPending.isEmpty {
                addLog("批后补偿：\(stillPending.count) 门课程将自动重试一轮")
                for task in stillPending {
                    if let index = tasks.firstIndex(where: { $0.taskId == task.taskId }) {
                        tasks[index].status = .waiting
                        tasks[index].statusMessage = "批后重试等待中"
                        tasks[index].errorMessage = nil
                        tasks[index].errorKind = nil
                    }
                }
                results.append(contentsOf: await runTaskBatch(stillPending))
            }
        }

        // 按课程取最后一轮结果汇总
        var latestByCourse: [TeacherEvaluationCourse: TeacherEvaluationResult] = [:]
        for result in results { latestByCourse[result.course] = result }
        let finalResults = Array(latestByCourse.values)

        let success = finalResults.filter(\.success).count
        let failed = finalResults.count - success
        lastResult = TeacherEvaluationBatchResult(
            total: finalResults.count,
            success: success,
            failed: failed,
            results: finalResults,
            duration: Date().timeIntervalSince(startTime)
        )

        if failed > 0 {
            addLog("并发评教完成：成功 \(success)/\(finalResults.count)，失败 \(failed)")
        } else {
            addLog("并发评教完成：全部 \(finalResults.count) 门课程成功")
        }

        await refreshCoursesAfterEvaluation()
        isEvaluating = false
        activeTasks.removeAll()
        launcherTask = nil
    }

    /// 按标准间隔启动一批任务并等待全部完成
    private func runTaskBatch(_ batch: [TeacherEvaluationTask]) async -> [TeacherEvaluationResult] {
        var runners: [Task<TeacherEvaluationResult, Never>] = []

        for (index, task) in batch.enumerated() {
            if Task.isCancelled { break }
            if index > 0 {
                addLog("等待 \(launchIntervalSeconds) 秒后启动下一个任务（\(index + 1)/\(batch.count)）")
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

        var results: [TeacherEvaluationResult] = []
        for runner in runners {
            results.append(await runner.value)
        }
        return results
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

        var prepared = await service.prepareEvaluation(course: course, totalCourses: tasks.count)
        if !prepared.success {
            // 瞬时失败（网络抖动/HTTP 5xx）立即重试一次
            addLog("任务 \(taskId) [\(course.displayName)]：准备失败，立即重试一次")
            updateTask(taskId, status: .preparing, message: "准备失败，立即重试")
            prepared = await service.prepareEvaluation(course: course, totalCourses: tasks.count)
        }
        guard prepared.success, let formData = prepared.data else {
            return failTask(taskId, course: course, message: prepared.error ?? "无法访问评价页面", errorKind: "prepareFailed")
        }

        updateTask(taskId, status: .preparing, message: "解析问卷")
        addLog("任务 \(taskId) [\(course.displayName)]：解析问卷")
        updateTask(taskId, status: .preparing, message: "生成答案")
        addLog("任务 \(taskId) [\(course.displayName)]：生成答案")

        var form = formData
        var isRetry = false
        while true {
            updateTask(taskId, status: .countdown, message: isRetry ? "重试等待提交" : "等待提交", countdownRemaining: countdownSeconds, countdownTotal: countdownSeconds)
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

            updateTask(taskId, status: .submitting, message: isRetry ? "重新提交评价" : "提交评价", countdownRemaining: 0, countdownTotal: countdownSeconds)
            addLog("任务 \(taskId) [\(course.displayName)]：提交评价")
            let submit = await service.submitEvaluation(formData: form)
            if submit.success { break }

            // 验证兜底：submit 响应异常但服务器实际已记录时按成功处理
            updateTask(taskId, status: .verifying, message: "提交响应异常，正在核实")
            let fallback = await service.fetchCourses()
            if fallback.success, let updated = fallback.data,
               updated.first(where: { course.matches($0) })?.isEvaluated == true {
                updateTask(taskId, status: .completed, message: "提交成功（响应异常，已核实）", endTime: Date())
                addLog("任务 \(taskId) [\(course.displayName)]：提交成功（响应异常，已核实）")
                return TeacherEvaluationResult(course: course, success: true)
            }

            // 立即重试一次完整流程：刷新 index token → 重新 prepare（不复用旧评价页 token）→ 等待 → 提交
            guard !isRetry else {
                return failTask(taskId, course: course, message: submit.error ?? "提交失败", errorKind: "submitFailed")
            }
            isRetry = true
            addLog("任务 \(taskId) [\(course.displayName)]：提交失败，刷新 token 后重试一次")
            await service.refreshIndexToken()
            updateTask(taskId, status: .preparing, message: "提交失败，重新准备表单")
            let retried = await service.prepareEvaluation(course: course, totalCourses: tasks.count)
            guard retried.success, let retryForm = retried.data else {
                return failTask(taskId, course: course, message: retried.error ?? "重试准备失败", errorKind: "submitFailed")
            }
            form = retryForm
        }

        updateTask(taskId, status: .verifying, message: "验证结果")
        addLog("任务 \(taskId) [\(course.displayName)]：验证结果")
        let verify = await service.fetchCourses()
        guard verify.success, let updatedCourses = verify.data else {
            return failTask(taskId, course: course, message: verify.error ?? "无法验证结果", errorKind: "verifyMismatch")
        }
        let updatedCourse = updatedCourses.first { course.matches($0) }
        guard updatedCourse?.isEvaluated == true else {
            return failTask(taskId, course: course, message: "评教未生效，服务器未确认", errorKind: "verifyMismatch")
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

    private func failTask(_ taskId: Int, course: TeacherEvaluationCourse, message: String, errorKind: String = "unknown") -> TeacherEvaluationResult {
        updateTask(taskId, status: .failed, message: "失败", errorMessage: message, errorKind: errorKind, endTime: Date())
        addLog("任务 \(taskId) [\(course.displayName)] 失败[\(errorKind)]：\(message)")
        return TeacherEvaluationResult(course: course, success: false, errorMessage: message)
    }

    private func updateTask(
        _ taskId: Int,
        status: TeacherEvaluationTaskStatus? = nil,
        message: String? = nil,
        errorMessage: String? = nil,
        countdownRemaining: Int? = nil,
        countdownTotal: Int? = nil,
        errorKind: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        guard let index = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        if let status { tasks[index].status = status }
        if let message { tasks[index].statusMessage = message }
        if let errorMessage { tasks[index].errorMessage = errorMessage }
        if let errorKind { tasks[index].errorKind = errorKind }
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

    /// 首次访问保护：最多自动等待重载次数（超过则要求手动刷新）
    private static let maxProtectionWaits = 2
}
