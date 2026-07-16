import Foundation

@MainActor @Observable
final class ExamViewModel {
    var isLoading = false
    var hasLoaded = false
    var exams: [UnifiedExamInfo] = []
    var error: String?
    private var service: JWCService?

    func initialize(service: JWCService) { self.service = service }

    func loadExams() {
        guard let svc = service else { return }
        Task {
            isLoading = true; error = nil
            let result = await svc.getExamInfo()
            if result.success { exams = result.data ?? [] } else { error = result.error }
            hasLoaded = true
            isLoading = false
        }
    }
}
