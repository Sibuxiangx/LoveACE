import Foundation
import os

private let logger = Logger(subsystem: "tech.loveace.loveaceios", category: "AuthViewModel")

enum AuthState { case initial, loading, reconnecting, authenticated, unauthenticated, error }

private enum ReauthenticationResult {
    case success(AUFEConnection)
    case unavailable
    case failed
}

@MainActor
@Observable
final class AuthViewModel {
    var state: AuthState = .initial
    var errorMessage: String?
    var userId: String = ""

    private let credentialStore = CredentialStore()
    private var heartbeatTask: Task<Void, Never>?
    private var authenticationTask: Task<Void, Never>?
    private var isReconnecting = false
    private var currentAuthenticationAttempt = UUID()

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

    func login(userId: String, password: String, gatewayPassword: String? = nil) {
        authenticationTask?.cancel()
        stopHeartbeat()
        clearServices()
        let attempt = UUID()
        currentAuthenticationAttempt = attempt
        authenticationTask = Task {
            state = .loading; errorMessage = nil
            let ecPassword = gatewayPassword.flatMap { $0.isEmpty ? nil : $0 } ?? password
            let conn = AUFEConnection(userId: userId, ecPassword: ecPassword, password: password)
            await conn.startClient()

            let ecResult = await conn.ecLogin()
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            guard ecResult.success else {
                let msg: String
                if ecResult.failInvalidCredentials { msg = "学号或密码错误" }
                else if ecResult.failMaybeAttacked { msg = "登录过于频繁，请稍后再试" }
                else if ecResult.failNetworkError { msg = "网络连接失败" }
                else { msg = "登录失败，请稍后重试" }
                Analytics.shared.trackLoginFailed(userId: userId, reason: msg)
                state = .error; errorMessage = msg; return
            }

            let uaapResult = await conn.uaapLogin()
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            guard uaapResult.success else {
                let msg: String
                if uaapResult.failInvalidCredentials { msg = "学号或密码错误" }
                else if uaapResult.failNetworkError { msg = "网络连接失败" }
                else { msg = "教务系统登录失败" }
                Analytics.shared.trackLoginFailed(userId: userId, reason: msg)
                state = .error; errorMessage = msg; return
            }

            connection = conn
            initServices(conn)
            await wireSessionExpiredHandler(conn)
            startHeartbeat()
            credentialStore.save(UserCredentials(userId: userId, ecPassword: ecPassword, password: password))
            credentialStore.saveRemembered(UserCredentials(userId: userId, ecPassword: ecPassword, password: password))
            self.userId = userId
            Analytics.shared.trackLoginSuccess(userId: userId)
            state = .authenticated
            sessionGeneration += 1
            logger.info("Login successful")
        }
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
                state = .unauthenticated; return
            }
            let uaap = await conn.uaapLogin()
            guard !Task.isCancelled, attempt == currentAuthenticationAttempt else { return }
            guard uaap.success else {
                Analytics.shared.trackLoginFailed(userId: creds.userId, reason: "restore_uaap_failed")
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
        guard ec.success else { return .failed }

        let uaap = await conn.uaapLogin()
        if uaap.failNetworkError { return .unavailable }
        guard uaap.success else { return .failed }
        return .success(conn)
    }

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
