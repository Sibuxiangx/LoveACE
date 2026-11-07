import Foundation

@MainActor @Observable
final class MailPasswordViewModel {
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 仅内存中保存；`clear()` 在页面离开时调用
    private(set) var password: MailInitialPassword?
    private(set) var error: String?

    func load(service: PortalService?) async {
        guard let service else {
            error = "请先登录"
            hasLoaded = true
            return
        }
        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            password = try await service.mailInitialPassword()
        } catch {
            password = nil
            self.error = PortalErrorMessage.text(for: error)
        }
    }

    func clear() {
        password = nil
    }
}
