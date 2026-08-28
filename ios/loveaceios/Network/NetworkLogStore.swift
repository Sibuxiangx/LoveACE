import Foundation

struct SessionPageDetection: Sendable {
    let isExpired: Bool
    let kind: String
    let signals: [String]
}

enum SessionPageDetector {
    nonisolated static func inspect(responseURL: URL?, body: Data, location: String? = nil) -> SessionPageDetection {
        let text = String(decoding: body.prefix(64 * 1024), as: UTF8.self)
        let lower = text.lowercased()
        let host = responseURL?.host?.lowercased() ?? ""
        let path = responseURL?.path.lowercased() ?? ""
        let locationURL = location.flatMap(URL.init)
        var signals: [String] = []

        if host == "vpn.aufe.edu.cn" && path == "/portal" { signals.append("vpn_portal_url") }
        if host == "vpn.aufe.edu.cn" && path.hasPrefix("/portal/") { signals.append("vpn_portal_url") }
        if host == "vpn2.aufe.edu.cn" && path == "/", locationURL?.query?.contains("redirect_uri=") == true {
            signals.append("vpn_route_selector_url")
        }
        if host == "vpn2.aufe.edu.cn" && path == "/", responseURL?.query?.contains("redirect_uri=") == true {
            signals.append("vpn_route_selector_url")
        }
        if lower.contains("id=\"app\"") && lower.contains("ms-controller=\"app\"") {
            signals.append("portal_app_root")
        }
        if lower.contains("sangfor-body") { signals.append("sangfor_body") }
        if lower.contains("sangfor-main") { signals.append("sangfor_main") }
        if lower.contains("jssdk/business/session.js") { signals.append("portal_session_script") }
        if lower.contains("jssdk/business/auth.js") { signals.append("portal_auth_script") }
        if lower.contains("../por/jsdata.csp") || lower.contains("/por/jsdata.csp") {
            signals.append("portal_jsdata")
        }
        if lower.contains("window.ecredirect") { signals.append("portal_ec_redirect") }
        if lower.contains("#!/login") { signals.append("portal_login_route") }
        if lower.contains("g_lines") { signals.append("vpn_route_selector_script") }
        if lower.contains("gotolines") { signals.append("vpn_route_selector_goto") }
        if lower.contains("win_location") { signals.append("vpn_route_selector_probe") }
        if lower.contains("sf_ssl_ms_") { signals.append("vpn_route_selector_marker") }
        if lower.contains("/por/phone_index.csp") { signals.append("vpn_phone_entry") }
        if lower.contains("getorigin() + '/portal'") { signals.append("vpn_portal_fallback") }
        if lower.contains("<twfid>") { signals.append("vpn_auth_response") }

        let portalSignals = signals.filter { $0.hasPrefix("vpn_portal") || $0.hasPrefix("portal_") }
        let routeSelectorSignals = signals.filter { $0.hasPrefix("vpn_route_selector") || $0.hasPrefix("vpn_phone_") || $0.hasPrefix("vpn_portal_fallback") }
        let isPortal = signals.contains("vpn_portal_url")
            || portalSignals.count >= 3
            || signals.contains("vpn_route_selector_url")
            || routeSelectorSignals.count >= 3
        let kind = isPortal ? "vpn_session_expired" : (signals.contains("vpn_auth_response") ? "vpn_auth" : "normal")
        return SessionPageDetection(isExpired: isPortal, kind: kind, signals: signals)
    }
}

enum NetworkLogRedactor {
    nonisolated private static let sensitiveNames = [
        "authorization", "cookie", "set-cookie", "password", "passwd", "token",
        "ticket", "csrf", "rand", "secret", "credential", "jessionid", "jsessionid", "twfid",
        "lt", "execution", "username", "session", "svpn_name", "svpn_password"
    ]

    nonisolated static func url(_ url: URL?) -> String {
        guard let url else { return "unknown" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                isSensitive(item.name) ? URLQueryItem(name: item.name, value: "<redacted>") : item
            }
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            components.fragment = isSensitive(fragment) ? "<redacted>" : fragment
        }
        return text(components.string ?? url.absoluteString)
    }

    nonisolated static func headers(_ headers: [AnyHashable: Any]) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            let name = String(describing: item.key)
            let value = String(describing: item.value)
            if isSensitive(name) {
                result[name] = "<redacted>"
            } else if name.caseInsensitiveCompare("Location") == .orderedSame {
                result[name] = url(URL(string: value))
            } else {
                result[name] = text(value)
            }
        }
    }

    nonisolated static func headers(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            if isSensitive(item.key) {
                result[item.key] = "<redacted>"
            } else if item.key.caseInsensitiveCompare("Location") == .orderedSame {
                result[item.key] = url(URL(string: item.value))
            } else {
                result[item.key] = text(item.value)
            }
        }
    }

    nonisolated static func text(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?is)(<(?:csrf_rand_code|twfid|rsa_encrypt_key|rsa_encrypt_exp)[^>]*>)(.*?)(</(?:csrf_rand_code|twfid|rsa_encrypt_key|rsa_encrypt_exp)>)"#,
            #"(?i)(password|passwd|token|ticket|csrf|secret|authorization|cookie|set-cookie|jessionid|jsessionid|twfid|lt|execution)(\s*[=:]\s*)([^&\s,;<>\"']+)"#,
            #"(?i)(\"?(?:password|passwd|token|ticket|csrf|secret|jessionid|jsessionid|twfid|lt|execution)\"?\s*:\s*\"?)([^\",}\s]+)"#,
            #"(?i)(name=[\"']?(svpn_password|password|token|ticket|csrf)[\"']?\s+value=[\"']?)([^\"' >]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let replacement = pattern.hasPrefix("(?is)(<") ? "$1<redacted>$3" : "$1<redacted>"
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    nonisolated static func isSensitive(_ name: String) -> Bool {
        let lower = name.lowercased().replacingOccurrences(of: "-", with: "")
        if ["lt", "execution", "rand"].contains(lower) { return true }
        return sensitiveNames
            .filter { !["lt", "execution", "rand"].contains($0) }
            .contains { lower.contains($0.replacingOccurrences(of: "-", with: "")) }
    }
}

actor NetworkLogStore {
    static let shared = NetworkLogStore()
    nonisolated static let loggingEnabledKey = "loveace.network_logging_enabled"
    nonisolated static var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: loggingEnabledKey)
    }

    nonisolated static func setLoggingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: loggingEnabledKey)
    }

    static let largeResponseThreshold = 256 * 1024
    private let fileManager = FileManager.default
    private let sessionDirectory: URL
    private let responseDirectory: URL
    private let logFile: URL
    private var sequence = 0

    private init() {
        let applicationSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let root = applicationSupport.appendingPathComponent("LoveACE/NetworkLogs", isDirectory: true)
        let session = root.appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
        self.sessionDirectory = session
        self.responseDirectory = session.appendingPathComponent("responses", isDirectory: true)
        self.logFile = session.appendingPathComponent("network.jsonl")
        try? fileManager.createDirectory(at: responseDirectory, withIntermediateDirectories: true)
    }

    func recordRequestStarted(id: String, request: URLRequest, bodySummary: String?) {
        guard Self.isLoggingEnabled else { return }
        var fields: [String: Any] = [
            "event": "request_started",
            "request_id": id,
            "method": request.httpMethod ?? "GET",
            "url": NetworkLogRedactor.url(request.url),
            "headers": NetworkLogRedactor.headers(request.allHTTPHeaderFields ?? [:])
        ]
        if let bodySummary { fields["body"] = bodySummary }
        append(fields)
    }

    func recordResponse(
        id: String,
        requestURL: URL?,
        response: HTTPURLResponse,
        body: Data,
        duration: TimeInterval,
        detection: SessionPageDetection
    ) {
        guard Self.isLoggingEnabled else { return }
        let sequenceNumber = sequence + 1
        var bodyInfo: [String: Any] = [
            "bytes": body.count,
            "storage": "inline"
        ]

        if body.count > Self.largeResponseThreshold {
            let fileName = String(format: "%06d-response.bin", sequenceNumber)
            let fileURL = responseDirectory.appendingPathComponent(fileName)
            if (try? body.write(to: fileURL, options: .atomic)) != nil {
                bodyInfo["storage"] = "file"
                bodyInfo["file"] = "responses/\(fileName)"
            } else {
                bodyInfo["storage"] = "write_failed"
            }
        } else if let text = String(data: body, encoding: .utf8), !text.isEmpty {
            bodyInfo["preview"] = NetworkLogRedactor.text(String(text.prefix(16 * 1024)))
        } else if !body.isEmpty {
            bodyInfo["preview"] = "binary response"
        }

        append([
            "event": "response_received",
            "request_id": id,
            "request_url": NetworkLogRedactor.url(requestURL),
            "status_code": response.statusCode,
            "url": NetworkLogRedactor.url(response.url),
            "headers": NetworkLogRedactor.headers(response.allHeaderFields),
            "duration_ms": Int(duration * 1000),
            "classification": detection.kind,
            "signals": detection.signals,
            "body": bodyInfo
        ])
    }

    func recordFailure(id: String, request: URLRequest, error: Error, duration: TimeInterval) {
        guard Self.isLoggingEnabled else { return }
        let nsError = error as NSError
        append([
            "event": "request_failed",
            "request_id": id,
            "method": request.httpMethod ?? "GET",
            "url": NetworkLogRedactor.url(request.url),
            "duration_ms": Int(duration * 1000),
            "error_domain": nsError.domain,
            "error_code": nsError.code,
            "error": NetworkLogRedactor.text(error.localizedDescription)
        ])
    }

    func recordRedirect(taskID: Int, response: HTTPURLResponse, newRequest: URLRequest) {
        guard Self.isLoggingEnabled else { return }
        append([
            "event": "redirect",
            "task_id": taskID,
            "status_code": response.statusCode,
            "from_url": NetworkLogRedactor.url(response.url),
            "to_url": NetworkLogRedactor.url(newRequest.url),
            "response_headers": NetworkLogRedactor.headers(response.allHeaderFields),
            "request_headers": NetworkLogRedactor.headers(newRequest.allHTTPHeaderFields ?? [:])
        ])
    }

    func recordSessionExpired(requestURL: URL?, responseURL: URL?, signals: [String]) {
        guard Self.isLoggingEnabled else { return }
        append([
            "event": "vpn_session_expired",
            "request_url": NetworkLogRedactor.url(requestURL),
            "response_url": NetworkLogRedactor.url(responseURL),
            "signals": signals
        ])
    }

    func recordHeartbeat(result: String, bodyBytes: Int) {
        guard Self.isLoggingEnabled else { return }
        append([
            "event": "heartbeat",
            "result": result,
            "body_bytes": bodyBytes
        ])
    }

    func exportZip() throws -> URL {
        guard Self.isLoggingEnabled else { throw NetworkLogError.loggingDisabled }
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let root = sessionDirectory.deletingLastPathComponent()
        let archiveURL = root.appendingPathComponent("\(sessionDirectory.lastPathComponent).zip")
        var archive = ZipArchiveBuilder()
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        if let enumerator = fileManager.enumerator(at: sessionDirectory, includingPropertiesForKeys: resourceKeys) {
            for case let fileURL as URL in enumerator {
                guard (try? fileURL.resourceValues(forKeys: Set(resourceKeys)).isRegularFile) == true else { continue }
                let relativePath = String(fileURL.path.dropFirst(sessionDirectory.path.count + 1))
                archive.addFile(path: relativePath, data: try Data(contentsOf: fileURL))
            }
        }
        try archive.finalizedData.write(to: archiveURL, options: .atomic)
        return archiveURL
    }

    private func append(_ fields: [String: Any]) {
        guard Self.isLoggingEnabled else { return }
        sequence += 1
        var object = fields
        object["sequence"] = sequence
        object["timestamp"] = Date().timeIntervalSince1970
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: logFile) else {
            var firstLine = data
            firstLine.append(0x0A)
            fileManager.createFile(atPath: logFile.path, contents: firstLine)
            return
        }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(Data([0x0A]))
        try? handle.close()
    }
}

enum NetworkLogError: LocalizedError {
    case loggingDisabled

    var errorDescription: String? {
        "请先开启网络日志"
    }
}

private struct ZipArchiveBuilder {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private(set) nonisolated var data = Data()
    private var entries: [Entry] = []

    nonisolated init() {}

    nonisolated mutating func addFile(path: String, data fileData: Data) {
        let name = Data(path.utf8)
        let crc = crc32(fileData)
        let offset = UInt32(data.count)
        appendUInt32(0x04034B50)
        appendUInt16(20)
        appendUInt16(0x0800)
        appendUInt16(0)
        appendUInt16(0)
        appendUInt16(0)
        appendUInt32(crc)
        appendUInt32(UInt32(fileData.count))
        appendUInt32(UInt32(fileData.count))
        appendUInt16(UInt16(name.count))
        appendUInt16(0)
        data.append(name)
        data.append(fileData)
        entries.append(Entry(name: name, crc: crc, size: UInt32(fileData.count), offset: offset))
    }

    private mutating func appendUInt16(_ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(value & 0xFFFF))
        appendUInt16(UInt16((value >> 16) & 0xFFFF))
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB88320 : 0) }
        }
        return crc ^ 0xFFFFFFFF
    }

    nonisolated var finalizedData: Data {
        var result = data
        var centralDirectory = Data()
        for entry in entries {
            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(entry.crc)
            centralDirectory.appendUInt32(entry.size)
            centralDirectory.appendUInt32(entry.size)
            centralDirectory.appendUInt16(UInt16(entry.name.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(entry.offset)
            centralDirectory.append(entry.name)
        }
        let centralOffset = UInt32(result.count)
        result.append(centralDirectory)
        result.appendUInt32(0x06054B50)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt16(UInt16(entries.count))
        result.appendUInt32(UInt32(centralDirectory.count))
        result.appendUInt32(centralOffset)
        result.appendUInt16(0)
        return result
    }
}

fileprivate extension Data {
    nonisolated mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    nonisolated mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(value & 0xFFFF))
        appendUInt16(UInt16((value >> 16) & 0xFFFF))
    }
}
