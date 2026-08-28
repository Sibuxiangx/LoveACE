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

        if followRedirects {
            self.session = URLSession(configuration: config)
        } else {
            self.session = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        }
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
        let reqUrl = request.url?.absoluteString ?? ""
        logger.info("🌐 \(request.httpMethod ?? "?") \(self.safeLogURL(request.url))")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        let respUrl = httpResponse.url?.absoluteString ?? reqUrl
        logger.info("✅ \(httpResponse.statusCode) \(self.safeLogURL(httpResponse.url)) [\(data.count) bytes]")

        let isLoginRequest = reqUrl.contains("/por/login_auth.csp") || reqUrl.contains("/por/login_psw.csp")
        if !isLoginRequest, let peek = String(data: data.prefix(512), encoding: .utf8) {
            if isVpnLoginPage(body: peek, url: respUrl) {
                logger.warning("⚠️ Session expired detected for \(reqUrl)")
                onSessionExpired?()
            }
        }
        return (data, httpResponse)
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

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
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
