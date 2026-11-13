import Foundation

@MainActor @Observable
final class AACViewModel {
    var isLoading = false
    var creditInfo: AACCreditInfo?
    var categories: [AACCreditCategory] = []
    var error: String?
    private var service: AACService?

    func initialize(service: AACService) { self.service = service }

    func loadAll() {
        guard let svc = service else { return }
        Task {
            isLoading = true; error = nil
            let infoResult = await svc.getCreditInfo()
            let listResult = await svc.getCreditList()
            creditInfo = infoResult.data
            categories = listResult.data ?? []
            error = infoResult.error ?? listResult.error
            isLoading = false
        }
    }
}

/// 毕业统计，与 Android 的 AACScreen 保持一致。分类名由教务系统返回，当前为「劳动实践」。
enum AACGraduationStats {
    static let practiceMin = 1.0
    static let laborRequired = 4.0
    private static let laborCategoryName = "劳动实践"

    /// 社会实践分数：「劳动实践」分类下，类型或标题含「三下乡」「社会实践」的条目分数之和
    static func practiceScore(_ categories: [AACCreditCategory]) -> Double {
        categories
            .filter { $0.typeName.contains(laborCategoryName) }
            .flatMap(\.children)
            .filter { $0.typeName.contains("三下乡") || $0.title.contains("三下乡") || $0.title.contains("社会实践") }
            .reduce(0) { $0 + $1.score }
    }

    /// 劳动实践分数：「劳动实践」分类的总分之和
    static func laborScore(_ categories: [AACCreditCategory]) -> Double {
        categories
            .filter { $0.typeName.contains(laborCategoryName) }
            .reduce(0) { $0 + $1.totalScore }
    }
}
