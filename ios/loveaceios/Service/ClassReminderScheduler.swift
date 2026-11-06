import Foundation
import UserNotifications

/// 上课前本地提醒，不依赖服务端。系统对待发通知数量有限，只保留最近一批；
/// 标识由开始时刻与节次决定，重复注册会覆盖而不是叠加。
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

    /// 已开启时重排未来 14 天内的提醒；权限被系统关闭时 add 会失败，静默忽略
    static func reschedule(snapshot: WidgetSnapshot?) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        await removeOwnPending(center)
        guard let snapshot else { return }
        for request in upcomingRequests(snapshot: snapshot).prefix(maxPending) {
            try? await center.add(request)
        }
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
            let phase = SchoolTerm.phase(on: day, semesters: snapshot.semesters, calendar: calendar)
            for course in WidgetScheduleBuilder.coursesForDay(day, phase: phase, snapshot: snapshot, calendar: calendar) {
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
}
