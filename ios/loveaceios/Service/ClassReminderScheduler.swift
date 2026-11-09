import Foundation
import UserNotifications

/// 上课与考试的本地提醒，不依赖服务端。系统对待发通知数量有限，只保留最近一批；
/// 标识由开始时刻与节次（考试为日期与课程）决定，重复注册会覆盖而不是叠加。
enum ClassReminderScheduler {
    static let enabledKey = "class_reminder_enabled"
    private static let idPrefix = "class-reminder-"
    private static let maxPending = 60
    private static let windowDays = 14

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// 开启时请求通知权限；返回最终是否处于开启状态
    static func setEnabled(_ enabled: Bool, snapshot: WidgetSnapshot?) async -> Bool {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await cancelAll()
            return false
        }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted {
            await reschedule(snapshot: snapshot)
        }
        return granted
    }

    /// 重排全部提醒。考试提醒只取决于通知授权（未决定时在此请求一次），与上课提醒开关无关：
    /// 每场考试前一晚 20:00 一条，不受 14 天窗口限制。上课提醒仍需开关开启，窗口为未来 14 天。
    /// 权限被系统关闭时 add 会失败，静默忽略
    static func reschedule(snapshot: WidgetSnapshot?) async {
        let center = UNUserNotificationCenter.current()
        await removeOwnPending(center)
        guard let snapshot else { return }
        let status = await authorizationStatus(center)
        let examsAllowed = [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(status)
        // 考试提醒排在前面，待发数量达到上限时优先保留
        var requests: [UNNotificationRequest] = examsAllowed ? examRequests(snapshot: snapshot) : []
        if isEnabled {
            requests += upcomingRequests(snapshot: snapshot)
        }
        for request in requests.prefix(maxPending) {
            try? await center.add(request)
        }
    }

    /// 读取通知授权；仅在 notDetermined 时请求一次 alert 与 sound（系统权限弹窗，无应用内提示）
    private static func authorizationStatus(_ center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return status }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await center.notificationSettings().authorizationStatus
    }

    static func cancelAll() async {
        await removeOwnPending(UNUserNotificationCenter.current())
    }

    private static func removeOwnPending(_ center: UNUserNotificationCenter) async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func upcomingRequests(snapshot: WidgetSnapshot, now: Date = .now) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let lead = WidgetScheduleBuilder.reminderLeadMinutes
        var fires: [(date: Date, request: UNNotificationRequest)] = []

        for offset in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let phase = SchoolTerm.phase(on: day, semesters: snapshot.semesters, exams: snapshot.examList, calendar: calendar)
            for case .course(let course) in WidgetScheduleBuilder.itemsForDay(day, phase: phase, snapshot: snapshot, calendar: calendar) {
                guard let span = SchoolCalendar.span(of: course),
                      let start = calendar.date(byAdding: .minute, value: span.start, to: day),
                      let fire = calendar.date(byAdding: .minute, value: -lead, to: start),
                      fire > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "即将上课：\(course.courseName)"
                let place = course.location.isEmpty ? "" : " · \(course.location)"
                content.body = "\(lead) 分钟后开始 · \(SchoolCalendar.rangeText(course))\(place)"
                content.sound = .default

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "\(idPrefix)\(Int(fire.timeIntervalSince1970))-\(course.startSession)-\(course.courseName)"
                fires.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
            }
        }
        return fires.sorted { $0.date < $1.date }.map(\.request)
    }

    /// 每场考试前一天 20:00 提醒；已过去的不再排。标识由考试的日期、课程与时间决定，重排会覆盖
    private static func examRequests(snapshot: WidgetSnapshot, now: Date = .now) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        var fires: [(date: Date, request: UNNotificationRequest)] = []
        for exam in snapshot.examList {
            guard let day = SchoolDay.date(exam.date, calendar: calendar),
                  let eve = calendar.date(byAdding: .day, value: -1, to: day),
                  let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: eve),
                  fire > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "明天有考试：\(exam.courseName)"
            let place = exam.location.isEmpty ? "" : " · \(exam.location)"
            content.body = "\(exam.rangeText)\(place)"
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            fires.append((fire, UNNotificationRequest(identifier: "\(idPrefix)exam-\(exam.id)", content: content, trigger: trigger)))
        }
        return fires.sorted { $0.date < $1.date }.map(\.request)
    }
}
