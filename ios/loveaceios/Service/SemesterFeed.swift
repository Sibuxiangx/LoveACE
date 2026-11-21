import Foundation

private struct SemesterManifestV2: Decodable {
    let schemaVersion: Int
    let semester: SemesterManifestSection?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case semester
    }
}

private struct SemesterManifestSection: Decodable {
    let semesters: [SemesterItem]
}

/// 学期列表：优先从 manifest_v2 读取（EdgeOne 优先，release 兜底），失败时回退旧 OSS 静态文件；首页与小组件同步共用
enum SemesterFeed {
    private static let manifestURLs = [
        URL(string: "https://loveace.linota.cn/loveace/manifest_v2.json")!,
        URL(string: "https://release.loveace.top/loveace/manifest_v2.json")!,
    ]
    private static let legacyURL = URL(string: "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json")!

    static func fetch() async throws -> [SemesterItem] {
        var lastError: Error = ServiceError.parseError("远程配置缺少学期数据")

        for url in manifestURLs {
            do {
                let data = try await fetchData(from: url)
                let manifest = try JSONDecoder().decode(SemesterManifestV2.self, from: data)
                guard manifest.schemaVersion == 2,
                      let semesters = manifest.semester?.semesters,
                      !semesters.isEmpty else {
                    throw ServiceError.parseError("远程配置缺少学期数据")
                }
                return semesters
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        do {
            let data = try await fetchData(from: legacyURL)
            let semesters = try JSONDecoder().decode(SemesterData.self, from: data).semesters
            guard !semesters.isEmpty else {
                throw ServiceError.parseError("旧版学期数据为空")
            }
            return semesters
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw lastError
        }
    }

    private static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw ServiceError.parseError("学期配置请求失败")
        }
        return data
    }
}
