import Foundation

/// 独立配置 `manifest_v2_ios_testflight.json`（与 manifest_v2 无关，旧版本客户端不读取）。
struct IOSTestFlightManifest: Decodable, Sendable {
    let schemaVersion: Int
    let revision: String
    let updatedAt: String
    let enabled: Bool
    let version: String
    let build: Int
    let testflightURL: String
    let title: String
    let changelog: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case updatedAt = "updated_at"
        case enabled
        case version
        case build
        case testflightURL = "testflight_url"
        case title
        case changelog
    }
}

/// 有新 TestFlight 构建可用
struct IOSTestFlightUpdate: Equatable, Sendable {
    let version: String
    let build: Int
    let testflightURL: URL
    let title: String
    let changelog: String
}

/// 一次检查的结果。`failed` 包括所有地址都不可用、响应无效或 schema 不匹配。
enum IOSUpdateCheckResult: Sendable {
    case upToDate
    case available(IOSTestFlightUpdate)
    case failed
}

enum IOSUpdateService {
    private static let manifestURLs = [
        URL(string: "https://loveace.linota.cn/loveace/manifest_v2_ios_testflight.json")!,
        URL(string: "https://release.loveace.top/loveace/manifest_v2_ios_testflight.json")!,
    ]
    private static let ignoredBuildKey = "ios_testflight_ignored_build"

    /// 当前安装的构建号（CFBundleVersion）
    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// 检查是否有更新。不考虑「稍后」的忽略记录，设置页的手动检查总是给出结果。
    /// 网络、非 2xx、解码失败时换下一个地址；拿到有效配置后不再回退。
    /// 响应内容不记录日志。
    static func check() async -> IOSUpdateCheckResult {
        let current = currentBuild
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
                let manifest = try JSONDecoder().decode(IOSTestFlightManifest.self, from: data)
                guard manifest.schemaVersion == 1,
                      let testflightURL = URL(string: manifest.testflightURL),
                      testflightURL.scheme == "https",
                      testflightURL.host == "testflight.apple.com" else {
                    return .failed
                }
                guard manifest.enabled, manifest.build > current else {
                    return .upToDate
                }
                return .available(IOSTestFlightUpdate(
                    version: manifest.version,
                    build: manifest.build,
                    testflightURL: testflightURL,
                    title: manifest.title,
                    changelog: manifest.changelog
                ))
            } catch {
                continue
            }
        }
        return .failed
    }

    /// 启动时的更新弹窗：只返回用户没有对该构建点过「稍后」的更新
    static func fetchPromptUpdate() async -> IOSTestFlightUpdate? {
        guard case .available(let update) = await check(),
              update.build != UserDefaults.standard.integer(forKey: ignoredBuildKey) else {
            return nil
        }
        return update
    }

    /// 用户点了「稍后」：忽略这个构建，更高的构建会再次提示
    static func ignore(_ update: IOSTestFlightUpdate) {
        UserDefaults.standard.set(update.build, forKey: ignoredBuildKey)
    }
}
