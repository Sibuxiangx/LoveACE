import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let state: WidgetScheduleState
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, state: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let now = Date()
        completion(ScheduleEntry(date: now, state: WidgetScheduleBuilder.state(at: now, snapshot: WidgetSnapshotStore.load())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        // 整条时间线只读取一次快照
        let snapshot = WidgetSnapshotStore.load()
        let entries = WidgetScheduleBuilder.transitionDates(from: now, snapshot: snapshot).map { date in
            ScheduleEntry(date: date, state: WidgetScheduleBuilder.state(at: date, snapshot: snapshot))
        }
        let calendar = Calendar.current
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        // 未同步时每小时检查一次；已同步则在次日 0 点之后重新生成时间线（同步成功时 App 也会主动 reload）
        let refresh = snapshot == nil ? now.addingTimeInterval(3_600) : nextMidnight.addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

extension WidgetScheduleState {
    /// 占位与图库预览用的示例数据
    static var sample: WidgetScheduleState {
        let course = WidgetCourseEntry(
            courseName: "高等数学", location: "教1-301", teacher: "张老师",
            dayOfWeek: 1, startSession: 1, endSession: 2,
            weekDescription: "1-16周", classWeek: "0111111111111111100000000"
        )
        return WidgetScheduleState(
            date: .now,
            phase: .inSession(name: "2025-2026学年 第一学期", week: 5, totalWeeks: 18, isEnding: false),
            today: [course], upcoming: [course], inProgress: nil, next: course,
            nextDay: nil, liveCourse: nil, lastSyncedAt: .now
        )
    }
}

// MARK: - Widget

struct LoveACEWidget: Widget {
    let kind = "LoveACEScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日课程")
        .description("查看今天的课程、下一节课和假期倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LoveACEWidgetBundle: WidgetBundle {
    var body: some Widget {
        LoveACEWidget()
        CourseLiveActivityWidget()
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        if family == .systemMedium {
            MediumScheduleView(state: entry.state)
        } else {
            SmallScheduleView(state: entry.state)
        }
    }
}

// MARK: - Small

struct SmallScheduleView: View {
    let state: WidgetScheduleState

    var body: some View {
        if !state.isSynced {
            NotSyncedView()
        } else if case .vacation(let name, _, let days)? = state.phase {
            VacationView(nextName: name, days: days, compact: true)
        } else if let next = state.next {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(state.inProgress != nil ? "正在上课" : "下节课")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    WeekTag(phase: state.phase, compact: true)
                }

                Text(next.courseName)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Label(SchoolCalendar.startText(next), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !next.location.isEmpty {
                    Label(next.location, systemImage: "mappin")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                FooterNote(state: state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        } else if state.today.isEmpty {
            EmptyDayView(state: state, compact: true)
        } else {
            AllFinishedView(count: state.today.count, compact: true)
        }
    }
}

// MARK: - Medium

struct MediumScheduleView: View {
    let state: WidgetScheduleState

    var body: some View {
        if !state.isSynced {
            NotSyncedView()
        } else if case .vacation(let name, _, let days)? = state.phase {
            VacationView(nextName: name, days: days, compact: false)
        } else if state.today.isEmpty {
            EmptyDayView(state: state, compact: false)
        } else if state.upcoming.isEmpty {
            AllFinishedView(count: state.today.count, compact: false)
        } else {
            CourseListView(state: state)
        }
    }
}

/// 只展示尚未结束的课程（进行中的排在最前），超出部分显示计数
struct CourseListView: View {
    let state: WidgetScheduleState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("今日课程", systemImage: "calendar")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Spacer()
                WeekTag(phase: state.phase, compact: false)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text("\(state.today.count) 节")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if state.liveCourse != nil {
                    Button(intent: StartCourseActivityIntent()) {
                        Image(systemName: "timer")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(state.upcoming.prefix(3)) { course in
                CourseRow(course: course, isNext: course.id == state.next?.id)
            }

            if state.upcoming.count > 3 {
                Text("还有 \(state.upcoming.count - 3) 节课...")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            FooterNote(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(2)
    }
}

struct CourseRow: View {
    let course: WidgetCourseEntry
    let isNext: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isNext ? Color.blue : Color.secondary.opacity(0.3))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(course.courseName)
                    .font(.caption)
                    .fontWeight(isNext ? .semibold : .regular)
                    .lineLimit(1)
                Text("\(SchoolCalendar.rangeText(course)) · \(course.location)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(height: 28)
    }
}

// MARK: - Shared states

struct NotSyncedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("等待同步")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("打开 App 同步课表")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VacationView: View {
    let nextName: String?
    let days: Int?
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("假期中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let days {
                    Text("\(days) 天后开学")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("假期中")
                        .font(.headline)
                    if let days {
                        Text("\(days) 天后开学 · \(nextName ?? "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("好好休息吧")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
        }
    }
}

struct EmptyDayView: View {
    let state: WidgetScheduleState
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("今日无课")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                nextDayText
                WeekTag(phase: state.phase, compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日无课")
                        .font(.headline)
                    nextDayText
                    WeekTag(phase: state.phase, compact: false)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
        }
    }

    @ViewBuilder
    private var nextDayText: some View {
        if let nextDay = state.nextDay {
            Text("\(nextDay.label) \(SchoolCalendar.startText(nextDay.course)) · \(nextDay.course.courseName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("好好休息吧")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct AllFinishedView: View {
    let count: Int
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("今日课程已结束")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日课程已结束")
                        .font(.headline)
                    Text("今日共 \(count) 节")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
        }
    }
}

/// 第 N 周标签（仅学期内显示）
struct WeekTag: View {
    let phase: TermPhase?
    let compact: Bool

    var body: some View {
        if case .inSession(_, let week, _, _)? = phase {
            Text("第\(week)周")
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// 底部提示：学期即将结束优先，其次是超过 24 小时未同步
struct FooterNote: View {
    let state: WidgetScheduleState

    var body: some View {
        if case .inSession(_, let week, let total, true)? = state.phase {
            Text("第\(week)/\(total)周 · 学期即将结束")
                .font(.system(size: 9))
                .foregroundStyle(.red)
        } else if state.isStale, let synced = state.lastSyncedAt {
            HStack(spacing: 0) {
                Text("上次同步 ")
                Text(synced, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Live Activity（锁屏与灵动岛）

struct CourseActivityWidgetCountdown: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        if Date.now < state.startDate {
            Text(timerInterval: Date.now...state.startDate, pauseTime: state.startDate, countsDown: true)
        } else {
            Text(timerInterval: Date.now...state.endDate, pauseTime: state.endDate, countsDown: true)
        }
    }
}

struct CourseLockScreenView: View {
    let attributes: CourseActivityAttributes
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.courseName)
                        .font(.headline)
                        .lineLimit(1)
                    if !attributes.location.isEmpty {
                        Text(attributes.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Date.now < state.startDate ? "距上课" : "距下课")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    CourseActivityWidgetCountdown(state: state)
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                }
            }
            ProgressView(timerInterval: state.startDate...state.endDate, countsDown: false)
                .tint(.blue)
            Text(attributes.sessionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseLockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.courseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CourseActivityWidgetCountdown(state: context.state)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: false)
                            .tint(.blue)
                        Text(context.attributes.location.isEmpty ? context.attributes.sessionText : "\(context.attributes.location) · \(context.attributes.sessionText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                CourseActivityWidgetCountdown(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}
