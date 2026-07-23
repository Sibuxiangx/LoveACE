import Foundation

struct AppAnnouncement: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let content: String
    let platforms: [String]
    let surfaces: [String]
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, platforms, surfaces
        case expiresAt = "expires_at"
    }
}

private struct AnnouncementManifest: Decodable {
    let schemaVersion: Int
    let announcements: [AppAnnouncement]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case announcements
    }
}

private enum AnnouncementServiceError: LocalizedError {
    case invalidResponse
    case unsupportedManifest

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "公告服务返回异常"
        case .unsupportedManifest: "公告配置版本不受支持"
        }
    }
}

enum AnnouncementService {
    private static let manifestURLs = [
        URL(string: "https://loveace.linota.cn/loveace/manifest_v2.json")!,
        URL(string: "https://release.loveace.top/loveace/manifest_v2.json")!,
    ]

    static func fetchAnnouncements() async throws -> [AppAnnouncement] {
        var lastError: Error = AnnouncementServiceError.invalidResponse

        for url in manifestURLs {
            do {
                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 8
                )
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    throw AnnouncementServiceError.invalidResponse
                }

                let manifest = try JSONDecoder().decode(AnnouncementManifest.self, from: data)
                guard manifest.schemaVersion == 2 else {
                    throw AnnouncementServiceError.unsupportedManifest
                }
                return manifest.announcements.filter(isVisibleInIOSApp)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private static func isVisibleInIOSApp(_ announcement: AppAnnouncement) -> Bool {
        guard !announcement.id.isEmpty,
              announcement.platforms.contains("all") || announcement.platforms.contains("ios"),
              announcement.surfaces.contains("app") else {
            return false
        }
        guard let expiresAt = announcement.expiresAt else { return true }
        return parseISO8601(expiresAt).map { $0 > Date() } ?? false
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
