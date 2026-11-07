import Foundation

@MainActor @Observable
final class MailPasswordViewModel {
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 仅内存中保存；`clear()` 在页面离开时调用
    private(set) var password: MailInitialPassword?
    private(set) var error: String?
    /// 每次加载或清除都递增；旧请求返回时丢弃，离开页面后迟到的结果不会重新写入密码
    private var generation = 0

    func load(service: PortalService?) async {
        generation += 1
        let token = generation
        guard let service else {
            isLoading = false
            error = "请先登录"
            hasLoaded = true
            return
        }
        isLoading = true
        error = nil
        do {
            let value = try await service.mailInitialPassword()
            guard token == generation else { return }
            password = value
        } catch let caught {
            guard token == generation else { return }
            password = nil
            error = PortalErrorMessage.text(for: caught)
        }
        guard token == generation else { return }
        isLoading = false
        hasLoaded = true
    }

    func clear() {
        generation += 1
        password = nil
        error = nil
        isLoading = false
        hasLoaded = false
    }
}
