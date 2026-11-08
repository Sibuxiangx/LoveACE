import CryptoKit
import Foundation

/// 登录诊断上传（契约 v1 第 1 节）。鉴权与 `/v1/events` 相同：Bearer apiKey + HMAC 签名。
enum DiagnosticsUploader {
    static let endpoint = URL(string: "https://analyst-api.loveace.top/v1/diagnostics")!

    /// 请求体上限（契约 v1 第 1 节）。超过时不发送网络请求。
    static let maxBodyBytes = 1_048_576

    /// 上传成功后服务端返回的链接信息
    struct UploadResult: Equatable, Identifiable {
        let id: String
        let url: URL
        let llmUrl: URL
        let expiresAt: Date
    }

    /// 组装并发送签名请求，`body` 为 `diagnostic.json` 原始字节。
    static func upload(_ body: Data) async throws -> UploadResult {
        guard !AnalyticsSecrets.apiKey.isEmpty, !AnalyticsSecrets.signingSecret.isEmpty else {
            throw DiagnosticsUploadError.notConfigured
        }
        guard body.count <= maxBodyBytes else {
            throw DiagnosticsUploadError.server(status: 413, code: "payload_too_large")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let bodyHash = sha256Hex(body)
        let signature = hmacSha256Hex(
            secret: AnalyticsSecrets.signingSecret,
            message: "\(timestamp).\(nonce).\(bodyHash)"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AnalyticsSecrets.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-LoveACE-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-LoveACE-Nonce")
        request.setValue(signature, forHTTPHeaderField: "X-LoveACE-Signature")

        let received: (Data, URLResponse)
        do {
            received = try await URLSession.shared.data(for: request)
        } catch {
            throw DiagnosticsUploadError.transport
        }
        let (data, response) = received

        guard let http = response as? HTTPURLResponse else {
            throw DiagnosticsUploadError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "http_\(http.statusCode)"
            throw DiagnosticsUploadError.server(status: http.statusCode, code: code)
        }
        return try parseSuccess(data)
    }

    private struct SuccessBody: Decodable {
        let ok: Bool
        let id: String
        let url: String
        let llmUrl: String
        let expiresAt: String
    }

    private struct ErrorBody: Decodable {
        let error: String?
    }

    private static func parseSuccess(_ data: Data) throws -> UploadResult {
        guard let body = try? JSONDecoder().decode(SuccessBody.self, from: data),
              body.ok,
              let url = URL(string: body.url),
              let llmUrl = URL(string: body.llmUrl),
              let expiresAt = parseDate(body.expiresAt) else {
            throw DiagnosticsUploadError.invalidResponse
        }
        return UploadResult(id: body.id, url: url, llmUrl: llmUrl, expiresAt: expiresAt)
    }

    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSha256Hex(secret: String, message: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}

/// 上传失败的类型化错误。`server` 携带服务端返回的错误码（如 `invalid_schema`、`rate_limited`）。
enum DiagnosticsUploadError: Error, Equatable {
    case notConfigured
    case transport
    case invalidResponse
    case server(status: Int, code: String)
}
