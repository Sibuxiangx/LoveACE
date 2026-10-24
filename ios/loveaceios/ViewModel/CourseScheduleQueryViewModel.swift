import Foundation

@MainActor @Observable
final class CourseScheduleQueryViewModel {
    // 学期与下拉选项
    private(set) var index: CourseScheduleIndex?
    private(set) var isLoadingIndex = false
    private(set) var indexError: String?

    // 条件：draft 由筛选 sheet 编辑，search() 时才生效为 applied
    var draft = CourseScheduleQuery(termCode: "")
    private(set) var applied: CourseScheduleQuery?

    // 结果
    private(set) var records: [CourseScheduleRecord] = []
    private(set) var totalCount = 0
    private(set) var isLoadingPage = false
    private(set) var pageError: String?

    private var service: CourseScheduleService?
    private var nextPageNum = 1
    /// 服务端返回的原始条数（去重前），用于判断是否还有下一页
    private var loadedRaw = 0
    private var seenKeys: Set<String> = []
    /// 每次新查询递增；旧查询的翻页结果到达时丢弃
    private var generation = 0

    var hasSearched: Bool { applied != nil }

    /// 还有下一页：第一页总是可以加载，之后看原始条数是否已达到 totalCount。
    var canLoadMore: Bool {
        applied != nil && (nextPageNum == 1 || loadedRaw < totalCount)
    }

    var summary: String {
        guard let applied else { return "" }
        var parts: [String] = []
        if let term = index?.terms.first(where: { $0.code == applied.termCode }) {
            parts.append(term.name)
        }
        if let weekday = applied.weekday {
            parts.append(ScheduleFormatting.weekdayName(weekday))
        }
        if let section = applied.startSection {
            parts.append("第 \(section) 节开始")
        }
        parts.append("共 \(totalCount) 条")
        return parts.joined(separator: " · ")
    }

    func initialize(service: CourseScheduleService) {
        self.service = service
    }

    func loadIndex() async {
        guard let service, index == nil, !isLoadingIndex else { return }
        isLoadingIndex = true
        indexError = nil
        let result = await service.loadIndex()
        isLoadingIndex = false
        guard result.success, let loaded = result.data else {
            indexError = result.error ?? "获取学期列表失败"
            return
        }
        index = loaded
        if draft.termCode.isEmpty {
            draft.termCode = loaded.terms.first(where: \.isSelected)?.code ?? loaded.terms.first?.code ?? ""
        }
    }

    /// 按草稿条件查询，从第一页开始。
    func search() async {
        guard service != nil, !draft.termCode.isEmpty else { return }
        applied = draft
        generation += 1
        records = []
        seenKeys = []
        totalCount = 0
        loadedRaw = 0
        nextPageNum = 1
        pageError = nil
        isLoadingPage = false
        await loadNextPage()
    }

    /// 重置筛选条件，保留学期。
    func resetDraft() {
        draft = CourseScheduleQuery(termCode: draft.termCode)
    }

    /// 加载下一页：列表接近末尾时或点重试时调用。
    func loadNextPage() async {
        guard let service, let query = applied, !isLoadingPage, canLoadMore else { return }
        let token = generation
        isLoadingPage = true
        pageError = nil
        let result = await service.queryPage(query, pageNum: nextPageNum)
        guard token == generation else { return }
        isLoadingPage = false
        guard result.success, let page = result.data else {
            pageError = result.error ?? "查询失败"
            return
        }
        nextPageNum += 1
        totalCount = page.totalCount
        loadedRaw += page.records.count
        for record in page.records where seenKeys.insert(record.id).inserted {
            records.append(record)
        }
        if page.records.isEmpty {
            loadedRaw = totalCount
        }
    }
}
