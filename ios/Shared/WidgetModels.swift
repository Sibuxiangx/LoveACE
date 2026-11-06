import ActivityKit
import AppIntents
import Foundation

// 小组件与 App 共享的数据与计算。App 与 Widget 两个 target 都编译本文件。
// 课表时间以学校教务系统 sectionTime 为准：每节 45 分钟，全天 10 节。

// MARK: - 学校作息

enum SchoolCalendar {
    /// 节次 -> 开始、结束（自当天 0:00 起的分钟数）
    private static let sessionMinutes: [Int: (start: Int, end: Int)] = [
        1: (480, 525), 2: (535, 580), 3: (610, 655), 4: (665, 710), 5: (840, 885),
        6: (895, 940), 7: (970, 1015), 8: (1025, 1070), 9: (1140, 1185), 10: (1195, 1240),
    ]

    /// 课程的开始、结束分钟；节次超出学校作息时返回 nil
    static func span(of course: WidgetCourseEntry) -> (start: Int, end: Int)? {
        guard let start = sessionMinutes[course.startSession]?.start,
              let end = (sessionMinutes[course.endSession] ?? sessionMinutes[course.startSession])?.end,
              end > start else { return nil }
        return (start, end)
    }

    static func startText(_ course: WidgetCourseEntry) -> String {
        guard let span = span(of: course) else { return "第\(course.startSession)节" }
        return clock(span.start)
    }

    static func rangeText(_ course: WidgetCourseEntry) -> String {
        guard let span = span(of: course) else { return "第\(course.startSession)节" }
        return "\(clock(span.start))–\(clock(span.end))"
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

// MARK: - 学期

struct SemesterItem: Codable, Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let startDate: String
    let weeks: Int

    enum CodingKeys: String, CodingKey {
        case code, name, weeks
        case startDate = "start_date"
    }

    init(code: String, name: String, startDate: String, weeks: Int = 18) {
        self.code = code; self.name = name; self.startDate = startDate; self.weeks = weeks
    }

    func displayName() -> String {
        let termNameMap = ["1": "第一学期（秋季）", "2": "第二学期（春季）"]
        let parts = code.split(separator: "-")
        if parts.count == 3 {
            let yearPart = "\(parts[0])-\(parts[1])"
            let termText = termNameMap[String(parts[2])] ?? "第\(parts[2])学期"
            return "\(yearPart)学年 \(termText)"
        }
        return name.isEmpty ? code : name
    }

    /// 学期第一天（当天 0 点），startDate 格式 yyyy-MM-dd
    var firstDay: Date? {
        let parts = startDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

struct SemesterData: Codable {
    let version: Int
    let updatedAt: String
    let semesters: [SemesterItem]

    enum CodingKeys: String, CodingKey {
        case version
        case updatedAt = "updated_at"
        case semesters
    }

    init(version: Int = 1, updatedAt: String = "", semesters: [SemesterItem] = []) {
        self.version = version; self.updatedAt = updatedAt; self.semesters = semesters
    }
}

/// 某一天所处的学期阶段。周次与假期都由学期开始日期现算，不依赖 App 何时打开。
enum TermPhase: Equatable {
    case vacation(nextName: String?, nextStartDate: String?, daysUntilStart: Int?)
    case inSession(name: String, week: Int, totalWeeks: Int, isEnding: Bool)
}

enum SchoolTerm {
    /// 某天的学期阶段；学期列表为空时返回 nil（未知，需要同步）
    static func phase(on date: Date, semesters: [SemesterItem], calendar: Calendar = .current) -> TermPhase? {
        guard !semesters.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        for semester in semesters.sorted(by: { $0.startDate < $1.startDate }) {
            guard let start = semester.firstDay else { continue }
            if today < start {
                let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
                return .vacation(nextName: semester.displayName(), nextStartDate: semester.startDate, daysUntilStart: days)
            }
            guard let end = calendar.date(byAdding: .day, value: semester.weeks * 7 - 1, to: start) else { continue }
            if today <= end {
                let daysSinceStart = calendar.dateComponents([.day], from: start, to: today).day ?? 0
                let week = max(1, daysSinceStart / 7 + 1)
                return .inSession(
                    name: semester.displayName(),
                    week: week,
                    totalWeeks: semester.weeks,
                    isEnding: semester.weeks - week <= 2
                )
            }
        }
        return .vacation(nextName: nil, nextStartDate: nil, daysUntilStart: nil)
    }
}

// MARK: - 课程与快照

struct WidgetCourseEntry: Codable, Identifiable {
    var id: String { "\(dayOfWeek)_\(startSession)_\(courseName)" }
    let courseName: String
    let location: String
    let teacher: String
    let dayOfWeek: Int
    let startSession: Int
    let endSession: Int
    let weekDescription: String
    let classWeek: String

    /// classWeek 为 "0/1" 串，第 n 周对应下标 n-1
    func isActiveInWeek(_ week: Int) -> Bool {
        guard week > 0, week <= classWeek.count else { return false }
        let idx = classWeek.index(classWeek.startIndex, offsetBy: week - 1)
        return classWeek[idx] == "1"
    }
}

extension WidgetCourseEntry: Equatable {
    static func == (lhs: WidgetCourseEntry, rhs: WidgetCourseEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// App 写入、小组件只读的快照。拉取成功才整体覆盖。
struct WidgetSnapshot: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let userId: String
    /// 最近一次成功拉取课表的时间
    let updatedAt: Date
    let semesters: [SemesterItem]
    let termCode: String
    let courses: [WidgetCourseEntry]

    init(userId: String, updatedAt: Date, semesters: [SemesterItem], termCode: String, courses: [WidgetCourseEntry]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.userId = userId
        self.updatedAt = updatedAt
        self.semesters = semesters
        self.termCode = termCode
        self.courses = courses
    }
}

enum WidgetSnapshotStore {
    static let suiteName = "group.cn.linota.loveace"
    private static let key = "widget_snapshot_v2"
    /// 旧版本分散的键，写入新快照时一并清理
    private static let legacyKeys = [
        "widget_courses", "widget_updated", "widget_current_week", "widget_total_weeks", "widget_semester_in_session",
    ]

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        legacyKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    /// 结构版本不匹配或解码失败时返回 nil，视为未同步
    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }
}

// MARK: - 单个时刻的展示状态（纯数据，小组件与提醒共用）

struct NextDayCourse {
    let course: WidgetCourseEntry
    /// "明天" 或 "周X"
    let label: String
}

struct LiveCourse {
    let course: WidgetCourseEntry
    let start: Date
    let end: Date
    /// 同一天同一节课的稳定标识，用于避免重复创建灵动岛
    let key: String
}

struct WidgetScheduleState {
    let date: Date
    /// nil 表示未同步（快照缺失或学期列表为空）
    let phase: TermPhase?
    /// 今日全部课程，按节次排序
    let today: [WidgetCourseEntry]
    /// 今日尚未结束的课程（含进行中）
    let upcoming: [WidgetCourseEntry]
    let inProgress: WidgetCourseEntry?
    /// 进行中或即将开始的课程
    let next: WidgetCourseEntry?
    /// 今日无课时，之后最近的一节课
    let nextDay: NextDayCourse?
    /// 处于灵动岛时段（提前量内或上课中）的课程
    let liveCourse: LiveCourse?
    let lastSyncedAt: Date?

    var isSynced: Bool { phase != nil }

    var isStale: Bool {
        guard let lastSyncedAt else { return false }
        return date.timeIntervalSince(lastSyncedAt) > 24 * 3600
    }
}

enum WidgetScheduleBuilder {
    /// 上课前多久开始提醒，灵动岛与本地通知共用
    static let reminderLeadMinutes = 10

    static func state(at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> WidgetScheduleState {
        guard let snapshot else {
            return WidgetScheduleState(
                date: date, phase: nil, today: [], upcoming: [], inProgress: nil, next: nil,
                nextDay: nil, liveCourse: nil, lastSyncedAt: nil
            )
        }
        let phase = SchoolTerm.phase(on: date, semesters: snapshot.semesters, calendar: calendar)
        let dayStart = calendar.startOfDay(for: date)
        let today = coursesForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar)
        let minute = minuteOfDay(date, calendar)
        let upcoming = today.filter { (SchoolCalendar.span(of: $0)?.end ?? Int.max) > minute }
        let inProgress = today.first { course in
            guard let span = SchoolCalendar.span(of: course) else { return false }
            return minute >= span.start && minute < span.end
        }
        return WidgetScheduleState(
            date: date,
            phase: phase,
            today: today,
            upcoming: upcoming,
            inProgress: inProgress,
            next: inProgress ?? upcoming.first,
            nextDay: today.isEmpty ? nextCourse(after: dayStart, snapshot: snapshot, calendar: calendar) : nil,
            liveCourse: liveCourse(at: date, snapshot: snapshot, calendar: calendar),
            lastSyncedAt: snapshot.updatedAt
        )
    }

    /// 某天（0 点）的课程：仅学期内生效，按周次过滤，按节次排序
    static func coursesForDay(
        _ dayStart: Date, phase: TermPhase?, snapshot: WidgetSnapshot, calendar: Calendar = .current
    ) -> [WidgetCourseEntry] {
        guard case .inSession(_, let week, _, _)? = phase else { return [] }
        let weekday = calendar.component(.weekday, from: dayStart)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return snapshot.courses
            .filter { $0.dayOfWeek == isoWeekday && ($0.classWeek.isEmpty || $0.isActiveInWeek(week)) }
            .sorted { $0.startSession < $1.startSession }
    }

    /// 时间线需要切换的时刻：now，以及今天、明天每节课的开始与结束，以及明天 0 点
    static func transitionDates(from now: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> [Date] {
        guard let snapshot,
              let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        else { return [now] }
        var dates: Set<Date> = [now, startOfTomorrow]
        for dayStart in [calendar.startOfDay(for: now), startOfTomorrow] {
            let phase = SchoolTerm.phase(on: dayStart, semesters: snapshot.semesters, calendar: calendar)
            for course in coursesForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar) {
                guard let span = SchoolCalendar.span(of: course) else { continue }
                for minute in [span.start, span.end] {
                    if let time = calendar.date(byAdding: .minute, value: minute, to: dayStart), time > now {
                        dates.insert(time)
                    }
                }
            }
        }
        return dates.sorted()
    }

    /// 当前时刻是否处于灵动岛时段：课前 reminderLeadMinutes 分钟起，到下课为止
    static func liveCourse(at now: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> LiveCourse? {
        guard let snapshot else { return nil }
        let dayStart = calendar.startOfDay(for: now)
        let phase = SchoolTerm.phase(on: dayStart, semesters: snapshot.semesters, calendar: calendar)
        let lead = TimeInterval(reminderLeadMinutes * 60)
        let parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
        for course in coursesForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar) {
            guard let span = SchoolCalendar.span(of: course),
                  let start = calendar.date(byAdding: .minute, value: span.start, to: dayStart),
                  let end = calendar.date(byAdding: .minute, value: span.end, to: dayStart),
                  now >= start.addingTimeInterval(-lead), now < end else { continue }
            let key = "\(parts.year ?? 0)\(parts.month ?? 0)\(parts.day ?? 0)-\(course.startSession)-\(course.courseName)"
            return LiveCourse(course: course, start: start, end: end, key: key)
        }
        return nil
    }

    private static func nextCourse(after dayStart: Date, snapshot: WidgetSnapshot, calendar: Calendar) -> NextDayCourse? {
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let phase = SchoolTerm.phase(on: day, semesters: snapshot.semesters, calendar: calendar)
            if let course = coursesForDay(day, phase: phase, snapshot: snapshot, calendar: calendar).first {
                return NextDayCourse(course: course, label: offset == 1 ? "明天" : weekdayText(day, calendar: calendar))
            }
        }
        return nil
    }

    private static func weekdayText(_ date: Date, calendar: Calendar) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return "周" + symbols[calendar.component(.weekday, from: date) - 1]
    }

    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

// MARK: - 灵动岛（Live Activity）

struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let startDate: Date
        let endDate: Date
    }

    let key: String
    let courseName: String
    let location: String
    let sessionText: String
}

enum CourseLiveActivityController {
    /// 在灵动岛显示当前课程：同一节课不重复创建；过期活动结束；只保留一个活动
    static func sync(now: Date = .now) async {
        for activity in Activity<CourseActivityAttributes>.activities where activity.content.state.endDate <= now {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let live = WidgetScheduleBuilder.liveCourse(at: now, snapshot: WidgetSnapshotStore.load()) else { return }
        let showing = Activity<CourseActivityAttributes>.activities
        guard !showing.contains(where: { $0.attributes.key == live.key }) else { return }
        for activity in showing {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = CourseActivityAttributes(
            key: live.key,
            courseName: live.course.courseName,
            location: live.course.location,
            sessionText: "\(live.course.startSession)–\(live.course.endSession) 节 · \(SchoolCalendar.rangeText(live.course))"
        )
        let state = CourseActivityAttributes.ContentState(startDate: live.start, endDate: live.end)
        // 系统拒绝（权限、数量上限、后台限制）时静默忽略，下次同步再试
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: live.end),
            pushType: nil
        )
    }

    static func endAll() async {
        for activity in Activity<CourseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// 小组件按钮与控制中心控件使用：不打开 App，即可在后台开启当前课程的灵动岛
struct StartCourseActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "显示当前课程"
    static let description = IntentDescription("在灵动岛显示正在上课或即将开始的课程")

    func perform() async throws -> some IntentResult {
        await CourseLiveActivityController.sync()
        return .result()
    }
}
