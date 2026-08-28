import Foundation

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

    func isActiveInWeek(_ week: Int) -> Bool {
        guard week > 0, week <= classWeek.count else { return false }
        let idx = classWeek.index(classWeek.startIndex, offsetBy: week - 1)
        return classWeek[idx] == "1"
    }
}

enum WidgetDataBridge {
    static let suiteName = "group.cn.linota.loveace"
    private static let semesterStatusKey = "widget_semester_in_session"

    static func saveCourses(_ courses: [WidgetCourseEntry]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(courses) else { return }
        defaults.set(data, forKey: "widget_courses")
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_updated")
    }

    static func loadCourses() -> [WidgetCourseEntry] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: "widget_courses"),
              let courses = try? JSONDecoder().decode([WidgetCourseEntry].self, from: data)
        else { return [] }
        return courses
    }

    static func saveCurrentWeek(_ week: Int, totalWeeks: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(true, forKey: semesterStatusKey)
        defaults.set(week, forKey: "widget_current_week")
        defaults.set(totalWeeks, forKey: "widget_total_weeks")
    }

    static func saveVacationStatus() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(false, forKey: semesterStatusKey)
        defaults.removeObject(forKey: "widget_current_week")
    }

    static func isInSession() -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.object(forKey: semesterStatusKey) != nil else { return true }
        return defaults.bool(forKey: semesterStatusKey)
    }

    static func loadCurrentWeek() -> Int? {
        guard isInSession() else { return nil }
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        let val = defaults.integer(forKey: "widget_current_week")
        return val > 0 ? val : nil
    }

    static func loadTotalWeeks() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return 18 }
        let val = defaults.integer(forKey: "widget_total_weeks")
        return val > 0 ? val : 18
    }

    static func todayCourses(on date: Date = Date()) -> [WidgetCourseEntry] {
        guard isInSession() else { return [] }
        let weekday = Calendar.current.component(.weekday, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let currentWeek = loadCurrentWeek()
        return loadCourses()
            .filter { entry in
                guard entry.dayOfWeek == isoWeekday else { return false }
                if let week = currentWeek, !entry.classWeek.isEmpty {
                    return entry.isActiveInWeek(week)
                }
                return true
            }
            .sorted { $0.startSession < $1.startSession }
    }

    static func nextCourse(on date: Date = Date()) -> WidgetCourseEntry? {
        let today = todayCourses(on: date)
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        for course in today {
            let start = sessionStartMinutes[course.startSession] ?? 0
            let end = sessionEndMinutes[course.endSession]
                ?? sessionStartMinutes[course.endSession + 1]
                ?? 21 * 60
            if end > currentMinutes {
                return course
            }
        }
        return nil
    }

    static func isCourseInProgress(_ course: WidgetCourseEntry, at date: Date) -> Bool {
        let currentMinutes = Calendar.current.component(.hour, from: date) * 60
            + Calendar.current.component(.minute, from: date)
        let start = sessionStartMinutes[course.startSession] ?? 0
        let end = sessionEndMinutes[course.endSession]
            ?? sessionStartMinutes[course.endSession + 1]
            ?? 21 * 60
        return currentMinutes >= start && currentMinutes < end
    }

    static func timelineDates(from date: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        var dates: Set<Date> = [date]

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if day > date { dates.insert(day) }
            for course in todayCourses(on: day) {
                let start = sessionStartMinutes[course.startSession] ?? 0
                let end = sessionEndMinutes[course.endSession]
                    ?? sessionStartMinutes[course.endSession + 1]
                    ?? 21 * 60
                for minutes in [start, end] {
                    guard let transition = calendar.date(byAdding: .minute, value: minutes, to: day),
                          transition > date else { continue }
                    dates.insert(transition)
                }
            }
        }
        return dates.sorted()
    }

    private static let sessionStartMinutes: [Int: Int] = [
        1: 480, 2: 530, 3: 600, 4: 650,
        5: 840, 6: 890, 7: 960, 8: 1010,
        9: 1110, 10: 1160, 11: 1210
    ]

    private static let sessionEndMinutes: [Int: Int] = [
        1: 530, 2: 600, 3: 650, 4: 840,
        5: 890, 6: 960, 7: 1010, 8: 1110,
        9: 1160, 10: 1210, 11: 1260
    ]

    static func sessionTimeString(_ session: Int) -> String {
        let times = [
            1: "08:00", 2: "08:50", 3: "10:00", 4: "10:50",
            5: "14:00", 6: "14:50", 7: "16:00", 8: "16:50",
            9: "18:30", 10: "19:20", 11: "20:10"
        ]
        return times[session] ?? "\(session)节"
    }
}
