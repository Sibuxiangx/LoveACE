import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "AuthViewModel")

enum AuthState { case initial, loading, reconnecting, authenticated, unauthenticated, error }

private enum ReauthenticationResult {
    case success(AUFEConnection)
    case unavailable
    case failed
    case passwordChangeRequired
    case captchaRequired
}

/// 本地登录失败计数与冷却（UserDefaults，按学号分键；不含密码，不入钥匙串）
enum LoginThrottle {
    private static let failuresKeyPrefix = "login_throttle.failures."
    private static let cooldownKeyPrefix = "login_throttle.cooldown_until."

    /// 冷却阶梯（按连续失败次数）：1 次无冷却，2 次 30 秒，3 次 120 秒，≥4 次 600 秒
    static func cooldownSeconds(afterFailures failures: Int) -> Int {
        switch failures {
        case ..<2: return 0
        case 2: return 30
        case 3: return 120
        default: return 600
        }
    }

    /// 记录一次失败并返回冷却截止时间（无冷却时返回 nil）
    static func recordFailure(for userId: String, now: Date = Date()) -> Date? {
        let defaults = UserDefaults.standard
        let failures = defaults.integer(forKey: failuresKeyPrefix + userId) + 1
        let until = now.addingTimeInterval(TimeInterval(cooldownSeconds(afterFailures: failures)))
        defaults.set(failures, forKey: failuresKeyPrefix + userId)
        defaults.set(until.timeIntervalSince1970, forKey: cooldownKeyPrefix + userId)
        return until > now ? until : nil
    }

    /// 尚未过期的冷却截止时间
    static func activeCooldown(for userId: String, now: Date = Date()) -> Date? {
        let until = UserDefaults.standard.double(forKey: cooldownKeyPrefix + userId)
        return until > now.timeIntervalSince1970 ? Date(timeIntervalSince1970: until) : nil
    }

    /// 登录成功：清除该学号的失败计数与冷却
    static func reset(for userId: String) {
        UserDefaults.standard.removeObject(forKey: failuresKeyPrefix + userId)
        UserDefaults.standard.removeObject(forKey: cooldownKeyPrefix + userId)
    }

    /// 距冷却结束的剩余秒数（向上取整，最小 0）
    static func remainingSeconds(until: Date, now: Date = Date()) -> Int {
        max(0, Int(ceil(until.timeIntervalSince(now))))
    }
}

/// 待提交验证码的连接与凭据（仅内存）；提交或重新取图时使用同一连接的认证上下文
private struct PendingCaptcha {
    let credentials: UserCredentials
    let connection: AUFEConnection
}

@MainActor
@Observable
final class AuthViewModel {
    var state: AuthState = .initial
    var errorMessage: String?
    var userId: String = ""
    /// 学校 UAAP/CAS 强制改密拦截（不是密码错误：不清凭据、不计密码失败、不自动重试）
    var passwordChangeRequired = false
    /// 学校要求验证码时的图片（GIF 字节）；nil 表示当前不需要验证码
    var captchaImage: Data?
    /// 当前学号的登录冷却截止时间；nil 表示无冷却
    var cooldownUntil: Date?

    private let credentialStore = CredentialStore()
    private var heartbeatTask: Task<Void, Never>?
    private var authenticationTask: Task<Void, Never>?
    private var isReconnecting = false
    private var currentAuthenticationAttempt = UUID()
    /// 验证码待提交的连接与凭据；captchaImage 为 nil 时必为 nil
    private var pendingCaptcha: PendingCaptcha?
    private static let captchaReloginMessage = "学校要求输入验证码，请重新登录"

    private(set) var connection: AUFEConnection?
    private(set) var jwcService: JWCService?
    private(set) var yktService: YKTService?
    private(set) var isimService: ISIMService?
    private(set) var aacService: AACService?
    private(set) var laborClubService: LaborClubService?
    private(set) var competitionService: CompetitionService?
    private(set) var studentScheduleService: StudentScheduleService?
    private(set) var courseScheduleService: CourseScheduleService?
    private(set) var planService: PlanService?
    private(set) var repairService: RepairService?
    private(set) var teacherEvaluationService: TeacherEvaluationService?

    private(set) var sessionGeneration = 0

    var isAuthenticated: Bool { state == .authenticated }

    /// 用户发起的登录。`captchaCode` 仅在学校要求验证码后传入（已 trim）。
    func login(userId: String, password: String, gatewayPassword: String? = nil, captchaCode: String? = nil) {
        if let until = LoginThrottle.activeCooldown(for: userId) {
            cooldownUntil = until
            errorMessage = "请 \(LoginThrottle.remainingSeconds(until: until)) 秒后再试"
            return
        }
        let ecPassword = gatewayPassword.flatMap { $0.isEmpty ? nil : $0 } ?? password
        let credentials = UserCredentials(userId: userId, ecPassword: ecPassword, password: password)
        // 验证码图片绑定在某个连接的认证上下文上：凭据未变时复用该连接，否则新建连接
        let pending = pendingCaptcha
        pendingCaptcha = nil
        if let pending, isSameCredentials(pending.credentials, credentials) {
            startAuthentication(on: pending.connection, credentials: credentials,
                                captchaCode: captchaCode, reusesConnection: true)
        } else {
            startAuthentication(on: AUFEConnection(userId: userId, ecPassword: ecPassword, password: password),
                                credentials: credentials, captchaCode: captchaCode, reusesConnection: false)
        }
    }

    private func startAuthentication(on conn: AUFEConnection, credentials: UserCredentials,
                                     captchaCode: String?, reusesConnection: Bool) {
        authenticationTask?.cancel()
        stopHeartbeat()
        clearServices()
        let attempt = UUID()
        currentAuthenticationAttempt = attempt
        authenticationTask = Task {
            state = .loading; errorMessage = nil
            if !reusesConnection { await conn.startClient() }
            await authenticate(on: conn, credentials: credentials, captchaCode: captchaCode, attempt: attempt)
        }
    }

    private func authenticate(on conn: AUFEConnection, credentials: UserCredentials,
                              captchaCode: String?, attempt: UUID) async {
        let userId = credentials.userId
        var ecResult = await conn.ecLogin(captchaCode: captchaCode)
        guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }

        var captchaMessage: String?
        if ecResult.captchaInvalid {
            // 验证码错误计入失败次数，并立即重新取图（不计失败）
            recordLoginFailure(for: userId)
            Analytics.shared.trackLoginFailed(userId: userId, reason: "captcha_invalid")
            ecResult = await conn.ecLogin(captchaCode: nil)
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            captchaMessage = "验证码错误，请重新输入"
        }
        if ecResult.captchaRequired, let image = ecResult.captchaImage {
            presentCaptcha(image, on: conn, credentials: credentials)
            state = .error; errorMessage = captchaMessage ?? "学校要求输入验证码"
            return
        }

        guard ecResult.success else {
            // 非验证码结果：清除验证码状态；仅密码错误计入失败次数
            clearCaptcha()
            let msg: String
            if ecResult.failInvalidCredentials {
                recordLoginFailure(for: userId)
                msg = "学号或密码错误"
            } else if ecResult.failNetworkError { msg = "网络连接失败" }
            else { msg = "登录失败，请稍后重试" }
            Analytics.shared.trackLoginFailed(userId: userId, reason: msg)
            state = .error; errorMessage = msg; return
        }

        clearCaptcha()
        let uaapResult = await conn.uaapLogin()
        guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
        guard uaapResult.success else {
            if uaapResult.failPasswordChangeRequired {
                // 学校强制改密：TGT 已铸出（密码正确），CAS 拒绝签发票据。
                // 不是密码错误：不清凭据、不计密码失败、不自动重试，本次会话作废
                logger.warning("Password change required for \(userId)")
                Analytics.shared.trackLoginFailed(userId: userId, reason: "password_change_required")
                state = .error; errorMessage = nil; passwordChangeRequired = true; return
            }
            let msg: String
            if uaapResult.failInvalidCredentials {
                recordLoginFailure(for: userId)
                msg = "学号或密码错误"
            } else if uaapResult.failNetworkError { msg = "网络连接失败" }
            else { msg = "教务系统登录失败" }
            Analytics.shared.trackLoginFailed(userId: userId, reason: msg)
            state = .error; errorMessage = msg; return
        }

        LoginThrottle.reset(for: userId)
        cooldownUntil = nil
        connection = conn
        initServices(conn)
        await wireSessionExpiredHandler(conn)
        startHeartbeat()
        credentialStore.save(credentials)
        credentialStore.saveRemembered(credentials)
        self.userId = userId
        Analytics.shared.trackLoginSuccess(userId: userId)
        state = .authenticated
        sessionGeneration += 1
        logger.info("Login successful")
    }

    /// 点击验证码图片：用同一连接重新取图（ecLogin(nil)）。冷却期内不触网。
    func refreshCaptcha() {
        guard let pending = pendingCaptcha, state != .loading else { return }
        if let until = LoginThrottle.activeCooldown(for: pending.credentials.userId) {
            cooldownUntil = until
            errorMessage = "请 \(LoginThrottle.remainingSeconds(until: until)) 秒后再试"
            return
        }
        startAuthentication(on: pending.connection, credentials: pending.credentials,
                            captchaCode: nil, reusesConnection: true)
    }

    /// 学号变化：清除验证码状态，并载入新学号的持久化冷却
    func userIdDidChange(to userId: String) {
        clearCaptcha()
        cooldownUntil = LoginThrottle.activeCooldown(for: userId)
    }

    private func presentCaptcha(_ image: Data, on conn: AUFEConnection, credentials: UserCredentials) {
        pendingCaptcha = PendingCaptcha(credentials: credentials, connection: conn)
        captchaImage = image
    }

    private func clearCaptcha() {
        captchaImage = nil
        pendingCaptcha = nil
    }

    private func recordLoginFailure(for userId: String) {
        cooldownUntil = LoginThrottle.recordFailure(for: userId)
    }

    private func isSameCredentials(_ lhs: UserCredentials, _ rhs: UserCredentials) -> Bool {
        lhs.userId == rhs.userId && lhs.ecPassword == rhs.ecPassword && lhs.password == rhs.password
    }

    func restoreSession() {
        guard let creds = credentialStore.load() ?? credentialStore.loadRemembered() else {
            state = .unauthenticated; return
        }
        authenticationTask?.cancel()
        let attempt = UUID()
        currentAuthenticationAttempt = attempt
        authenticationTask = Task {
            state = .loading
            let conn = AUFEConnection(userId: creds.userId, ecPassword: creds.ecPassword, password: creds.password)
            await conn.startClient()
            let ec = await conn.ecLogin()
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            guard ec.success else {
                Analytics.shared.trackLoginFailed(userId: creds.userId, reason: "restore_ec_failed")
                if ec.captchaRequired { errorMessage = Self.captchaReloginMessage }
                state = .unauthenticated; return
            }
            let uaap = await conn.uaapLogin()
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            guard uaap.success else {
                if uaap.failPasswordChangeRequired {
                    // 学校强制改密：不是密码错误，不清凭据，抛给 UI 提示
                    Analytics.shared.trackLoginFailed(userId: creds.userId, reason: "password_change_required")
                    passwordChangeRequired = true
                } else {
                    Analytics.shared.trackLoginFailed(userId: creds.userId, reason: "restore_uaap_failed")
                }
                state = .unauthenticated; return
            }
            connection = conn
            initServices(conn)
            await wireSessionExpiredHandler(conn)
            startHeartbeat()
            credentialStore.save(creds)
            userId = creds.userId
            Analytics.shared.trackLoginSuccess(userId: creds.userId)
            state = .authenticated
            sessionGeneration += 1
            logger.info("Session restored")
        }
    }

    func logout() {
        currentAuthenticationAttempt = UUID()
        authenticationTask?.cancel()
        authenticationTask = nil
        clearCaptcha()
        stopHeartbeat()
        clearServices()
        credentialStore.clear()
        Analytics.shared.clearUser()
        state = .unauthenticated
        logger.info("Logged out")
    }

    func verifyPassword(_ input: String) -> Bool {
        guard let creds = credentialStore.load() else { return false }
        return input == creds.password || input == creds.ecPassword
    }

    func getRememberedCredentials() -> UserCredentials? { credentialStore.loadRemembered() }
    func clearSavedCredentials() { credentialStore.clear(); credentialStore.clearRemembered() }

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(240))
                guard let conn = connection, !Task.isCancelled else { break }
                switch await conn.heartbeat() {
                case .alive, .unavailable:
                    continue
                case .expired:
                    if !isReconnecting { await handleSessionExpired(for: conn) }
                }
            }
        }
    }

    private func stopHeartbeat() { heartbeatTask?.cancel(); heartbeatTask = nil }

    private func handleSessionExpired(for expiredConnection: AUFEConnection) async {
        guard !isReconnecting,
              state == .authenticated,
              let activeConnection = connection,
              activeConnection === expiredConnection else { return }
        isReconnecting = true
        defer { isReconnecting = false }
        state = .reconnecting
        logger.info("Auto-reconnecting...")
        Analytics.shared.trackSessionExpired(reason: "session_expired")

        guard let credentials = credentialStore.load() ?? credentialStore.loadRemembered() else {
            finishAutomaticSignOut()
            return
        }

        switch await reauthenticate(using: credentials) {
        case .success(let conn):
            connection = conn
            initServices(conn)
            await wireSessionExpiredHandler(conn)
            sessionGeneration += 1
            state = .authenticated
            startHeartbeat()
            Analytics.shared.trackSessionReconnectSuccess()
            logger.info("Auto-reconnect succeeded")
        case .unavailable:
            state = .authenticated
            startHeartbeat()
            logger.warning("Auto-reconnect deferred because the network is unavailable")
        case .passwordChangeRequired:
            // 学校强制改密：停止重连（再连也会被拦截），不清凭据，把状态抛给 UI
            logger.warning("Password change required, stop reconnecting")
            Analytics.shared.trackSessionReconnectFailed()
            finishPasswordChangeIntercepted()
        case .captchaRequired:
            // 学校要求验证码：后台无法输入验证码。结束重连，保留凭据供登录页预填；不计失败
            logger.warning("Captcha required during auto-reconnect, stop reconnecting")
            Analytics.shared.trackSessionReconnectFailed()
            finishCaptchaRequiredOnReconnect()
        case .failed:
            Analytics.shared.trackSessionReconnectFailed()
            finishAutomaticSignOut()
        }
    }

    private func reauthenticate(using credentials: UserCredentials) async -> ReauthenticationResult {
        let conn = AUFEConnection(
            userId: credentials.userId,
            ecPassword: credentials.ecPassword,
            password: credentials.password
        )
        await conn.startClient()
        let ec = await conn.ecLogin()
        if ec.failNetworkError { return .unavailable }
        if ec.captchaRequired { return .captchaRequired }
        guard ec.success else { return .failed }

        let uaap = await conn.uaapLogin()
        if uaap.failNetworkError { return .unavailable }
        if uaap.failPasswordChangeRequired { return .passwordChangeRequired }
        guard uaap.success else { return .failed }
        return .success(conn)
    }

    /// 自动重连遇到学校验证码：结束重连回到未登录态，保留凭据以便登录页预填
    private func finishCaptchaRequiredOnReconnect() {
        stopHeartbeat()
        clearServices()
        clearCaptcha()
        currentAuthenticationAttempt = UUID()
        errorMessage = Self.captchaReloginMessage
        state = .unauthenticated
    }

    /// 学校强制改密拦截：停止重连、半成品会话作废，但不清除本地凭据（不是密码错误），状态抛给 UI
    private func finishPasswordChangeIntercepted() {
        stopHeartbeat()
        clearServices()
        currentAuthenticationAttempt = UUID()
        errorMessage = nil
        passwordChangeRequired = true
        state = .unauthenticated
    }

    func dismissPasswordChange() { passwordChangeRequired = false }

    private func finishAutomaticSignOut() {
        stopHeartbeat()
        clearServices()
        credentialStore.clear()
        currentAuthenticationAttempt = UUID()
        errorMessage = "会话已过期，请重新登录"
        state = .unauthenticated
    }

    private func wireSessionExpiredHandler(_ conn: AUFEConnection) async {
        await conn.setOnSessionExpired { [weak self, weak conn] in
            guard let conn else { return }
            Task { @MainActor [weak self] in
                await self?.handleSessionExpired(for: conn)
            }
        }
    }

    private func initServices(_ conn: AUFEConnection) {
        jwcService = JWCService(connection: conn)
        yktService = YKTService(connection: conn)
        isimService = ISIMService(connection: conn)
        aacService = AACService(connection: conn)
        laborClubService = LaborClubService(connection: conn)
        competitionService = CompetitionService(connection: conn)
        studentScheduleService = StudentScheduleService(connection: conn)
        courseScheduleService = CourseScheduleService(connection: conn)
        planService = PlanService(connection: conn)
        repairService = RepairService(connection: conn)
        teacherEvaluationService = TeacherEvaluationService(connection: conn)
    }

    private func clearServices() {
        connection = nil; jwcService = nil; yktService = nil; isimService = nil
        aacService = nil; laborClubService = nil; competitionService = nil
        studentScheduleService = nil; courseScheduleService = nil; planService = nil; repairService = nil
        teacherEvaluationService = nil
    }
}
