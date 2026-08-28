import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "HTTPClient")

actor HTTPClient {
    let baseUrl: String
    let timeoutInterval: TimeInterval
    let session: URLSession
    let cookieStorage: HTTPCookieStorage
    var onSessionExpired: (@Sendable () -> Void)?

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    init(baseUrl: String = "", timeoutInterval: TimeInterval = 60,
         followRedirects: Bool = true, cookieStorage: HTTPCookieStorage? = nil) {
        self.baseUrl = baseUrl
        self.timeoutInterval = timeoutInterval

        let storage = cookieStorage ?? HTTPCookieStorage()
        storage.cookieAcceptPolicy = .always
        self.cookieStorage = storage

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = storage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2

        self.session = URLSession(
            configuration: config,
            delegate: HTTPClientSessionDelegate(followRedirects: followRedirects),
            delegateQueue: nil
        )
    }

    func get(_ urlString: String, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        let fullUrl = resolveUrl(urlString)
        guard let url = URL(string: fullUrl) else { throw HTTPError.invalidURL(fullUrl) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await execute(request)
    }

    func post(_ urlString: String, formData: [String: String] = [:],
              headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        let fullUrl = resolveUrl(urlString)
        guard let url = URL(string: fullUrl) else { throw HTTPError.invalidURL(fullUrl) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let bodyString = formData.map { key, value in
            "\(key.urlEncoded)=\(value.urlEncoded)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        return try await execute(request)
    }

    func postRaw(_ urlString: String, body: Data, contentType: String,
                 headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        let fullUrl = resolveUrl(urlString)
        guard let url = URL(string: fullUrl) else { throw HTTPError.invalidURL(fullUrl) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body
        return try await execute(request)
    }

    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestID = UUID().uuidString
        let startedAt = Date()
        let reqUrl = request.url?.absoluteString ?? ""
        logger.info("🌐 \(request.httpMethod ?? "?") \(self.safeLogURL(request.url))")
        await NetworkLogStore.shared.recordRequestStarted(
            id: requestID,
            request: request,
            bodySummary: requestBodySummary(request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type"))
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            let location = httpResponse.value(forHTTPHeaderField: "Location")
            let detection = SessionPageDetector.inspect(responseURL: httpResponse.url, body: data, location: location)
            await NetworkLogStore.shared.recordResponse(
                id: requestID,
                requestURL: request.url,
                response: httpResponse,
                body: data,
                duration: Date().timeIntervalSince(startedAt),
                detection: detection
            )
            let respUrl = httpResponse.url?.absoluteString ?? reqUrl
            logger.info("✅ \(httpResponse.statusCode) \(self.safeLogURL(httpResponse.url)) [\(data.count) bytes]")

            if detection.isExpired {
                logger.warning("⚠️ VPN session expired detected for \(self.safeLogURL(httpResponse.url))")
                await NetworkLogStore.shared.recordSessionExpired(
                    requestURL: request.url,
                    responseURL: httpResponse.url,
                    signals: detection.signals
                )
                onSessionExpired?()
            } else if !reqUrl.contains("/por/login_auth.csp"),
                      !reqUrl.contains("/por/login_psw.csp"),
                      let peek = String(data: data.prefix(512), encoding: .utf8),
                      isVpnLoginPage(body: peek, url: respUrl) {
                logger.warning("⚠️ Legacy VPN login page detected for \(reqUrl)")
                await NetworkLogStore.shared.recordSessionExpired(
                    requestURL: request.url,
                    responseURL: httpResponse.url,
                    signals: ["legacy_login_page"]
                )
                onSessionExpired?()
            }
            return (data, httpResponse)
        } catch {
            await NetworkLogStore.shared.recordFailure(
                id: requestID,
                request: request,
                error: error,
                duration: Date().timeIntervalSince(startedAt)
            )
            throw error
        }
    }

    private func requestBodySummary(_ body: Data?, contentType: String?) -> String? {
        guard let body else { return nil }
        let type = contentType ?? "unknown"
        if type.lowercased().contains("form-urlencoded"),
           let text = String(data: body, encoding: .utf8) {
            let fields = text.split(separator: "&").compactMap { $0.split(separator: "=", maxSplits: 1).first }
                .map(String.init).sorted().joined(separator: ",")
            return "content_type=\(type); bytes=\(body.count); fields=[\(fields)]"
        }
        return "content_type=\(type); bytes=\(body.count)"
    }

    private func safeLogURL(_ url: URL?) -> String {
        guard let url else { return "unknown" }
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = url.path
        return components.string ?? url.path
    }

    private func isVpnLoginPage(body: String, url: String) -> Bool {
        if url.contains("/por/login_auth.csp") || url.contains("/por/login_psw.csp") { return true }
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") {
            if body.contains("login_auth.csp") || body.contains("TWFID") || body.contains("svpn_name") {
                return true
            }
        }
        return false
    }

    private func resolveUrl(_ urlString: String) -> String {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") { return urlString }
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let path = urlString.hasPrefix("/") ? urlString : "/\(urlString)"
        return "\(base)\(path)"
    }

    func setCookie(name: String, value: String, domain: String) {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain,
            .path: "/", .expires: Date.distantFuture
        ]
        if let cookie = HTTPCookie(properties: properties) {
            cookieStorage.setCookie(cookie)
        }
    }

    func getCookie(name: String) -> String? {
        cookieStorage.cookies?.first { $0.name == name }?.value
    }

    func copyCookies(from other: HTTPClient) async {
        let otherCookies = await other.cookieStorage.cookies ?? []
        for cookie in otherCookies {
            cookieStorage.setCookie(cookie)
        }
    }
}

enum HTTPError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .emptyResponse: return "Empty response"
        }
    }
}

final class HTTPClientSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        Task {
            await NetworkLogStore.shared.recordRedirect(
                taskID: task.taskIdentifier,
                response: response,
                newRequest: request
            )
        }
        completionHandler(followRedirects ? request : nil)
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=+")
        return cs
    }()
}
