enum SemesterStatus {
    case loading
    case vacation(message: String = "假期中", nextSemesterName: String? = nil,
                  nextStartDate: String? = nil, daysUntilStart: Int? = nil)
    case inSession(semesterName: String, currentWeek: Int, totalWeeks: Int,
                   remainingWeeks: Int, isEnding: Bool)
    case error(message: String)
}
