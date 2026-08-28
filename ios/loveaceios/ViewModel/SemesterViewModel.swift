import Foundation
import os
import WidgetKit

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "SemesterViewModel")
private let semesterJSONURL = "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json"

@MainActor @Observable
final class SemesterViewModel {
    var status: SemesterStatus = .loading
    var currentWeek: Int = 0
    var totalWeeks: Int = 18

    func loadSemesterInfo() {
        Task {
            status = .loading
            do {
                guard let url = URL(string: semesterJSONURL) else { throw ServiceError.parseError("URL无效") }
                let (data, _) = try await URLSession.shared.data(from: url)
                let semesterData = try JSONDecoder().decode(SemesterData.self, from: data)
                status = computeStatus(semesterData)
                switch status {
                case .inSession(_, let week, let total, _, _):
                    currentWeek = week
                    totalWeeks = total
                    WidgetDataBridge.saveCurrentWeek(week, totalWeeks: total)
                case .vacation:
                    currentWeek = 0
                    WidgetDataBridge.saveVacationStatus()
                case .loading, .error:
                    break
                }
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                logger.error("Failed to load semester info: \(error.localizedDescription)")
                status = .error(message: "无法获取学期信息")
            }
        }
    }

    private func computeStatus(_ data: SemesterData) -> SemesterStatus {
        let today = Calendar.current.startOfDay(for: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let semesters = data.semesters.sorted { $0.startDate < $1.startDate }
        for sem in semesters {
            guard let start = fmt.date(from: sem.startDate) else { continue }
            let end = Calendar.current.date(byAdding: .weekOfYear, value: sem.weeks, to: start)!
                .addingTimeInterval(-86400)
            let display = sem.displayName()
            if today < start {
                let days = Calendar.current.dateComponents([.day], from: today, to: start).day ?? 0
                return .vacation(nextSemesterName: display, nextStartDate: sem.startDate, daysUntilStart: days)
            }
            if today >= start && today <= end {
                let daysSinceStart = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
                let weekNum = daysSinceStart / 7 + 1
                let remaining = sem.weeks - weekNum
                return .inSession(semesterName: display, currentWeek: weekNum,
                                  totalWeeks: sem.weeks, remainingWeeks: remaining, isEnding: remaining <= 2)
            }
        }
        return .vacation()
    }
}
