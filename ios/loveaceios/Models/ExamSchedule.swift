import Foundation

enum HomeExamPeriod {
    case today
    case thisWeek
    case upcoming

    var title: String {
        switch self {
        case .today: "今日考试"
        case .thisWeek: "本周考试"
        case .upcoming: "最近考试"
        }
    }
}

struct HomeExamOverview {
    let period: HomeExamPeriod
    let exams: [UnifiedExamInfo]
}

enum ExamSchedule {
    private struct ParsedExam {
        let exam: UnifiedExamInfo
        let date: Date
        let startsAt: Date
        let endsAt: Date
    }

    private static let timePattern = try! NSRegularExpression(
        pattern: #"(?:[01]?\d|2[0-3]):[0-5]\d"#
    )

    static func homeOverview(
        exams: [UnifiedExamInfo],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeExamOverview? {
        let pending = exams.compactMap { parseExam($0, calendar: calendar) }
            .filter { $0.endsAt > now }
            .sorted {
                if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                return $0.exam.courseName.localizedCompare($1.exam.courseName) == .orderedAscending
            }
        guard !pending.isEmpty else { return nil }

        let today = pending.filter { calendar.isDate($0.date, inSameDayAs: now) }
        if !today.isEmpty {
            return HomeExamOverview(period: .today, exams: today.map(\.exam))
        }

        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        if let weekEnd = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.end {
            let thisWeek = pending.filter { $0.date < weekEnd }
            if !thisWeek.isEmpty {
                return HomeExamOverview(period: .thisWeek, exams: thisWeek.map(\.exam))
            }
        }

        let nearestDate = pending[0].date
        let nearest = pending.filter { calendar.isDate($0.date, inSameDayAs: nearestDate) }
        return HomeExamOverview(period: .upcoming, exams: nearest.map(\.exam))
    }

    private static func parseExam(_ exam: UnifiedExamInfo, calendar: Calendar) -> ParsedExam? {
        guard let date = parseDate(exam.examDate, calendar: calendar) else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        let times = parseTimes(exam.examTime)
        let startsAt = times.first.flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: dayStart)
        } ?? dayStart
        let endsAt: Date
        if times.count >= 2, let last = times.last {
            endsAt = calendar.date(
                bySettingHour: last.hour,
                minute: last.minute,
                second: 0,
                of: dayStart
            ) ?? dayStart
        } else {
            endsAt = calendar.date(byAdding: .day, value: 1, to: dayStart)?
                .addingTimeInterval(-0.001) ?? dayStart
        }
        return ParsedExam(exam: exam, date: dayStart, startsAt: startsAt, endsAt: endsAt)
    }

    private static func parseDate(_ value: String, calendar: Calendar) -> Date? {
        if let range = value.range(
            of: #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#,
            options: .regularExpression
        ) {
            let parts = value[range].split { $0 == "-" || $0 == "/" || $0 == "." }
            if parts.count == 3,
               let year = Int(parts[0]),
               let month = Int(parts[1]),
               let day = Int(parts[2]) {
                return calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
        }

        if let range = value.range(of: #"\d{8}"#, options: .regularExpression) {
            let compact = String(value[range])
            guard let year = Int(compact.prefix(4)),
                  let month = Int(compact.dropFirst(4).prefix(2)),
                  let day = Int(compact.suffix(2)) else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        return nil
    }

    private static func parseTimes(_ value: String) -> [(hour: Int, minute: Int)] {
        let range = NSRange(value.startIndex..., in: value)
        return timePattern.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            let parts = value[matchRange].split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { return nil }
            return (hour, minute)
        }
    }
}
