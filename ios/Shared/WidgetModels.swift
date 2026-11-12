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

    static func clock(_ minute: Int) -> String {
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

/// yyyy-MM-dd 与当天 0 点的换算（学期开始日与考试日期共用）
enum SchoolDay {
    static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// 某一天所处的学期阶段。周次、假期与考试周都由学期开始日期与快照现算，不依赖 App 何时打开。
enum TermPhase: Equatable {
    case vacation(nextName: String?, nextStartDate: String?, daysUntilStart: Int?)
    case inSession(name: String, week: Int, totalWeeks: Int, isEnding: Bool)
    /// 教学结束后仍有今天或以后的考试：考试周，携带最近一场考试与距今天数
    case examWeek(exam: WidgetExamEntry, daysUntil: Int)
}

enum SchoolTerm {
    /// 某天的学期阶段；学期列表为空时返回 nil（未知，需要同步）。
    /// 教学结束 = 开始日 + 周数 × 7 天（第 weeks+1 周的周一）。教学期内（含第 weeks 周末）为 inSession；
    /// 教学结束后若有今天或以后的考试为 examWeek；其余为 vacation。
    static func phase(
        on date: Date, semesters: [SemesterItem], exams: [WidgetExamEntry], calendar: Calendar = .current
    ) -> TermPhase? {
        guard !semesters.isEmpty else { return nil }
        let today = calendar.startOfDay(for: date)
        let base = basePhase(on: today, semesters: semesters, calendar: calendar)
        let teachingEnded = semesters.contains { semester in
            guard let end = teachingEnd(of: semester, calendar: calendar) else { return false }
            return end <= today
        }
        guard case .vacation = base, teachingEnded,
              let exam = nextExam(from: today, exams: exams, calendar: calendar),
              let examDay = SchoolDay.date(exam.date, calendar: calendar) else { return base }
        let days = calendar.dateComponents([.day], from: today, to: examDay).day ?? 0
        return .examWeek(exam: exam, daysUntil: days)
    }

    /// 教学结束日（第 weeks+1 周的周一）；开始日无法解析时为 nil
    static func teachingEnd(of semester: SemesterItem, calendar: Calendar = .current) -> Date? {
        guard let start = SchoolDay.date(semester.startDate, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: semester.weeks * 7, to: start)
    }

    private static func basePhase(on today: Date, semesters: [SemesterItem], calendar: Calendar) -> TermPhase {
        for semester in semesters.sorted(by: { $0.startDate < $1.startDate }) {
            guard let start = SchoolDay.date(semester.startDate, calendar: calendar),
                  let end = teachingEnd(of: semester, calendar: calendar) else { continue }
            if today < start {
                let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
                return .vacation(nextName: semester.displayName(), nextStartDate: semester.startDate, daysUntilStart: days)
            }
            if today < end {
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

    /// 今天及以后最近的一场考试（先按日期，再按开始时间）；日期无法解析的忽略
    private static func nextExam(from today: Date, exams: [WidgetExamEntry], calendar: Calendar) -> WidgetExamEntry? {
        exams
            .compactMap { exam -> (exam: WidgetExamEntry, day: Date)? in
                guard let day = SchoolDay.date(exam.date, calendar: calendar), day >= today else { return nil }
                return (exam, day)
            }
            .min { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day < rhs.day }
                return (lhs.exam.minuteSpan?.start ?? Int.max) < (rhs.exam.minuteSpan?.start ?? Int.max)
            }?.exam
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

/// 一场考试（教务考试查询）。date 为 yyyy-MM-dd；timeText 为学校原文（如 "14:00-16:00"），不一定能解析
struct WidgetExamEntry: Codable, Identifiable, Equatable {
    var id: String { "\(date)_\(courseName)_\(timeText)" }
    let courseName: String
    let date: String
    let timeText: String
    let location: String

    /// 学校原文中的开始、结束分钟（自当天 0:00 起）；无法解析出两个时刻时为 nil
    var minuteSpan: (start: Int, end: Int)? {
        let minutes = timeText.matches(of: #/(\d{1,2}):(\d{2})/#).compactMap { match -> Int? in
            guard let hour = Int(match.output.1), let minute = Int(match.output.2) else { return nil }
            return hour * 60 + minute
        }
        guard minutes.count >= 2, minutes[1] > minutes[0] else { return nil }
        return (minutes[0], minutes[1])
    }

    /// 界面上的时间：能解析时为 HH:mm–HH:mm，否则保留学校原文
    var rangeText: String {
        guard let span = minuteSpan else { return timeText.isEmpty ? "时间待定" : timeText }
        return "\(SchoolCalendar.clock(span.start))–\(SchoolCalendar.clock(span.end))"
    }
}

/// 课表中的一项：课程（按节次）或考试（按时刻）。今日列表、下一项、灵动岛与时间线共用同一套切换规则。
enum ScheduleItem: Identifiable, Equatable {
    case course(WidgetCourseEntry)
    case exam(WidgetExamEntry)

    var id: String {
        switch self {
        case .course(let course): return "course-\(course.id)"
        case .exam(let exam): return "exam-\(exam.id)"
        }
    }

    var isExam: Bool {
        if case .exam = self { return true }
        return false
    }

    var courseName: String {
        switch self {
        case .course(let course): return course.courseName
        case .exam(let exam): return exam.courseName
        }
    }

    var location: String {
        switch self {
        case .course(let course): return course.location
        case .exam(let exam): return exam.location
        }
    }

    /// 开始、结束分钟（自当天 0:00 起）；考试时间无法解析时为 nil
    var minuteSpan: (start: Int, end: Int)? {
        switch self {
        case .course(let course): return SchoolCalendar.span(of: course)
        case .exam(let exam): return exam.minuteSpan
        }
    }

    /// 列表中的时间范围
    var rangeText: String {
        switch self {
        case .course(let course): return SchoolCalendar.rangeText(course)
        case .exam(let exam): return exam.rangeText
        }
    }

    /// 开始时间文字
    var startText: String {
        switch self {
        case .course(let course): return SchoolCalendar.startText(course)
        case .exam(let exam):
            guard let span = exam.minuteSpan else { return exam.rangeText }
            return SchoolCalendar.clock(span.start)
        }
    }

    /// 灵动岛与锁屏的副文字
    var sessionText: String {
        switch self {
        case .course(let course): return "\(course.startSession)–\(course.endSession) 节 · \(rangeText)"
        case .exam: return "考试 · \(rangeText)"
        }
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
    /// 考试；旧快照没有此字段时为 nil，含义与空数组相同（没有考试）
    let exams: [WidgetExamEntry]?

    var examList: [WidgetExamEntry] { exams ?? [] }

    init(
        userId: String, updatedAt: Date, semesters: [SemesterItem], termCode: String,
        courses: [WidgetCourseEntry], exams: [WidgetExamEntry]? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.userId = userId
        self.updatedAt = updatedAt
        self.semesters = semesters
        self.termCode = termCode
        self.courses = courses
        self.exams = exams
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

/// 今日无项目时，之后最近的一项（课程或考试）
struct NextDayItem {
    let item: ScheduleItem
    /// "明天" 或 "周X"
    let label: String
}

/// 正在进行中的项目（灵动岛只在上课时段显示）
struct LiveItem {
    let item: ScheduleItem
    let start: Date
    let end: Date
    /// 同一天同一项的稳定标识，用于避免重复创建灵动岛
    let key: String
}

struct WidgetScheduleState {
    let date: Date
    /// nil 表示未同步（快照缺失或学期列表为空）
    let phase: TermPhase?
    /// 今日全部课程与考试，按开始时间排序
    let today: [ScheduleItem]
    /// 今日尚未结束的项目（含进行中）
    let upcoming: [ScheduleItem]
    let inProgress: ScheduleItem?
    /// 下一项：进行中的项目，否则结束时间未到的最早项目。上一项结束后即切换到下一项（考试同样）
    let next: ScheduleItem?
    /// 今日无项目时，之后最近的一项
    let nextDay: NextDayItem?
    /// 正在进行中的项目（灵动岛只在上课时段显示）
    let liveItem: LiveItem?
    let lastSyncedAt: Date?

    var isSynced: Bool { phase != nil }

    var isStale: Bool {
        guard let lastSyncedAt else { return false }
        return date.timeIntervalSince(lastSyncedAt) > 24 * 3600
    }
}

enum WidgetScheduleBuilder {
    /// 上课前多久发送本地提醒（灵动岛不提前显示）
    static let reminderLeadMinutes = 10

    static func state(at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> WidgetScheduleState {
        guard let snapshot else {
            return WidgetScheduleState(
                date: date, phase: nil, today: [], upcoming: [], inProgress: nil, next: nil,
                nextDay: nil, liveItem: nil, lastSyncedAt: nil
            )
        }
        let phase = SchoolTerm.phase(on: date, semesters: snapshot.semesters, exams: snapshot.examList, calendar: calendar)
        let dayStart = calendar.startOfDay(for: date)
        let today = itemsForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar)
        let minute = minuteOfDay(date, calendar)
        // 结束时刻未到的项目；无法解析时间的考试没有结束时刻，一直保留到当天结束
        let upcoming = today.filter { ($0.minuteSpan?.end ?? Int.max) > minute }
        let inProgress = today.first { item in
            guard let span = item.minuteSpan else { return false }
            return minute >= span.start && minute < span.end
        }
        return WidgetScheduleState(
            date: date,
            phase: phase,
            today: today,
            upcoming: upcoming,
            inProgress: inProgress,
            next: inProgress ?? upcoming.first,
            nextDay: today.isEmpty ? nextItem(after: dayStart, snapshot: snapshot, calendar: calendar) : nil,
            liveItem: liveItem(at: date, snapshot: snapshot, calendar: calendar),
            lastSyncedAt: snapshot.updatedAt
        )
    }

    /// 某天（0 点）的课程与考试：仅学期内生效；课程按周次过滤；按开始时间排序，无时间的考试排最后
    static func itemsForDay(
        _ dayStart: Date, phase: TermPhase?, snapshot: WidgetSnapshot, calendar: Calendar = .current
    ) -> [ScheduleItem] {
        guard case .inSession(_, let week, _, _)? = phase else { return [] }
        let weekday = calendar.component(.weekday, from: dayStart)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let courses = snapshot.courses
            .filter { $0.dayOfWeek == isoWeekday && ($0.classWeek.isEmpty || $0.isActiveInWeek(week)) }
            .map(ScheduleItem.course)
        let exams = snapshot.examList
            .filter { SchoolDay.date($0.date, calendar: calendar) == dayStart }
            .map(ScheduleItem.exam)
        return (courses + exams).sorted { lhs, rhs in
            ((lhs.minuteSpan?.start ?? Int.max), lhs.id) < ((rhs.minuteSpan?.start ?? Int.max), rhs.id)
        }
    }

    /// 时间线需要切换的时刻：now，以及今天、明天每项的开始与结束，以及明天 0 点
    static func transitionDates(from now: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> [Date] {
        guard let snapshot,
              let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        else { return [now] }
        var dates: Set<Date> = [now, startOfTomorrow]
        for dayStart in [calendar.startOfDay(for: now), startOfTomorrow] {
            let phase = SchoolTerm.phase(on: dayStart, semesters: snapshot.semesters, exams: snapshot.examList, calendar: calendar)
            for item in itemsForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar) {
                guard let span = item.minuteSpan else { continue }
                for minute in [span.start, span.end] {
                    if let time = calendar.date(byAdding: .minute, value: minute, to: dayStart), time > now {
                        dates.insert(time)
                    }
                }
            }
        }
        return dates.sorted()
    }

    /// 当前时刻是否处于灵动岛时段：上课（或考试）进行中，即 start <= now < end。课程与考试共用此规则
    static func liveItem(at now: Date, snapshot: WidgetSnapshot?, calendar: Calendar = .current) -> LiveItem? {
        guard let snapshot else { return nil }
        let dayStart = calendar.startOfDay(for: now)
        let phase = SchoolTerm.phase(on: dayStart, semesters: snapshot.semesters, exams: snapshot.examList, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
        for item in itemsForDay(dayStart, phase: phase, snapshot: snapshot, calendar: calendar) {
            guard let span = item.minuteSpan,
                  let start = calendar.date(byAdding: .minute, value: span.start, to: dayStart),
                  let end = calendar.date(byAdding: .minute, value: span.end, to: dayStart),
                  now >= start, now < end else { continue }
            let key = "\(parts.year ?? 0)\(parts.month ?? 0)\(parts.day ?? 0)-\(item.id)"
            return LiveItem(item: item, start: start, end: end, key: key)
        }
        return nil
    }

    private static func nextItem(after dayStart: Date, snapshot: WidgetSnapshot, calendar: Calendar) -> NextDayItem? {
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let phase = SchoolTerm.phase(on: day, semesters: snapshot.semesters, exams: snapshot.examList, calendar: calendar)
            if let item = itemsForDay(day, phase: phase, snapshot: snapshot, calendar: calendar).first {
                return NextDayItem(item: item, label: offset == 1 ? "明天" : weekdayText(day, calendar: calendar))
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
              let live = WidgetScheduleBuilder.liveItem(at: now, snapshot: WidgetSnapshotStore.load()) else { return }
        let showing = Activity<CourseActivityAttributes>.activities
        guard !showing.contains(where: { $0.attributes.key == live.key }) else { return }
        for activity in showing {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = CourseActivityAttributes(
            key: live.key,
            courseName: live.item.courseName,
            location: live.item.location,
            sessionText: live.item.sessionText
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
    static let description = IntentDescription("在灵动岛显示正在上课的课程")

    func perform() async throws -> some IntentResult {
        await CourseLiveActivityController.sync()
        return .result()
    }
}
