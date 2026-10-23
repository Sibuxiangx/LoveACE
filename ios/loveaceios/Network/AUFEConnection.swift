import Foundation
import CommonCrypto
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "AUFEConnection")

private struct ECAuthContext {
    let twfId: String
    let csrfCode: String
    let rsaKey: String
    let rsaExp: String
}

/// 验证码图片对应的待提交认证上下文（仅内存，不记录日志）；提交验证码后立即丢弃
private struct PendingCaptchaContext {
    let auth: ECAuthContext
    let createdAt: Date
}

private enum ECAuthPageResult {
    case page(ECAuthContext, requiresCaptcha: Bool)
    case failed(ECLoginStatus)
}

actor AUFEConnection {
    let userId: String
    private let ecPassword: String
    private let password: String

    var client: HTTPClient!
    var simpleClient: HTTPClient!
    var noRedirectClient: HTTPClient!

    private(set) var twfId: String?
    private var ecLogged = false
    private var uaapLogged = false
    /// EC 验证码待提交上下文（仅内存）：仅在 captchaRequired 后存在，提交验证码后清除
    private var pendingCaptcha: PendingCaptchaContext?

    static let serverURL = "https://vpn2.aufe.edu.cn"
    static let uaapLoginURL =
        "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fjwcxk2.aufe.edu.cn%2Fj_spring_cas_security_check"
    static let timeout: TimeInterval = 60
    /// 验证码待提交上下文的有效期（秒）；超时后重新取图
    static let captchaContextLifetime: TimeInterval = 180

    init(userId: String, ecPassword: String, password: String) {
        self.userId = userId
        self.ecPassword = ecPassword
        self.password = password
    }

    func startClient() {
        let storage = HTTPCookieStorage.shared
        storage.cookieAcceptPolicy = .always
        if let oldCookies = storage.cookies {
            for c in oldCookies { storage.deleteCookie(c) }
        }
        client = HTTPClient(baseUrl: Self.serverURL, timeoutInterval: Self.timeout, cookieStorage: storage)
        simpleClient = HTTPClient(baseUrl: Self.serverURL, timeoutInterval: Self.timeout, cookieStorage: storage)
        noRedirectClient = HTTPClient(baseUrl: Self.serverURL, timeoutInterval: Self.timeout,
                                      followRedirects: false, cookieStorage: storage)
    }

    func setOnSessionExpired(_ callback: @escaping @Sendable () -> Void) async {
        await client.setSessionExpired(callback)
        await simpleClient.setSessionExpired(callback)
        await noRedirectClient.setSessionExpired(callback)
    }

    // MARK: - Heartbeat

    enum HeartbeatResult {
        case alive
        case expired
        case unavailable
    }

    func heartbeat() async -> HeartbeatResult {
        do {
            let (data, _) = try await client.get("\(Self.serverURL)/por/login_auth.csp?apiversion=1")
            let body = String(data: data, encoding: .utf8) ?? ""
            let result: HeartbeatResult = body.contains("<TwfID>") ? .alive : .expired
            logger.debug("💓 Heartbeat: \(String(describing: result))")
            await NetworkLogStore.shared.recordHeartbeat(result: String(describing: result), bodyBytes: data.count)
            return result
        } catch {
            logger.warning("💓 Heartbeat failed: \(error.localizedDescription)")
            await NetworkLogStore.shared.recordHeartbeat(result: "unavailable", bodyBytes: 0)
            return .unavailable
        }
    }

    // MARK: - EC Login

    /// EC 登录。`captchaCode` 为 nil 表示尚未输入验证码：学校要求验证码时返回 `captchaRequired` 与图片，不提交密码。
    /// 非空 `captchaCode` 必须使用上一次 `captchaRequired` 保存的待提交上下文；该上下文单次有效。
    func ecLogin(captchaCode: String? = nil) async -> ECLoginStatus {
        do {
            return try await performEcLogin(captchaCode: captchaCode)
        } catch {
            logger.error("EC login error: \(error.localizedDescription)")
            if isNetworkError(error) { return ECLoginStatus(failNetworkError: true) }
            return ECLoginStatus(failUnknownError: true)
        }
    }

    private func performEcLogin(captchaCode: String?) async throws -> ECLoginStatus {
        if let captchaCode {
            guard let pending = pendingCaptcha,
                  Date().timeIntervalSince(pending.createdAt) <= Self.captchaContextLifetime else {
                logger.info("🖼️ EC captcha code without a valid pending context; requesting a new challenge")
                return try await requestCaptchaChallenge()
            }
            pendingCaptcha = nil
            return try await submitEcCredentials(auth: pending.auth, captchaCode: captchaCode)
        }

        pendingCaptcha = nil
        switch try await fetchEcAuthPage() {
        case .failed(let status):
            return status
        case .page(let auth, let requiresCaptcha):
            if requiresCaptcha {
                logger.info("🖼️ EC login requires captcha (RndImg=1)")
                return try await issueCaptchaChallenge(auth: auth)
            }
            return try await submitEcCredentials(auth: auth, captchaCode: nil)
        }
    }

    /// 取新的认证页与验证码图片（验证码路径）
    private func requestCaptchaChallenge() async throws -> ECLoginStatus {
        switch try await fetchEcAuthPage() {
        case .failed(let status):
            return status
        case .page(let auth, _):
            return try await issueCaptchaChallenge(auth: auth)
        }
    }

    private func fetchEcAuthPage() async throws -> ECAuthPageResult {
        logger.info("🔑 EC Login Step 1: fetching auth params...")
        let (data, _) = try await client.get("\(Self.serverURL)/por/login_auth.csp?apiversion=1")
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.isEmpty {
            logger.error("❌ EC auth response is empty")
            return .failed(ECLoginStatus(failNetworkError: true))
        }
        logger.info("📄 EC auth response received [\(body.count) bytes]")

        guard let twfMatch = body.range(of: "(?<=<TwfID>).+?(?=</TwfID>)", options: .regularExpression) else {
            logger.error("❌ TwfID not found in response")
            return .failed(ECLoginStatus(failNotFoundTwfid: true))
        }
        let twfValue = String(body[twfMatch])
        twfId = twfValue
        logger.info("✅ TwfID received")

        guard let rsaKeyMatch = body.range(of: "(?<=<RSA_ENCRYPT_KEY>).+?(?=</RSA_ENCRYPT_KEY>)", options: .regularExpression) else {
            logger.error("❌ RSA key not found")
            return .failed(ECLoginStatus(failNotFoundRsaKey: true))
        }
        let rsaKey = String(body[rsaKeyMatch])
        logger.info("✅ RSA key length: \(rsaKey.count)")

        guard let rsaExpMatch = body.range(of: "(?<=<RSA_ENCRYPT_EXP>).+?(?=</RSA_ENCRYPT_EXP>)", options: .regularExpression) else {
            logger.error("❌ RSA exponent not found")
            return .failed(ECLoginStatus(failNotFoundRsaExp: true))
        }
        let rsaExp = String(body[rsaExpMatch])
        logger.info("✅ RSA exponent: \(rsaExp)")

        guard let csrfMatch = body.range(of: "(?<=<CSRF_RAND_CODE>).+?(?=</CSRF_RAND_CODE>)", options: .regularExpression) else {
            logger.error("❌ CSRF code not found")
            return .failed(ECLoginStatus(failNotFoundCsrfCode: true))
        }
        let csrfCode = String(body[csrfMatch])
        logger.info("✅ CSRF code received")

        let requiresCaptcha = body.contains("<RndImg>1</RndImg>")
        let auth = ECAuthContext(twfId: twfValue, csrfCode: csrfCode, rsaKey: rsaKey, rsaExp: rsaExp)
        return .page(auth, requiresCaptcha: requiresCaptcha)
    }

    /// 下载验证码图片（绑定到本认证页的 TWFID），成功后保存待提交上下文
    private func issueCaptchaChallenge(auth: ECAuthContext) async throws -> ECLoginStatus {
        let (image, _) = try await client.get(
            "\(Self.serverURL)/por/rand_code.csp",
            headers: ["Cookie": "TWFID=\(auth.twfId)"]
        )
        guard !image.isEmpty else {
            logger.error("❌ EC captcha image is empty")
            return ECLoginStatus(failUnknownError: true)
        }
        pendingCaptcha = PendingCaptchaContext(auth: auth, createdAt: Date())
        logger.info("🖼️ EC captcha image received [\(image.count) bytes]")
        return ECLoginStatus(captchaRequired: true, captchaImage: image)
    }

    private func submitEcCredentials(auth: ECAuthContext, captchaCode: String?) async throws -> ECLoginStatus {
        let passwordToEncrypt = "\(ecPassword)_\(auth.csrfCode)"
        let encryptedPassword = CryptoHelper.rsaEncrypt(plaintext: passwordToEncrypt, modulusHex: auth.rsaKey, exponentStr: auth.rsaExp)
        logger.info("🔐 Encrypted password length: \(encryptedPassword.count), empty: \(encryptedPassword.isEmpty)")

        logger.info("🔑 EC Login Step 2: posting credentials...")
        let (loginData, _) = try await client.post(
            "\(Self.serverURL)/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs",
            formData: [
                "svpn_rand_code": captchaCode ?? "",
                "mitm": "",
                "svpn_req_randcode": auth.csrfCode,
                "svpn_name": userId,
                "svpn_password": encryptedPassword
            ],
            headers: ["Cookie": "TWFID=\(auth.twfId)"]
        )
        let loginBody = String(data: loginData, encoding: .utf8) ?? ""
        logger.info("📄 EC login response received [\(loginBody.count) bytes]")

        switch Self.classifyEcLoginBody(loginBody, codeSubmitted: captchaCode != nil) {
        case .success:
            await client.setCookie(name: "TWFID", value: auth.twfId, domain: ".vpn2.aufe.edu.cn")
            ecLogged = true
            await simpleClient.copyCookies(from: client)
            await noRedirectClient.copyCookies(from: client)
            logger.info("✅ EC Login succeeded")
            return ECLoginStatus(success: true)
        case .captchaRequired:
            logger.error("❌ EC Login: captcha required")
            return try await requestCaptchaChallenge()
        case .captchaInvalid:
            logger.error("❌ EC Login: captcha incorrect")
            return ECLoginStatus(captchaInvalid: true)
        case .invalidCredentials:
            logger.error("❌ EC Login: invalid credentials")
            return ECLoginStatus(failInvalidCredentials: true)
        case .unknown:
            logger.error("❌ EC Login: unknown response [\(loginBody.count) bytes]")
            return ECLoginStatus(failUnknownError: true)
        }
    }

    private enum ECLoginOutcome {
        case success, captchaRequired, captchaInvalid, invalidCredentials, unknown
    }

    /// login_psw.csp 响应分类，判定顺序固定：成功 → 验证码/风控 → 密码错误 → 未知
    private static func classifyEcLoginBody(_ body: String, codeSubmitted: Bool) -> ECLoginOutcome {
        if body.contains("<Result>1</Result>") { return .success }
        let captchaChallenge = body.contains("20023")
            || body.contains("CAPTCHA required")
            || body.contains("characters are incorrect")
        // "[CDATA[maybe attacked]]" 已被 "maybe attacked" 覆盖
        let maybeAttacked = body.contains("20041") || body.contains("maybe attacked")
        if captchaChallenge || maybeAttacked {
            return codeSubmitted && captchaChallenge ? .captchaInvalid : .captchaRequired
        }
        if body.contains("Invalid username or password!") || body.contains("20004") {
            return .invalidCredentials
        }
        return .unknown
    }

    // MARK: - UAAP Login

    func uaapLogin() async -> UAAPLoginStatus {
        do {
            return try await performUaapLogin()
        } catch {
            logger.error("UAAP login error: \(error.localizedDescription)")
            if isNetworkError(error) { return UAAPLoginStatus(failNetworkError: true) }
            return UAAPLoginStatus(failUnknownError: true)
        }
    }

    private func performUaapLogin() async throws -> UAAPLoginStatus {
        logger.info("🔑 UAAP Login Step 1: fetching CAS page...")
        let (data, casResponse) = try await client.get(Self.uaapLoginURL)
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.isEmpty {
            logger.error("❌ UAAP CAS page is empty")
            return UAAPLoginStatus(failNetworkError: true)
        }

        guard let ltMatch = body.range(of: #"(?<=name="lt" value=").+?(?=")"#, options: .regularExpression) else {
            logger.error("❌ lt not found in CAS response [\(body.count) bytes]")
            return UAAPLoginStatus(failNotFoundLt: true)
        }
        let ltValue = String(body[ltMatch])
        logger.info("✅ lt value received (len=\(ltValue.count))")

        guard let execMatch = body.range(of: #"(?<=name="execution" value=").+?(?=")"#, options: .regularExpression) else {
            logger.error("❌ execution not found")
            return UAAPLoginStatus(failNotFoundExecution: true)
        }
        let executionValue = String(body[execMatch])
        logger.info("✅ execution value received")

        let encryptedPassword = CryptoHelper.desEncrypt(plaintext: password, key: ltValue)
        logger.info("🔐 DES encrypted password generated (len=\(encryptedPassword.count))")

        logger.info("🔑 UAAP Login Step 2: posting credentials...")
        let casPostURL = formActionURL(in: body, relativeTo: casResponse.url)
            ?? casResponse.url?.absoluteString
            ?? Self.uaapLoginURL
        let (loginData, loginResponse) = try await noRedirectClient.post(
            casPostURL,
            formData: [
                "username": userId,
                "password": encryptedPassword,
                "lt": ltValue,
                "execution": executionValue,
                "_eventId": "submit",
                "submit": "LOGIN"
            ]
        )
        let loginBody = String(data: loginData, encoding: .utf8) ?? ""
        let redirectURL = loginResponse.value(forHTTPHeaderField: "Location")
        let responseUrl = redirectURL ?? loginResponse.url?.absoluteString ?? ""
        logger.info("📄 UAAP response size: \(loginBody.count), contains '用户名或密码错误': \(loginBody.contains("用户名或密码错误")), contains 'ticket': \(responseUrl.contains("ticket="))")

        // 学校强制改密：TGT 已铸出（密码正确）但 CAS 不签发票据，302 到改密页面。
        // 必须先于"密码错误"判定；该状态不可自动重试。
        if responseUrl.contains("/mng/acp/completeInfo/password") {
            logger.warning("🏫 UAAP: password change required (TGT issued, ticket refused)")
            return UAAPLoginStatus(failPasswordChangeRequired: true)
        }
        if loginBody.contains("Invalid username or password")
            || loginBody.contains("用户名或密码错误")
            || loginBody.contains("密码输入错误")
            || loginBody.contains("errorMsg") {
            logger.error("❌ UAAP Login: invalid credentials")
            return UAAPLoginStatus(failInvalidCredentials: true)
        }
        if let redirectURL,
           redirectURL.contains("ticket="),
           let callbackURL = proxiedJwcURL(from: redirectURL),
           try await establishJwcSession(from: callbackURL) {
            uaapLogged = true
            await client.copyCookies(from: noRedirectClient)
            await simpleClient.copyCookies(from: client)
            await noRedirectClient.copyCookies(from: client)
            logger.info("✅ UAAP Login succeeded")
            return UAAPLoginStatus(success: true)
        }
        let responseScheme = loginResponse.url?.scheme ?? ""
        let responseHost = loginResponse.url?.host ?? ""
        let responsePath = loginResponse.url?.path ?? ""
        let hasTicket = responseUrl.contains("ticket=")
        let hasLoginForm = loginBody.contains("name=\"username\"") || loginBody.contains("name='username'")
        let hasCasError = loginBody.contains("登录失败") || loginBody.contains("认证失败")
        let hasErrorMessage = loginBody.contains("errorMsg")
        logger.error("❌ UAAP unknown status=\(loginResponse.statusCode, privacy: .public), bodyLength=\(loginBody.count, privacy: .public)")
        logger.error("❌ UAAP unknown location: scheme=\(responseScheme, privacy: .public), host=\(responseHost, privacy: .public), path=\(responsePath, privacy: .public)")
        logger.error("❌ UAAP unknown features: ticket=\(hasTicket, privacy: .public), loginForm=\(hasLoginForm, privacy: .public), casError=\(hasCasError, privacy: .public), errorMsg=\(hasErrorMessage, privacy: .public)")
        return UAAPLoginStatus(failUnknownError: true)
    }

    private func formActionURL(in html: String, relativeTo baseURL: URL?) -> String? {
        let pattern = #"<form\b[^>]*\baction=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let actionRange = Range(match.range(at: 1), in: html) else { return nil }

        let action = String(html[actionRange])
        if let baseURL, let resolved = URL(string: action, relativeTo: baseURL)?.absoluteString {
            return resolved
        }
        return URL(string: action)?.absoluteString
    }

    private func proxiedJwcURL(from redirectURL: String) -> String? {
        guard var components = URLComponents(string: redirectURL),
              components.host?.contains("jwcxk2") == true else { return nil }
        components.scheme = "http"
        components.host = "jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn"
        components.port = 8118
        return components.url?.absoluteString
    }

    private func establishJwcSession(from callbackURL: String) async throws -> Bool {
        var nextURL = callbackURL

        for _ in 0..<8 {
            let (data, response) = try await noRedirectClient.get(nextURL)
            guard (301...308).contains(response.statusCode),
                  let location = response.value(forHTTPHeaderField: "Location") else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.info("JWC callback response: status=\(response.statusCode, privacy: .public), bodyLength=\(body.count, privacy: .public)")
                return response.statusCode == 200 && !body.isEmpty
            }

            guard let baseURL = response.url ?? URL(string: nextURL),
                  let resolvedURL = URL(string: location, relativeTo: baseURL)?.absoluteString else {
                return false
            }
            nextURL = proxiedJwcURL(from: resolvedURL) ?? resolvedURL
        }

        logger.error("JWC callback exceeded redirect limit")
        return false
    }

    var isHealthy: Bool { ecLogged && uaapLogged }

    private func isNetworkError(_ error: Error) -> Bool {
        error is URLError || (error as NSError).domain == NSURLErrorDomain
    }
}

// MARK: - HTTPClient extension for session expired

extension HTTPClient {
    func setSessionExpired(_ callback: @escaping @Sendable () -> Void) {
        self.onSessionExpired = callback
    }
}

// MARK: - CryptoHelper

enum CryptoHelper {
    static func rsaEncrypt(plaintext: String, modulusHex: String, exponentStr: String) -> String {
        guard let plainData = plaintext.data(using: .utf8) else { return "" }
        guard let modulusData = hexToData(modulusHex) else { return "" }
        guard let exponent = UInt32(exponentStr) else { return "" }

        var expBytes = withUnsafeBytes(of: exponent.bigEndian) { Array($0) }
        while expBytes.first == 0 && expBytes.count > 1 { expBytes.removeFirst() }
        let exponentBytes = Data(expBytes)

        let keyData = buildDERPublicKey(modulus: modulusData, exponent: exponentBytes)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: modulusData.count * 8,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            return ""
        }
        guard let encrypted = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, plainData as CFData, &error) else {
            return ""
        }
        return (encrypted as Data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next != idx else { break }
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        return data
    }

    private static func buildDERPublicKey(modulus: Data, exponent: Data) -> Data {
        var modulusBytes = modulus
        if modulusBytes.first! >= 0x80 { modulusBytes.insert(0x00, at: 0) }
        var exponentBytes = exponent
        if exponentBytes.first! >= 0x80 { exponentBytes.insert(0x00, at: 0) }

        let modTLV = derInteger(modulusBytes)
        let expTLV = derInteger(exponentBytes)
        let sequence = derSequence(modTLV + expTLV)

        let bitString = Data([0x03]) + derLength(sequence.count + 1) + Data([0x00]) + sequence
        let algorithmOID: [UInt8] = [
            0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86,
            0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00
        ]
        let outerSequence = derSequence(Data(algorithmOID) + bitString)
        return outerSequence
    }

    private static func derInteger(_ data: Data) -> Data {
        Data([0x02]) + derLength(data.count) + data
    }

    private static func derSequence(_ data: Data) -> Data {
        Data([0x30]) + derLength(data.count) + data
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        if length < 0x100 { return Data([0x81, UInt8(length)]) }
        return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
    }

    static func desEncrypt(plaintext: String, key: String) -> String {
        guard let plainData = plaintext.data(using: .utf8) else { return "" }
        var keyBytes = Array(key.utf8)
        if keyBytes.count > 8 { keyBytes = Array(keyBytes.prefix(8)) }
        while keyBytes.count < 8 { keyBytes.append(0) }

        var tripleKey = [UInt8](repeating: 0, count: 24)
        for i in 0..<8 { tripleKey[i] = keyBytes[i]; tripleKey[i+8] = keyBytes[i]; tripleKey[i+16] = keyBytes[i] }

        let bufferSize = plainData.count + kCCBlockSize3DES
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesEncrypted: size_t = 0

        let status = plainData.withUnsafeBytes { plainBytes in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithm3DES),
                    CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                    tripleKey, kCCKeySize3DES, nil,
                    plainBytes.baseAddress, plainData.count,
                    &buffer, bufferSize, &numBytesEncrypted)
        }

        guard status == kCCSuccess else { return "" }
        return Data(buffer.prefix(numBytesEncrypted)).base64EncodedString()
    }
}
