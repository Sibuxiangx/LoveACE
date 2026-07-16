import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "SemesterViewModel")
private let semesterJSONURL = "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json"

@MainActor @Observable
final class SemesterViewModel {
    var status: SemesterStatus = .loading
    var currentWeek: Int = 0
    var totalWeeks: Int = 18
    private var semesterData: SemesterData?
    private var hasPendingExams = false

    func loadSemesterInfo() {
        Task {
            status = .loading
            do {
                guard let url = URL(string: semesterJSONURL) else { throw ServiceError.parseError("URL无效") }
                let (data, _) = try await URLSession.shared.data(from: url)
                let semesterData = try JSONDecoder().decode(SemesterData.self, from: data)
                self.semesterData = semesterData
                status = computeStatus(semesterData, hasPendingExams: hasPendingExams)
                if case .inSession(_, let week, let total, _, _) = status {
                    currentWeek = week
                    totalWeeks = total
                    WidgetDataBridge.saveCurrentWeek(week, totalWeeks: total)
                }
            } catch {
                logger.error("Failed to load semester info: \(error.localizedDescription)")
                status = .error(message: "无法获取学期信息")
            }
        }
    }

    func updatePendingExamStatus(_ hasPendingExams: Bool, now: Date = Date()) {
        self.hasPendingExams = hasPendingExams
        guard let semesterData else { return }
        switch status {
        case .loading, .error:
            return
        default:
            break
        }
        let nextStatus = computeStatus(semesterData, hasPendingExams: hasPendingExams, now: now)
        if status != nextStatus { status = nextStatus }
    }

    private func computeStatus(
        _ data: SemesterData,
        hasPendingExams: Bool,
        now: Date = Date()
    ) -> SemesterStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let semesters = data.semesters.sorted { $0.startDate < $1.startDate }
        var latestSemesterEnd: Date?
        for sem in semesters {
            guard let start = fmt.date(from: sem.startDate) else { continue }
            guard let boundary = calendar.date(byAdding: .weekOfYear, value: sem.weeks, to: start),
                  let end = calendar.date(byAdding: .day, value: -1, to: boundary) else { continue }
            let display = sem.displayName()
            if today < start {
                if hasPendingExams, let latestSemesterEnd, today > latestSemesterEnd {
                    return .finalExamWeek
                }
                let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
                return .vacation(nextSemesterName: display, nextStartDate: sem.startDate, daysUntilStart: days)
            }
            if today >= start && today <= end {
                let daysSinceStart = calendar.dateComponents([.day], from: start, to: today).day ?? 0
                let weekNum = daysSinceStart / 7 + 1
                let remaining = sem.weeks - weekNum
                return .inSession(semesterName: display, currentWeek: weekNum,
                                  totalWeeks: sem.weeks, remainingWeeks: remaining, isEnding: remaining <= 2)
            }
            latestSemesterEnd = end
        }
        if hasPendingExams, let latestSemesterEnd, today > latestSemesterEnd {
            return .finalExamWeek
        }
        return .vacation()
    }
}
