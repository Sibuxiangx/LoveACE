import Foundation

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

struct SemesterItem: Codable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let startDate: String
    let weeks: Int

    enum CodingKeys: String, CodingKey {
        case code, name
        case startDate = "start_date"
        case weeks
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

enum SemesterStatus: Equatable {
    case loading
    case vacation(message: String = "假期中", nextSemesterName: String? = nil,
                  nextStartDate: String? = nil, daysUntilStart: Int? = nil)
    case finalExamWeek
    case inSession(semesterName: String, currentWeek: Int, totalWeeks: Int,
                   remainingWeeks: Int, isEnding: Bool)
    case error(message: String)
}
