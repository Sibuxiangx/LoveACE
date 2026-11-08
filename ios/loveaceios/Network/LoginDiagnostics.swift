import Foundation

/// 登录诊断：保留最近 10 次登录的详细调试日志，格式参考 PCL 的调试日志。
///
/// 遮挡规则：
/// - 敏感字段的值统一写成 `<字段名驼峰形式>`，例如 `password` → `<Password>`，`Set-Cookie` → `<SetCookie>`，`Content-Type` → `<ContentType>`。
/// - 非常规请求头保留首尾各两位，中间用 `***` 代替。
/// - 学号保留首尾各两位。
/// - 图片和其他二进制只记录字节数，不记录内容。
actor LoginDiagnostics {
    static let shared = LoginDiagnostics()

    static let maxAttempts = 10
    static let maxSteps = 300
    nonisolated static let excerptLimit = 800

    enum Outcome: String, Codable, Sendable {
        case success
        case invalidCredentials
        case captchaRequired
        case captchaInvalid
        case passwordChangeRequired
        case network
        case other
        case cancelled
        case unfinished

        var isFailure: Bool {
            switch self {
            case .success, .captchaRequired, .unfinished: false
            case .invalidCredentials, .captchaInvalid, .passwordChangeRequired, .network, .other, .cancelled: true
            }
        }

        var label: String {
            switch self {
            case .success: "成功"
            case .invalidCredentials: "账号或密码错误"
            case .captchaRequired: "等待输入验证码"
            case .captchaInvalid: "验证码错误"
            case .passwordChangeRequired: "学校要求修改密码"
            case .network: "网络连接失败"
            case .other: "登录失败（其他原因）"
            case .cancelled: "已取消（被新的登录替换）"
            case .unfinished: "未完成"
            }
        }
    }

    /// 一次 HTTP 往返的原始信息。由 HTTPClient 传入，在这里遮挡和压缩后才写入日志。
    struct HTTPRecord: Sendable {
        let method: String
        let url: URL?
        let status: Int?
        let durationMs: Int
        let requestHeaders: [String: String]
        let requestBody: Data?
        let responseHeaders: [String: String]
        let responseBody: Data?
        let error: String?
    }

    struct Attempt: Codable, Sendable {
        let id: UUID
        let startedAt: Date
        var endedAt: Date?
        let account: String
        let mode: String
        var outcome: Outcome
        var message: String?
        var steps: [String]
        var httpCount: Int
    }

    private var attempts: [Attempt] = []
    private var activeID: UUID?
    private let fileURL: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("LoveACE/LoginDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("attempts.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Attempt].self, from: data) {
            attempts = saved
        }
    }

    /// 是否存在失败记录（决定登录页是否显示分享按钮）
    var hasFailureRecords: Bool {
        attempts.contains { $0.outcome.isFailure }
    }

    /// 当前保留的登录记录数（界面提示「最近 N 次」用）
    var attemptCount: Int { attempts.count }

    func beginAttempt(_ id: UUID, userId: String, mode: String) {
        // 上一次还没结束的尝试，被这次新登录替换
        if let previous = activeID, let index = attempts.firstIndex(where: { $0.id == previous }),
           attempts[index].endedAt == nil {
            attempts[index].outcome = .cancelled
            attempts[index].endedAt = Date()
            append(Self.line("WARN", "AUTH", "被新的登录替换，上一次记为已取消"), at: index)
        }
        attempts.append(Attempt(
            id: id, startedAt: Date(), endedAt: nil,
            account: Self.maskAccount(userId), mode: mode,
            outcome: .unfinished, message: nil, steps: [], httpCount: 0
        ))
        if attempts.count > Self.maxAttempts {
            attempts.removeFirst(attempts.count - Self.maxAttempts)
        }
        activeID = id
        if let index = attempts.firstIndex(where: { $0.id == id }) {
            append(Self.line("INFO", "AUTH", "开始登录 · 模式 \(mode)"), at: index)
        }
    }

    func note(_ id: UUID, _ text: String, level: String = "INFO", module: String = "AUTH") {
        guard let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        append(Self.line(level, module, LoginLogCompressor.text(text)), at: index)
    }

    func finish(_ id: UUID, outcome: Outcome, message: String?) {
        guard let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        let end = Date()
        let sanitized = message.map { LoginLogCompressor.text($0) }
        attempts[index].outcome = outcome
        attempts[index].message = sanitized
        attempts[index].endedAt = end
        let seconds = end.timeIntervalSince(attempts[index].startedAt)
        let reason = sanitized.map { "（\($0)）" } ?? ""
        let footer = "==== 结束：\(outcome.label)\(reason) · 耗时 \(String(format: "%.1f", seconds))s · HTTP \(attempts[index].httpCount) 次 ===="
        append(footer, at: index)
        if activeID == id { activeID = nil }
    }

    /// 记录一次 HTTP 往返。只在登录进行中生效，其他时候直接忽略。
    func recordHTTP(_ record: HTTPRecord) {
        guard let id = activeID, let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        attempts[index].httpCount += 1

        let contentType = Self.headerValue("Content-Type", in: record.responseHeaders)
        var head = ["\(record.method) \(LoginLogCompressor.url(record.url))"]
        head.append(record.status.map { "→ \($0)" } ?? "→ 无响应")
        head.append("(\(record.durationMs)ms)")
        if let contentType { head.append("type=\(LoginLogCompressor.mediaType(contentType))") }
        if let body = record.responseBody { head.append("len=\(Self.sizeText(body.count))") }
        let headerLines = LoginLogCompressor.responseHeaderLines(record.responseHeaders)
        if !headerLines.isEmpty { head.append("头[\(headerLines.joined(separator: ","))]") }
        if let body = record.responseBody {
            let markers = LoginLogCompressor.markers(in: body)
            if !markers.isEmpty { head.append("标记[\(markers.joined(separator: "、"))]") }
        }
        if let location = Self.headerValue("Location", in: record.responseHeaders), !location.isEmpty {
            head.append("跳转 \(LoginLogCompressor.url(URL(string: location)))")
        }
        if let error = record.error { head.append("错误 \(LoginLogCompressor.text(error))") }

        var block = [head.joined(separator: " ")]
        let requestLines = LoginLogCompressor.requestHeaderLines(record.requestHeaders)
        if !requestLines.isEmpty { block.append("  │ 请求头 " + requestLines.joined(separator: " ")) }
        if let body = record.requestBody, !body.isEmpty {
            let requestType = Self.headerValue("Content-Type", in: record.requestHeaders)?.lowercased() ?? ""
            let summary = requestType.contains("x-www-form-urlencoded")
                ? LoginLogCompressor.formSummary(body)
                : LoginLogCompressor.excerpt(body, limit: Self.excerptLimit)
            block.append("  │ 请求体 " + summary)
        }
        if let body = record.responseBody {
            if LoginLogCompressor.isBinary(contentType: contentType) {
                block.append("  │ 响应 二进制 \(Self.sizeText(body.count))（不记录内容）")
            } else {
                block.append("  │ 响应 " + LoginLogCompressor.excerpt(body, limit: Self.excerptLimit))
            }
        }

        let level: String
        if record.error != nil {
            level = "ERROR"
        } else if let status = record.status, status >= 400 {
            level = "WARN"
        } else {
            level = "INFO"
        }
        append(Self.line(level, "HTTP", block.joined(separator: "\n")), at: index)
    }

    /// 设备与应用信息，由界面层读取后传入
    struct DeviceInfo: Sendable {
        let model: String
        let os: String
        let osVersion: String
        let timezone: String
        let locale: String
    }

    /// 导出 diagnostic.json（schema v1）：UTF-8，键排序，结构与契约一致。
    /// 账号、日志行、消息在写入时已经遮挡，这里只做组装，不再读取其他数据。
    func exportJSON(appVersion: String, appBuild: String, device: DeviceInfo) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let file = ExportFile(
            schema: "loveace.login-diagnostics/v1",
            createdAt: formatter.string(from: Date()),
            app: ExportApp(platform: "ios", version: appVersion, build: appBuild),
            device: ExportDevice(
                model: device.model, os: device.os, osVersion: device.osVersion,
                timezone: device.timezone, locale: device.locale
            ),
            attempts: attempts.map { attempt in
                ExportAttempt(
                    id: attempt.id.uuidString,
                    startedAt: formatter.string(from: attempt.startedAt),
                    endedAt: attempt.endedAt.map { formatter.string(from: $0) },
                    account: attempt.account,
                    mode: attempt.mode,
                    // Outcome 的原始值就是契约中的 outcome 字符串
                    outcome: attempt.outcome.rawValue,
                    message: attempt.message,
                    httpCount: attempt.httpCount,
                    lines: attempt.steps
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(file)) ?? Data()
    }

    private struct ExportFile: Encodable {
        let schema: String
        let createdAt: String
        let app: ExportApp
        let device: ExportDevice
        let attempts: [ExportAttempt]
    }

    private struct ExportApp: Encodable {
        let platform: String
        let version: String
        let build: String
    }

    private struct ExportDevice: Encodable {
        let model: String
        let os: String
        let osVersion: String
        let timezone: String
        let locale: String
    }

    private struct ExportAttempt: Encodable {
        let id: String
        let startedAt: String
        let endedAt: String?
        let account: String
        let mode: String
        let outcome: String
        let message: String?
        let httpCount: Int
        let lines: [String]

        enum CodingKeys: String, CodingKey {
            case id, startedAt, endedAt, account, mode, outcome, message, httpCount, lines
        }

        /// 可空字段必须输出 null，不能省略键（契约要求 endedAt / message 为 ISO8601 或 null）
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(startedAt, forKey: .startedAt)
            try container.encode(endedAt, forKey: .endedAt)
            try container.encode(account, forKey: .account)
            try container.encode(mode, forKey: .mode)
            try container.encode(outcome, forKey: .outcome)
            try container.encode(message, forKey: .message)
            try container.encode(httpCount, forKey: .httpCount)
            try container.encode(lines, forKey: .lines)
        }
    }

    private func append(_ step: String, at index: Int) {
        guard attempts[index].steps.count < Self.maxSteps else { return }
        attempts[index].steps.append(step)
        // 每步都落盘：登录卡住或应用被杀时，未完成的记录也保留下来
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 日志行：`[HH:mm:ss.SSS] [LEVEL] [MODULE] 文本`
    nonisolated static func line(_ level: String, _ module: String, _ text: String, at date: Date = Date()) -> String {
        "[\(dateTime(date, format: "HH:mm:ss.SSS"))] [\(level.padding(toLength: 5, withPad: " ", startingAt: 0))] [\(module.padding(toLength: 5, withPad: " ", startingAt: 0))] \(text)"
    }

    nonisolated static func dateTime(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    nonisolated static func maskAccount(_ userId: String) -> String {
        guard userId.count > 4 else { return "****" }
        return "\(userId.prefix(2))****\(userId.suffix(2))"
    }

    nonisolated static func sizeText(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes)B" : String(format: "%.1fKB", Double(bytes) / 1024)
    }

    /// 响应头取值（大小写不敏感）
    nonisolated static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// EC 阶段的结果摘要：只记录是否存在，不记录任何值
    nonisolated static func ecSummary(_ status: ECLoginStatus) -> String {
        let result = status.success ? "成功" : "失败"
        let invalid = status.failInvalidCredentials ? "是" : "否"
        let network = status.failNetworkError ? "是" : "否"
        let unknown = status.failUnknownError ? "是" : "否"
        let captcha = status.captchaRequired ? "是" : "否"
        let captchaWrong = status.captchaInvalid ? "是" : "否"
        let twfid = status.failNotFoundTwfid ? "缺" : "有"
        let rsaKey = status.failNotFoundRsaKey ? "缺" : "有"
        let rsaExp = status.failNotFoundRsaExp ? "缺" : "有"
        let csrf = status.failNotFoundCsrfCode ? "缺" : "有"
        return "EC 结果 \(result) 凭据错误=\(invalid) 网络错误=\(network) 其他=\(unknown) 需要验证码=\(captcha) 验证码错误=\(captchaWrong) twfid=\(twfid) rsaKey=\(rsaKey) rsaExp=\(rsaExp) csrf=\(csrf)"
    }

    /// UAAP 阶段的结果摘要：只记录是否存在，不记录任何值
    nonisolated static func uaapSummary(_ status: UAAPLoginStatus) -> String {
        let result = status.success ? "成功" : "失败"
        let invalid = status.failInvalidCredentials ? "是" : "否"
        let changePassword = status.failPasswordChangeRequired ? "是" : "否"
        let network = status.failNetworkError ? "是" : "否"
        let unknown = status.failUnknownError ? "是" : "否"
        let lt = status.failNotFoundLt ? "缺" : "有"
        let execution = status.failNotFoundExecution ? "缺" : "有"
        return "UAAP 结果 \(result) 凭据错误=\(invalid) 需改密=\(changePassword) 网络错误=\(network) 其他=\(unknown) lt=\(lt) execution=\(execution)"
    }
}

/// 把请求地址、正文、请求头、错误文本压缩并遮挡成短的、不含敏感信息的形式。
enum LoginLogCompressor {
    nonisolated private static let vpnHost = "vpn2.aufe.edu.cn"
    nonisolated private static let vpnSuffix = ".vpn2.aufe.edu.cn"

    nonisolated private static let markerTable: [(name: String, keywords: [String])] = [
        ("密码错误", ["密码输入错误", "用户名或密码错误", "账号或密码错误"]),
        ("验证码", ["rand_code", "RndImg", "验证码"]),
        ("改密", ["completeInfo", "修改密码", "password/change"]),
        ("票据", ["TGT-", "ticket="]),
        ("登录表单", ["name=\"lt\"", "name=\"execution\"", "name='lt'", "name='execution'"]),
        ("会话失效", ["会话已过期", "登录超时", "sdp-app-session"])
    ]

    /// 标准请求头：值照常记录（Referer 和 Origin 仍压缩为服务名）
    nonisolated private static let standardRequestHeaders: Set<String> = [
        "accept", "accept-encoding", "accept-language", "content-type", "content-length", "connection",
        "host", "user-agent", "cache-control", "pragma", "origin", "referer", "upgrade-insecure-requests", "dnt"
    ]

    /// 账号类字段：学号只保留首尾两位
    nonisolated private static let accountKeys: Set<String> = [
        "xh", "userid", "openid", "account", "studentid", "username", "loginname"
    ]

    // MARK: - 地址

    /// `http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn/cas/login?service=…` -> `[uaap]/cas/login?×1`
    nonisolated static func url(_ url: URL?) -> String {
        guard let url, let host = url.host?.lowercased() else { return "[无地址]" }
        let segments = url.pathComponents.filter { $0 != "/" }.prefix(2).map { LoginLogCompressor.segmentToken($0) }
        let path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        var query = ""
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty {
            query = "?×\(items.count)"
        }
        return "[\(serviceToken(host: host))]\(path)\(query)"
    }

    /// 服务名：vpn 网关记为 vpn，`<服务>.vpn2.aufe.edu.cn` 取服务名，其他外部域名记为 ext
    nonisolated static func serviceToken(host: String) -> String {
        if host == vpnHost { return "vpn" }
        if host.hasSuffix(vpnSuffix) {
            let label = String(host.dropLast(vpnSuffix.count))
            let parts = label.split(separator: "-").map(String.init)
            guard let first = parts.first, !first.isEmpty else { return "vpn" }
            if first.allSatisfy(\.isNumber) { return "ip" }
            if first == "api", parts.count > 1 { return "api-\(parts[1])" }
            return first
        }
        return "ext:" + (host.split(separator: ".").first.map(String.init) ?? host)
    }

    /// 路径段：过长、带等号或纯数字的（通常是票据或 ID）替换为 *
    nonisolated static func segmentToken(_ segment: String) -> String {
        if segment.count > 20 || segment.contains("=") { return "*" }
        if segment.count >= 8, segment.allSatisfy(\.isNumber) { return "*" }
        return segment
    }

    // MARK: - 遮挡

    /// 敏感字段名：统一用 `<字段名驼峰形式>` 作为占位，例如 `<Password>`
    nonisolated static func maskToken(_ key: String) -> String {
        let words = key.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let name = words.map { word -> String in
            let text = String(word)
            return text.prefix(1).uppercased() + text.dropFirst().lowercased()
        }.joined()
        return "<\(name.isEmpty ? "Value" : name)>"
    }

    nonisolated static func isSensitiveKey(_ key: String) -> Bool {
        if NetworkLogRedactor.isSensitive(key) { return true }
        let lower = key.lowercased()
        return ["pwd", "captcha", "validatecode", "rsa", "sign", "secret", "cookie"].contains { lower.contains($0) }
    }

    /// 非常规值：保留首尾各两位，中间用 *** 代替
    nonisolated static func partialMask(_ value: String) -> String {
        guard value.count > 6 else { return "***" }
        return "\(value.prefix(2))***\(value.suffix(2))"
    }

    /// 学号：保留首尾两位，中间用 **** 代替
    nonisolated static func studentIDMask(_ value: String) -> String {
        guard value.count >= 6, value.allSatisfy(\.isNumber) else { return partialMask(value) }
        return "\(value.prefix(2))****\(value.suffix(2))"
    }

    /// 正文和文本中的数字串（8 到 12 位）按学号规则遮挡
    nonisolated static func maskDigitRuns(_ text: String) -> String {
        replaceMatches(in: text, pattern: #"(?<!\d)\d{8,12}(?!\d)"#) { match, source in
            substring(match, 0, source).map { studentIDMask($0) }
        }
    }

    /// 文本中的敏感键值：`key=value`、`key: value`、`"key":"value"`、`name="x" value="y"`
    nonisolated static func maskSecrets(_ text: String) -> String {
        let inputsMasked = replaceMatches(in: text, pattern: #"(?i)(name=["']?)([A-Za-z0-9_\-]+)(["']?[^>]*?value=["'])([^"']*)"#) { match, source in
            guard let name = substring(match, 2, source), isSensitiveKey(name) else { return nil }
            let prefix = substring(match, 1, source) ?? ""
            let middle = substring(match, 3, source) ?? ""
            return prefix + name + middle + maskToken(name)
        }
        return replaceMatches(in: inputsMasked, pattern: #"([A-Za-z0-9_\-]+)(["']?\s*[=:]\s*["']?)([^&\s,;<>"'{}\[\]]+)"#) { match, source in
            guard let key = substring(match, 1, source), isSensitiveKey(key) else { return nil }
            let separator = substring(match, 2, source) ?? ""
            return key + separator + maskToken(key)
        }
    }

    /// 隐藏域输入框的值：整个值替换为 `<字段名>`
    nonisolated static func maskHiddenInputs(_ text: String) -> String {
        replaceMatches(in: text, pattern: #"(?i)<input[^>]*>"#) { match, source in
            guard let tag = substring(match, 0, source),
                  tag.range(of: #"(?i)type=["']?hidden"#, options: .regularExpression) != nil else { return nil }
            let name = tag.range(of: #"(?i)name=["']?([A-Za-z0-9_\-]+)"#, options: .regularExpression)
                .map { String(tag[$0]).replacingOccurrences(of: #"(?i)name=["']?"#, with: "", options: .regularExpression) } ?? "Hidden"
            return replaceMatches(in: tag, pattern: #"(?i)(value=["'])([^"']*)"#) { valueMatch, valueSource in
                substring(valueMatch, 1, valueSource).map { $0 + maskToken(name) }
            }
        }
    }

    // MARK: - 请求和响应

    /// 请求头：Cookie、Authorization 和敏感字段用占位；标准请求头照常记录；其他非常规请求头首尾保留两位
    nonisolated static func requestHeaderLines(_ headers: [String: String]) -> [String] {
        headers.keys.sorted().map { name in
            let value = headers[name] ?? ""
            let lower = name.lowercased()
            if lower == "cookie" || lower == "authorization" || isSensitiveKey(name) {
                return "\(name)=\(maskToken(name))"
            }
            if standardRequestHeaders.contains(lower) {
                if lower == "referer" || lower == "origin" { return "\(name)=\(url(URL(string: value)))" }
                return "\(name)=\(text(value))"
            }
            return "\(name)=\(partialMask(value))"
        }
    }

    /// 响应头只列名字；Set-Cookie 等敏感头给出占位，Content-Type 只保留媒体类型
    nonisolated static func responseHeaderLines(_ headers: [String: String]) -> [String] {
        headers.keys.sorted().prefix(12).map { name in
            if name.lowercased() == "set-cookie" || isSensitiveKey(name) { return "\(name)=\(maskToken(name))" }
            return name
        }
    }

    /// 表单请求体：字段名与值成对列出；敏感字段用占位，学号按学号规则遮挡
    nonisolated static func formSummary(_ data: Data) -> String {
        guard let body = String(data: data, encoding: .utf8), body.contains("=") else { return excerpt(data) }
        return body.split(separator: "&").map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawKey = parts.first.map(String.init) ?? ""
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            return "\(key)=\(displayValue(key: key, value: value))"
        }.joined(separator: " ")
    }

    nonisolated static func displayValue(key: String, value: String) -> String {
        if value.isEmpty { return "" }
        if accountKeys.contains(key.lowercased()) { return studentIDMask(value) }
        if isSensitiveKey(key) { return maskToken(key) }
        let cleaned = text(value)
        return cleaned.count > 60 ? "\(cleaned.prefix(60))…" : cleaned
    }

    /// 响应正文摘要：去掉多余空白，遮挡隐藏域和敏感键值，学号按规则遮挡，超长截断
    nonisolated static func excerpt(_ data: Data, limit: Int = LoginDiagnostics.excerptLimit) -> String {
        guard let raw = decode(data) else { return "（无法解码，\(LoginDiagnostics.sizeText(data.count))）" }
        let flat = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let masked = maskDigitRuns(maskSecrets(maskHiddenInputs(urlsCompressed(flat))))
        if masked.count > limit {
            return "\(masked.prefix(limit))…（共 \(LoginDiagnostics.sizeText(data.count))）"
        }
        return masked
    }

    /// 普通文本：先压缩地址，再遮挡敏感键值，最后遮挡学号
    nonisolated static func text(_ raw: String) -> String {
        maskDigitRuns(maskSecrets(urlsCompressed(raw)))
    }

    nonisolated static func mediaType(_ contentType: String) -> String {
        contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? contentType
    }

    nonisolated static func isBinary(contentType: String?) -> Bool {
        guard let type = contentType?.lowercased() else { return false }
        return type.hasPrefix("image/") || type.hasPrefix("audio/") || type.hasPrefix("video/")
            || type.hasPrefix("application/octet-stream") || type.hasPrefix("application/pdf")
    }

    /// 正文关键词命中（只返回名称，不返回内容）
    nonisolated static func markers(in data: Data) -> [String] {
        guard let body = decode(data) else { return [] }
        return markerTable.compactMap { entry in
            entry.keywords.contains { body.contains($0) } ? entry.name : nil
        }
    }

    // MARK: - 工具

    nonisolated private static func urlsCompressed(_ text: String) -> String {
        replaceMatches(in: text, pattern: #"https?://[^\s"'<>,，。；;]+"#) { match, source in
            substring(match, 0, source).map { url(URL(string: $0)) }
        }
    }

    nonisolated private static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
    }

    /// 用正则逐个替换：transform 返回 nil 表示保持原样
    nonisolated private static func replaceMatches(
        in text: String, pattern: String,
        transform: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), let replacement = transform(match, text) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    nonisolated private static func substring(_ match: NSTextCheckingResult, _ group: Int, _ source: String) -> String? {
        guard let range = Range(match.range(at: group), in: source) else { return nil }
        return String(source[range])
    }
}
