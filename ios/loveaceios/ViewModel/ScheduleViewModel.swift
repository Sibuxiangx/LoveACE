import Foundation
import WidgetKit

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
                let shouldSyncWidget = terms.first { $0.termCode == termCode }?.isCurrent == true
                if shouldSyncWidget {
                    Self.syncToWidget(data.courses)
                }
            } else { error = result.error }
            isLoading = false
        }
    }

    private static func syncToWidget(_ courses: [ScheduleCourse]) {
        var entries: [WidgetCourseEntry] = []
        for course in courses {
            for tp in course.timeAndPlaceList {
                entries.append(WidgetCourseEntry(
                    courseName: course.courseName,
                    location: tp.locationDescription,
                    teacher: course.attendClassTeacher,
                    dayOfWeek: tp.classDay,
                    startSession: tp.classSessions,
                    endSession: tp.endSession,
                    weekDescription: tp.weekDescription,
                    classWeek: tp.classWeek
                ))
            }
        }
        WidgetDataBridge.saveCourses(entries)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
