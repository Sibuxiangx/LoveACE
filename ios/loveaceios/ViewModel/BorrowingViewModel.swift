import Foundation

@MainActor @Observable
final class BorrowingViewModel {
    private(set) var isLoading = false
    private(set) var current: [BorrowRecord] = []
    private(set) var history: [BorrowRecord] = []
    /// 已加载过数据时，刷新失败只提示错误并保留原列表；首次加载失败才进入错误态
    private(set) var error: String?
    private(set) var loaded = false
    /// 每次加载递增；旧请求返回时丢弃，避免两次加载互相覆盖
    private var generation = 0

    func load(service: PortalService?) async {
        generation += 1
        let token = generation
        guard let service else {
            isLoading = false
            error = "请先登录"
            return
        }
        isLoading = true
        error = nil
        do {
            let result = try await service.borrowing()
            guard token == generation else { return }
            current = result.current
            history = result.history
            loaded = true
        } catch let caught {
            guard token == generation else { return }
            error = PortalErrorMessage.text(for: caught)
        }
        guard token == generation else { return }
        isLoading = false
    }
}
