import Foundation

@MainActor @Observable
final class ScheduleViewModel {
    var isLoading = false
    var terms: [TermItem] = []
    var selectedTerm: TermItem?
    var courses: [ScheduleCourse] = []
    var totalUnits: Double = 0
    var error: String?

    private var jwcService: JWCService?
    private var scheduleService: StudentScheduleService?
    private let scheduleStore = ScheduleStore()

    func initialize(jwcService: JWCService, scheduleService: StudentScheduleService) {
        self.jwcService = jwcService; self.scheduleService = scheduleService
    }

    func setActiveUserId(_ userId: String) { scheduleStore.activeUserId = userId }

    func loadTerms() {
        guard let svc = jwcService else { return }
        Task {
            let result = await svc.getAllTerms()
            if result.success, let data = result.data {
                terms = data
                let current = data.first { $0.isCurrent } ?? data.first
                selectedTerm = current
                if let tc = current { loadSchedule(termCode: tc.termCode) }
            }
        }
    }

    func selectTerm(_ term: TermItem) { selectedTerm = term; loadSchedule(termCode: term.termCode) }

    func loadSchedule(termCode: String) {
        guard let svc = scheduleService else { return }
        Task {
            isLoading = true; error = nil
            let result = await svc.getStudentSchedule(termCode: termCode)
            if result.success, let data = result.data {
                courses = data.courses; totalUnits = data.allUnits
                scheduleStore.saveCourses(data.courses)
            } else { error = result.error }
            isLoading = false
        }
    }
}
