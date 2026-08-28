import WidgetKit
import SwiftUI

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let courses: [WidgetCourseEntry]
    let nextCourse: WidgetCourseEntry?
    let currentWeek: Int?
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), courses: [
            WidgetCourseEntry(courseName: "高等数学", location: "教1-301", teacher: "张老师",
                            dayOfWeek: 1, startSession: 1, endSession: 2,
                            weekDescription: "1-16周", classWeek: "0111111111111111100000000")
        ], nextCourse: nil, currentWeek: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let courses = WidgetDataBridge.todayCourses()
        let week = WidgetDataBridge.loadCurrentWeek()
        completion(ScheduleEntry(date: Date(), courses: courses,
                                nextCourse: WidgetDataBridge.nextCourse(), currentWeek: week))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let entries = WidgetDataBridge.timelineDates().map { date in
            ScheduleEntry(
                date: date,
                courses: WidgetDataBridge.todayCourses(on: date),
                nextCourse: WidgetDataBridge.nextCourse(on: date),
                currentWeek: WidgetDataBridge.loadCurrentWeek()
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SmallScheduleView: View {
    let entry: ScheduleEntry

    var body: some View {
        if let next = entry.nextCourse {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(WidgetDataBridge.isCourseInProgress(next, at: entry.date) ? "正在上课" : "下节课")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let week = entry.currentWeek {
                        Text("第\(week)周")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(next.courseName)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Label(WidgetDataBridge.sessionTimeString(next.startSession), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !next.location.isEmpty {
                    Label(next.location, systemImage: "mappin")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        } else if !WidgetDataBridge.isInSession() {
            VStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("假期中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entry.courses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("今日无课")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let week = entry.currentWeek {
                    Text("第\(week)周")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("今日课程已结束")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MediumScheduleView: View {
    let entry: ScheduleEntry

    var body: some View {
        if !WidgetDataBridge.isInSession() {
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("假期中")
                        .font(.headline)
                    Text("好好休息吧")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
        } else if entry.courses.isEmpty {
            HStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日无课")
                        .font(.headline)
                    if let week = entry.currentWeek {
                        Text("第\(week)周")
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
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("今日课程", systemImage: "calendar")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Spacer()
                    if let week = entry.currentWeek {
                        Text("第\(week)周")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text("\(entry.courses.count) 节")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(entry.courses.prefix(3)) { course in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(course == entry.nextCourse ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(course.courseName)
                                .font(.caption)
                                .fontWeight(course == entry.nextCourse ? .semibold : .regular)
                                .lineLimit(1)
                            Text("\(WidgetDataBridge.sessionTimeString(course.startSession)) · \(course.location)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .frame(height: 28)
                }

                if entry.courses.count > 3 {
                    Text("还有 \(entry.courses.count - 3) 节课...")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
        }
    }
}

extension WidgetCourseEntry: Equatable {
    static func == (lhs: WidgetCourseEntry, rhs: WidgetCourseEntry) -> Bool {
        lhs.id == rhs.id
    }
}

@main
struct LoveACEWidget: Widget {
    let kind = "LoveACEScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    ScheduleWidgetView(entry: entry)
                        .containerBackground(.fill.tertiary, for: .widget)
                } else {
                    ScheduleWidgetView(entry: entry)
                        .padding()
                        .background()
                }
            }
        }
        .configurationDisplayName("今日课程")
        .description("查看今天的课程安排和下一节课信息")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ScheduleEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallScheduleView(entry: entry)
        case .systemMedium:
            MediumScheduleView(entry: entry)
        default:
            SmallScheduleView(entry: entry)
        }
    }
}
