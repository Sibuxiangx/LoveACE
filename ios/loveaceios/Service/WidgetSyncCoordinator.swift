import Foundation
import WidgetKit

/// 小组件数据同步：登录、自动重连与回到前台时触发。
/// 拉取失败保留旧快照；拉取成功后整体覆盖，并只触发一次 reload。
@MainActor
enum WidgetSyncCoordinator {
    /// 前台重复触发时的最小间隔，避免每次切回前台都请求课表
    private static let minInterval: TimeInterval = 30 * 60
    private static var inFlight = false

    /// 快照写入成功后发出，首页据此刷新考试周状态
    static let snapshotDidChange = Notification.Name("WidgetSyncCoordinator.snapshotDidChange")

    static func sync(authVM: AuthViewModel, force: Bool = false) async {
        let userId = authVM.userId
        guard !userId.isEmpty, let jwc = authVM.jwcService, let schedule = authVM.studentScheduleService else { return }
        guard !inFlight else { return }

        let cached = WidgetSnapshotStore.load()
        if !force, let cached, cached.userId == userId,
           Date().timeIntervalSince(cached.updatedAt) < minInterval {
            return
        }

        inFlight = true
        defer { inFlight = false }

        let semesters = (try? await SemesterFeed.fetch()) ?? cached?.semesters ?? []
        let termsResult = await jwc.getAllTerms()
        guard termsResult.success, let terms = termsResult.data,
              let current = terms.first(where: { $0.isCurrent }) ?? terms.first else { return }
        let scheduleResult = await schedule.getStudentSchedule(termCode: current.termCode)
        guard scheduleResult.success, let data = scheduleResult.data else { return }
        let examsResult = await jwc.getExamInfo()
        // 考试拉取失败只沿用同一用户的上一次考试，不阻止课表保存；成功（含空列表）则整体覆盖
        let examList: [WidgetExamEntry]
        if examsResult.success, let fetched = examsResult.data {
            examList = examEntries(from: fetched)
        } else if let cached, cached.userId == userId {
            examList = cached.examList
        } else {
            examList = []
        }

        let snapshot = WidgetSnapshot(
            userId: userId,
            updatedAt: Date(),
            semesters: semesters,
            termCode: current.termCode,
            courses: entries(from: data.courses),
            exams: examList
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: snapshotDidChange, object: nil)
        await ClassReminderScheduler.reschedule(snapshot: snapshot)
        await CourseLiveActivityController.sync()
    }

    /// 登出或会话结束时清空小组件快照、提醒与灵动岛
    static func clearAll() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await ClassReminderScheduler.cancelAll()
            await CourseLiveActivityController.endAll()
        }
    }

    private static func entries(from courses: [ScheduleCourse]) -> [WidgetCourseEntry] {
        courses.flatMap { course in
            course.timeAndPlaceList.map { place in
                WidgetCourseEntry(
                    courseName: course.courseName,
                    location: place.locationDescription,
                    teacher: course.attendClassTeacher,
                    dayOfWeek: place.classDay,
                    startSession: place.classSessions,
                    endSession: place.endSession,
                    weekDescription: place.weekDescription,
                    classWeek: place.classWeek
                )
            }
        }
    }

    private static func examEntries(from exams: [UnifiedExamInfo]) -> [WidgetExamEntry] {
        exams.compactMap { exam in
            let date = String(exam.examDate.prefix(10))
            guard SchoolDay.date(date) != nil else { return nil }
            return WidgetExamEntry(courseName: exam.courseName, date: date, timeText: exam.examTime, location: exam.examLocation)
        }
    }
}
