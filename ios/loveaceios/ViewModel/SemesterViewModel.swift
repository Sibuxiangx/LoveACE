import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "SemesterViewModel")

@MainActor @Observable
final class SemesterViewModel {
    var status: SemesterStatus = .loading
    var currentWeek: Int = 0
    var totalWeeks: Int = 18

    func loadSemesterInfo() {
        Task {
            status = .loading
            do {
                let semesters = try await SemesterFeed.fetch()
                status = Self.status(from: SchoolTerm.phase(on: Date(), semesters: semesters))
                if case .inSession(_, let week, let total, _, _) = status {
                    currentWeek = week
                    totalWeeks = total
                } else {
                    currentWeek = 0
                }
            } catch {
                logger.error("Failed to load semester info: \(error.localizedDescription)")
                status = .error(message: "无法获取学期信息")
            }
        }
    }

    private static func status(from phase: TermPhase?) -> SemesterStatus {
        switch phase {
        case .inSession(let name, let week, let total, let isEnding)?:
            return .inSession(semesterName: name, currentWeek: week, totalWeeks: total,
                              remainingWeeks: total - week, isEnding: isEnding)
        case .vacation(let nextName, let nextStartDate, let days)?:
            return .vacation(nextSemesterName: nextName, nextStartDate: nextStartDate, daysUntilStart: days)
        case nil:
            return .vacation()
        }
    }
}
