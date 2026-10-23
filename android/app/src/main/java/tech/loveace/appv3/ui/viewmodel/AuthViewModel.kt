package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.data.local.CredentialStore
import tech.loveace.appv3.data.local.ScheduleStore
import tech.loveace.appv3.data.model.ECLoginStatus
import tech.loveace.appv3.data.model.UserCredentials
import tech.loveace.appv3.data.network.AUFEConnection
import tech.loveace.appv3.util.hasFullWidthChars
import tech.loveace.appv3.data.service.*

enum class AuthState { Initial, Loading, Authenticated, Unauthenticated, Error }

data class AuthUiState(
    val state: AuthState = AuthState.Initial,
    val errorMessage: String? = null,
    val userId: String = "",
    /** 学校 UAAP/CAS 强制改密拦截（不是密码错误：不清凭据、不计密码失败、不自动重试） */
    val passwordChangeRequired: Boolean = false,
    /** 学校要求的验证码图片（GIF 原始字节）；非 null 时登录页显示验证码输入行 */
    val captchaImage: ByteArray? = null,
    /** 当前学号的登录冷却截止时刻（epoch ms）；不大于当前时间表示无冷却 */
    val cooldownUntil: Long = 0L,
)

/**
 * 登录失败冷却阶梯（按累计失败次数）：
 * 第 1 次无冷却，第 2 次 30 秒，第 3 次 120 秒，第 4 次及以后 600 秒。
 */
internal fun loginCooldownMillis(failures: Int): Long = when {
    failures <= 1 -> 0L
    failures == 2 -> 30_000L
    failures == 3 -> 120_000L
    else -> 600_000L
}

/** 等待验证码提交的登录会话：连接对象内保存单次使用的认证上下文，凭据用于判断是否可复用 */
private class CaptchaSession(
    val connection: AUFEConnection,
    val userId: String,
    val ecPassword: String,
    val password: String,
) {
    fun matches(userId: String, ecPassword: String, password: String): Boolean =
        this.userId == userId && this.ecPassword == ecPassword && this.password == password
}

/**
 * 认证 ViewModel
 * - 管理登录状态和所有服务实例
 * - 心跳保活：每 4 分钟 ping VPN，防止 session 过期
 * - Session 过期检测：HttpClient 嗅探到 VPN 登录页时自动重连
 */
class AuthViewModel(application: Application) : AndroidViewModel(application) {

    private val credentialStore = CredentialStore(application)

    private val loginPrefs = application.getSharedPreferences(LOGIN_PREFS_NAME, Context.MODE_PRIVATE)

    /** 等待验证码提交的登录会话（同一连接，保证验证码的认证上下文可用） */
    private var captchaSession: CaptchaSession? = null

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    private var heartbeatJob: Job? = null
    private var isReconnecting = false

    // Connection and services
    var connection: AUFEConnection? = null
        private set
    var jwcService: JWCService? = null
        private set
    var yktService: YKTService? = null
        private set
    var isimService: ISIMService? = null
        private set
    var aacService: AACService? = null
        private set
    var laborClubService: LaborClubService? = null
        private set
    var competitionService: CompetitionService? = null
        private set
    var studentScheduleService: StudentScheduleService? = null
        private set
    var courseScheduleService: CourseScheduleService? = null
        private set
    var planService: PlanService? = null
        private set
    var repairService: RepairService? = null
        private set
    var teacherEvaluationService: TeacherEvaluationService? = null
        private set

    val isAuthenticated get() = _uiState.value.state == AuthState.Authenticated

    // ==================== Login ====================

    /**
     * 登录（用户主动操作）。
     * - 冷却期内不触网，仅更新冷却状态。
     * - [captchaCode] 为 null：首次登录；学校要求验证码时返回图片并等待输入（不计失败）。
     * - [captchaCode] 非空：在同一连接（同一认证上下文）上提交验证码。
     */
    fun login(userId: String, ecPassword: String, password: String, captchaCode: String? = null) {
        val now = System.currentTimeMillis()
        val cooldownUntil = loadCooldownUntil(userId)
        if (cooldownUntil > now) {
            _uiState.value = _uiState.value.copy(cooldownUntil = cooldownUntil)
            return
        }
        val code = captchaCode?.trim()
        if (code != null && hasFullWidthChars(code)) {
            _uiState.value = _uiState.value.copy(errorMessage = "验证码含全角字符，请用英文半角")
            return
        }
        viewModelScope.launch {
            val session = captchaSession
            captchaSession = null
            // 仅当验证码非空且凭据未变时复用连接，否则视为新登录（验证码上下文不存在则会重新取图）
            val reusable = session?.takeIf { !code.isNullOrEmpty() && it.matches(userId, ecPassword, password) }
            _uiState.value = AuthUiState(
                state = AuthState.Loading,
                captchaImage = _uiState.value.captchaImage,
                cooldownUntil = cooldownUntil,
            )
            try {
                val conn = reusable?.connection ?: AUFEConnection(userId, ecPassword, password).also { it.startClient() }

                // EC (VPN) login
                val ecResult = conn.ecLogin(code)
                if (!ecResult.success) {
                    val image = ecResult.captchaImage
                    if (ecResult.failCaptchaRequired && image != null) {
                        publishCaptchaRequired(conn, userId, ecPassword, password, image, CAPTCHA_REQUIRED_MESSAGE)
                        return@launch
                    }
                    if (ecResult.failCaptchaInvalid) {
                        // 验证码错误：计失败，并在同一连接上立即获取新图片（不提交密码）
                        recordLoginFailure(userId)
                        Analytics.trackLoginFailed(userId, "验证码错误")
                        val retry = conn.ecLogin(null)
                        val retryImage = retry.captchaImage
                        if (retry.failCaptchaRequired && retryImage != null) {
                            publishCaptchaRequired(conn, userId, ecPassword, password, retryImage, "验证码错误，请重新输入")
                        } else {
                            val msg = ecFailureMessage(retry)
                            Analytics.trackLoginFailed(userId, msg)
                            publishLoginState(userId, AuthState.Error, errorMessage = msg)
                        }
                        return@launch
                    }
                    if (ecResult.failInvalidCredentials) recordLoginFailure(userId)
                    val msg = ecFailureMessage(ecResult)
                    Analytics.trackLoginFailed(userId, msg)
                    publishLoginState(userId, AuthState.Error, errorMessage = msg)
                    return@launch
                }

                // UAAP (CAS) login
                val uaapResult = conn.uaapLogin()
                if (!uaapResult.success) {
                    if (uaapResult.failPasswordChangeRequired) {
                        // 学校强制改密：TGT 已铸出（密码正确），CAS 拒绝签发票据。
                        // 不是密码错误：不清凭据、不计密码失败、不自动重试，本次会话作废
                        Log.w(TAG, "🏫 Password change required for $userId")
                        Analytics.trackLoginFailed(userId, "password_change_required")
                        publishLoginState(userId, AuthState.Error, passwordChangeRequired = true)
                        return@launch
                    }
                    val msg = when {
                        uaapResult.failInvalidCredentials -> "教务系统密码错误"
                        uaapResult.failNetworkError -> "网络连接失败"
                        else -> "UAAP 登录失败"
                    }
                    if (uaapResult.failInvalidCredentials) recordLoginFailure(userId)
                    Analytics.trackLoginFailed(userId, msg)
                    publishLoginState(userId, AuthState.Error, errorMessage = msg)
                    return@launch
                }

                connection = conn
                initServices(conn)
                wireSessionExpiredHandler(conn)
                startHeartbeat()
                resetLoginFailures(userId)

                // 始终保存凭证（用于会话恢复和快速登录）
                credentialStore.save(UserCredentials(userId, ecPassword, password))
                credentialStore.saveRemembered(UserCredentials(userId, ecPassword, password))

                _uiState.value = AuthUiState(state = AuthState.Authenticated, userId = userId)
                Analytics.trackLoginSuccess(userId)
                Log.i(TAG, "✅ Login successful: $userId")
            } catch (e: Exception) {
                Log.e(TAG, "Login error", e)
                Analytics.trackLoginFailed(userId, "登录异常")
                _uiState.value = AuthUiState(state = AuthState.Error, errorMessage = "登录异常: ${e.message}")
            }
        }
    }

    /**
     * 进入验证码等待态。状态使用 Initial 而非 Error/Unauthenticated：后两者会触发导航回登录页，
     * 导致用户已输入的学号、密码和验证码被重置。
     */
    private fun publishCaptchaRequired(
        conn: AUFEConnection,
        userId: String,
        ecPassword: String,
        password: String,
        image: ByteArray,
        message: String,
    ) {
        captchaSession = CaptchaSession(conn, userId, ecPassword, password)
        publishLoginState(userId, AuthState.Initial, errorMessage = message, captchaImage = image)
    }

    /** 统一发布登录相关状态；冷却截止时刻从持久化存储读取 */
    private fun publishLoginState(
        userId: String,
        state: AuthState,
        errorMessage: String? = null,
        captchaImage: ByteArray? = null,
        passwordChangeRequired: Boolean = false,
    ) {
        _uiState.value = AuthUiState(
            state = state,
            errorMessage = errorMessage,
            passwordChangeRequired = passwordChangeRequired,
            captchaImage = captchaImage,
            cooldownUntil = loadCooldownUntil(userId),
        )
    }

    /** 用户切换学号（或进入登录页）：清除验证码状态，并载入该学号的持久化冷却 */
    fun onUserIdChanged(userId: String) {
        captchaSession = null
        _uiState.value = _uiState.value.copy(captchaImage = null, cooldownUntil = loadCooldownUntil(userId))
    }

    private fun ecFailureMessage(status: ECLoginStatus): String = when {
        status.failInvalidCredentials -> "VPN 账号或密码错误"
        status.failNetworkError -> "网络连接失败"
        else -> "VPN 登录失败"
    }

    /** 计入一次失败（密码错误 / 验证码错误），按阶梯写入冷却截止时刻 */
    private fun recordLoginFailure(userId: String) {
        val failures = loginPrefs.getInt(failuresKey(userId), 0) + 1
        val until = System.currentTimeMillis() + loginCooldownMillis(failures)
        loginPrefs.edit()
            .putInt(failuresKey(userId), failures)
            .putLong(cooldownKey(userId), until)
            .apply()
    }

    private fun resetLoginFailures(userId: String) {
        loginPrefs.edit()
            .remove(failuresKey(userId))
            .remove(cooldownKey(userId))
            .apply()
    }

    private fun loadCooldownUntil(userId: String): Long = loginPrefs.getLong(cooldownKey(userId), 0L)

    private fun failuresKey(userId: String) = "failures_$userId"

    private fun cooldownKey(userId: String) = "cooldown_until_$userId"

    // ==================== Session Restore ====================

    fun restoreSession() {
        // 优先用 session 凭证，没有则用 remembered 凭证（退出登录后快速登录场景）
        val creds = credentialStore.load() ?: credentialStore.loadRemembered() ?: run {
            _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
            return
        }
        viewModelScope.launch {
            _uiState.value = AuthUiState(state = AuthState.Loading)
            try {
                val conn = AUFEConnection(creds.userId, creds.ecPassword, creds.password)
                conn.startClient()

                val ecResult = conn.ecLogin()
                if (!ecResult.success) {
                    if (ecResult.failCaptchaRequired) {
                        // 快速登录无法人工输入验证码：回到登录页（预填已保存账号）并提示，不清凭据
                        Log.w(TAG, "🔐 Captcha required on session restore")
                        _uiState.value = AuthUiState(state = AuthState.Unauthenticated, errorMessage = CAPTCHA_RELOGIN_MESSAGE)
                        return@launch
                    }
                    Analytics.trackLoginFailed(creds.userId, "VPN 登录失败")
                    _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
                    return@launch
                }

                val uaapResult = conn.uaapLogin()
                if (!uaapResult.success) {
                    if (uaapResult.failPasswordChangeRequired) {
                        // 学校强制改密：不是密码错误，不清凭据，抛给 UI 提示
                        Analytics.trackLoginFailed(creds.userId, "password_change_required")
                        _uiState.value = AuthUiState(state = AuthState.Unauthenticated, passwordChangeRequired = true)
                        return@launch
                    }
                    Analytics.trackLoginFailed(creds.userId, "UAAP 登录失败")
                    _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
                    return@launch
                }

                connection = conn
                initServices(conn)
                wireSessionExpiredHandler(conn)
                startHeartbeat()

                // 恢复 session 凭证
                credentialStore.save(creds)

                _uiState.value = AuthUiState(state = AuthState.Authenticated, userId = creds.userId)
                Analytics.trackLoginSuccess(creds.userId)
                Log.i(TAG, "✅ Session restored: ${creds.userId}")
            } catch (e: Exception) {
                Log.e(TAG, "Session restore failed", e)
                Analytics.trackLoginFailed(creds.userId, "会话恢复失败")
                _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
            }
        }
    }

    // ==================== Logout ====================

    fun logout() {
        stopHeartbeat()
        captchaSession = null
        viewModelScope.launch {
            connection?.close()
            clearServices()
            credentialStore.clear() // 只清 session 凭证，保留 remembered 用于快速登录
            Analytics.clearUser()
            _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
            Log.i(TAG, "👋 Logged out")
        }
    }

    // ==================== Password Verification (for YKT) ====================

    fun verifyPassword(input: String): Boolean {
        val creds = credentialStore.load() ?: return false
        return input == creds.password || input == creds.ecPassword
    }

    fun getRememberedCredentials(): UserCredentials? = credentialStore.loadRemembered()

    /** 用户确认改密提示：仅关闭弹窗标记，保留错误状态与本地凭据 */
    fun dismissPasswordChange() {
        _uiState.value = _uiState.value.copy(passwordChangeRequired = false)
    }

    fun clearSavedCredentials() {
        credentialStore.clear()
        credentialStore.clearRemembered()
        Analytics.clearUser()
    }

    // ==================== Heartbeat Keepalive ====================

    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatJob = viewModelScope.launch(Dispatchers.IO) {
            Log.i(TAG, "💓 Heartbeat started (interval: ${HEARTBEAT_INTERVAL_MS / 1000}s)")
            while (isActive) {
                delay(HEARTBEAT_INTERVAL_MS)
                val conn = connection ?: break
                val alive = conn.heartbeat()
                if (!alive && !isReconnecting) {
                    Log.w(TAG, "💓 Heartbeat detected session expired, reconnecting...")
                    handleSessionExpired()
                }
            }
        }
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    // ==================== Session Expired Handler ====================

    private fun wireSessionExpiredHandler(conn: AUFEConnection) {
        conn.setOnSessionExpired {
            if (!isReconnecting) {
                Log.w(TAG, "⚠️ HttpClient detected session expired")
                viewModelScope.launch { handleSessionExpired() }
            }
        }
    }

    private suspend fun handleSessionExpired() {
        if (isReconnecting) return
        isReconnecting = true
        Analytics.trackSessionExpired("session_expired")
        try {
            val conn = connection ?: return
            Log.i(TAG, "🔄 Auto-reconnecting...")
            val success = conn.reconnect()
            if (success) {
                // Re-wire callback (new clients after reconnect)
                wireSessionExpiredHandler(conn)
                // Re-init services with refreshed connection
                initServices(conn)
                Analytics.trackSessionReconnectSuccess()
                Log.i(TAG, "✅ Auto-reconnect succeeded")
            } else if (conn.lastUaapPasswordChangeRequired) {
                // 学校强制改密：停止重连（再连也会被拦截），不清凭据，把状态抛给 UI
                Log.w(TAG, "🏫 Password change required, stop reconnecting")
                Analytics.trackSessionReconnectFailed()
                stopHeartbeat()
                runCatching { conn.close() }
                clearServices()
                _uiState.value = AuthUiState(state = AuthState.Error, passwordChangeRequired = true)
            } else if (conn.lastEcCaptchaRequired) {
                // 自动重连无法人工输入验证码：停止重连，保留凭据（供登录页预填），回到登录页提示
                Log.w(TAG, "🔐 Captcha required, stop reconnecting")
                Analytics.trackSessionReconnectFailed()
                stopHeartbeat()
                runCatching { conn.close() }
                clearServices()
                _uiState.value = AuthUiState(state = AuthState.Unauthenticated, errorMessage = CAPTCHA_RELOGIN_MESSAGE)
            } else {
                Log.e(TAG, "❌ Auto-reconnect failed, user needs to re-login")
                Analytics.trackSessionReconnectFailed()
                stopHeartbeat()
                _uiState.value = AuthUiState(
                    state = AuthState.Error,
                    errorMessage = "会话已过期，请重新登录"
                )
            }
        } finally {
            isReconnecting = false
        }
    }

    // ==================== Service Management ====================

    private fun initServices(conn: AUFEConnection) {
        jwcService = JWCService(conn)
        yktService = YKTService(conn)
        isimService = ISIMService(conn)
        aacService = AACService(conn)
        laborClubService = LaborClubService(conn)
        competitionService = CompetitionService(conn)
        studentScheduleService = StudentScheduleService(conn)
        courseScheduleService = CourseScheduleService(conn)
        planService = PlanService(conn)
        repairService = RepairService(conn)
        teacherEvaluationService = TeacherEvaluationService(conn)
    }

    private fun clearServices() {
        connection = null
        jwcService = null
        yktService = null
        isimService = null
        aacService = null
        laborClubService = null
        competitionService = null
        studentScheduleService = null
        courseScheduleService = null
        planService = null
        repairService = null
        teacherEvaluationService = null
    }

    override fun onCleared() {
        super.onCleared()
        stopHeartbeat()
        viewModelScope.launch { connection?.close() }
    }

    companion object {
        private const val TAG = "AuthViewModel"
        private const val HEARTBEAT_INTERVAL_MS = 4 * 60 * 1000L // 4 minutes
        private const val LOGIN_PREFS_NAME = "login_throttle"
        private const val CAPTCHA_REQUIRED_MESSAGE = "学校要求输入验证码"
        private const val CAPTCHA_RELOGIN_MESSAGE = "学校要求输入验证码，请重新登录"
    }
}
