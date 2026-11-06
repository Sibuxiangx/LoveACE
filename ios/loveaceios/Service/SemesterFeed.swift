import Foundation

/// 学期列表（OSS 静态文件），首页与小组件同步共用
enum SemesterFeed {
    private static let urlString = "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json"

    static func fetch() async throws -> [SemesterItem] {
        guard let url = URL(string: urlString) else { throw ServiceError.parseError("URL无效") }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SemesterData.self, from: data).semesters
    }
}
