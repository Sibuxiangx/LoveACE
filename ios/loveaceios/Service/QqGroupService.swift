import Foundation

/// 独立配置 `qq_group_v1.json`（与 manifest_v2 无关）。
struct QqGroupManifest: Decodable, Sendable, Equatable {
    let schemaVersion: Int
    let revision: String
    let updatedAt: String
    let enabled: Bool
    let title: String
    let groupNumber: String
    let shareUrl: String
    let qrImageUrl: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case updatedAt = "updated_at"
        case enabled
        case title
        case groupNumber = "group_number"
        case shareUrl = "share_url"
        case qrImageUrl = "qr_image_url"
    }
}

enum QqGroupService {
    private static let manifestURLs = [
        URL(string: "https://loveace.linota.cn/loveace/qq_group_v1.json")!,
        URL(string: "https://release.loveace.top/loveace/qq_group_v1.json")!,
    ]

    /// 拉取加群配置。网络、非 2xx、解码失败时换下一个地址；拿到有效配置后不再回退。
    /// 任何失败、schema_version 不为 1 或 enabled 为 false 都返回 nil，界面据此不展示入口。
    /// 响应内容不记录日志。
    static func fetch() async -> QqGroupManifest? {
        for url in manifestURLs {
            do {
                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 10
                )
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    continue
                }
                let manifest = try JSONDecoder().decode(QqGroupManifest.self, from: data)
                guard manifest.schemaVersion == 1, manifest.enabled else { return nil }
                return manifest
            } catch {
                continue
            }
        }
        return nil
    }
}
