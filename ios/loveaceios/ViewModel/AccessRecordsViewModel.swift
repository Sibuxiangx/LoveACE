import Foundation

@MainActor @Observable
final class AccessRecordsViewModel {
    private(set) var kind: AccessKind = .dormitory
    private(set) var range: AccessRange = .thisWeek
    private(set) var records: [AccessRecord] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var loadMoreError: String?
    private(set) var loadedPage = 0
    /// 每次查询条件变化或重新加载都会递增；旧请求返回时 generation 对不上就丢弃，也不改 loading 状态
    private var generation = 0

    var hasMore: Bool { records.count < total }

    /// 切换类型：立即清空结果并进入加载态，避免显示旧类型的数据或误报"暂无记录"
    func select(kind newKind: AccessKind) {
        guard newKind != kind else { return }
        kind = newKind
        resetForNewQuery()
    }

    func select(range newRange: AccessRange) {
        guard newRange != range else { return }
        range = newRange
        resetForNewQuery()
    }

    private func resetForNewQuery() {
        generation += 1
        records = []
        total = 0
        loadedPage = 0
        error = nil
        loadMoreError = nil
        isLoading = true
        isLoadingMore = false
    }

    /// 读取第一页（默认本周）
    func reload(service: PortalService?) async {
        generation += 1
        let current = generation
        guard let service else {
            error = "请先登录"
            isLoading = false
            return
        }
        records = []
        total = 0
        loadedPage = 0
        error = nil
        loadMoreError = nil
        isLoading = true
        defer {
            if current == generation { isLoading = false }
        }
        do {
            let page = try await service.accessRecords(kind, range: range, page: 1)
            guard current == generation else { return }
            records = page.records
            total = page.total
            loadedPage = 1
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = PortalErrorMessage.text(for: error)
        }
    }

    /// 按需翻下一页；服务端返回空页时停止翻页
    func loadMore(service: PortalService?) async {
        guard hasMore, !isLoading, !isLoadingMore, let service else { return }
        let current = generation
        let nextPage = loadedPage + 1
        isLoadingMore = true
        loadMoreError = nil
        defer {
            if current == generation { isLoadingMore = false }
        }
        do {
            let page = try await service.accessRecords(kind, range: range, page: nextPage)
            guard current == generation else { return }
            if page.records.isEmpty {
                total = records.count
            } else {
                records += page.records
                total = page.total
                loadedPage = nextPage
            }
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            loadMoreError = PortalErrorMessage.text(for: error)
        }
    }
}
