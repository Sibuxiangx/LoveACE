import Foundation

@MainActor @Observable
final class BorrowingViewModel {
    private(set) var isLoading = false
    private(set) var current: [BorrowRecord] = []
    private(set) var history: [BorrowRecord] = []
    private(set) var error: String?
    private(set) var loaded = false

    func load(service: PortalService?) async {
        guard let service else {
            error = "请先登录"
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await service.borrowing()
            current = result.current
            history = result.history
            loaded = true
        } catch {
            current = []
            history = []
            loaded = false
            self.error = PortalErrorMessage.text(for: error)
        }
    }
}
