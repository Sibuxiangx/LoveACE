package tech.loveace.appv3.ui.viewmodel

import android.app.Application
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
import tech.loveace.appv3.data.model.UserCredentials
import tech.loveace.appv3.data.network.AUFEConnection
import tech.loveace.appv3.data.service.*

enum class AuthState { Initial, Loading, Authenticated, Unauthenticated, Error }

data class AuthUiState(
    val state: AuthState = AuthState.Initial,
    val errorMessage: String? = null,
    val userId: String = "",
    val serviceGeneration: Long = 0,
)

/**
 * 认证 ViewModel
 * - 管理登录状态和所有服务实例
 * - 心跳保活：每 4 分钟 ping VPN，防止 session 过期
 * - Session 过期检测：HttpClient 嗅探到 VPN 登录页时自动重连
 */
class AuthViewModel(application: Application) : AndroidViewModel(application) {

    private val credentialStore = CredentialStore(application)

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    private var heartbeatJob: Job? = null
    private var isReconnecting = false
    private var serviceGeneration = 0L

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

    fun login(userId: String, ecPassword: String, password: String) {
        viewModelScope.launch {
            _uiState.value = AuthUiState(state = AuthState.Loading)
            try {
                val conn = AUFEConnection(userId, ecPassword, password)
                conn.startClient()

                // EC (VPN) login
                val ecResult = conn.ecLogin()
                if (!ecResult.success) {
                    val msg = when {
                        ecResult.failInvalidCredentials -> "VPN 账号或密码错误"
                        ecResult.failMaybeAttacked -> "登录过于频繁，请稍后再试"
                        ecResult.failNetworkError -> "网络连接失败"
                        else -> "VPN 登录失败"
                    }
                    Analytics.trackLoginFailed(userId, msg)
                    _uiState.value = AuthUiState(state = AuthState.Error, errorMessage = msg)
                    return@launch
                }

                // UAAP (CAS) login
                val uaapResult = conn.uaapLogin()
                if (!uaapResult.success) {
                    val msg = when {
                        uaapResult.failInvalidCredentials -> "教务系统密码错误"
                        uaapResult.failNetworkError -> "网络连接失败"
                        else -> "UAAP 登录失败"
                    }
                    Analytics.trackLoginFailed(userId, msg)
                    _uiState.value = AuthUiState(state = AuthState.Error, errorMessage = msg)
                    return@launch
                }

                connection = conn
                initServices(conn)
                wireSessionExpiredHandler(conn)
                startHeartbeat()

                // 始终保存凭证（用于会话恢复和快速登录）
                credentialStore.save(UserCredentials(userId, ecPassword, password))
                credentialStore.saveRemembered(UserCredentials(userId, ecPassword, password))

                _uiState.value = AuthUiState(
                    state = AuthState.Authenticated,
                    userId = userId,
                    serviceGeneration = serviceGeneration,
                )
                Analytics.trackLoginSuccess(userId)
                Log.i(TAG, "✅ Login successful: $userId")
            } catch (e: Exception) {
                Log.e(TAG, "Login error", e)
                Analytics.trackLoginFailed(userId, "登录异常")
                _uiState.value = AuthUiState(state = AuthState.Error, errorMessage = "登录异常: ${e.message}")
            }
        }
    }

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
                    Analytics.trackLoginFailed(creds.userId, "VPN 登录失败")
                    _uiState.value = AuthUiState(state = AuthState.Unauthenticated)
                    return@launch
                }

                val uaapResult = conn.uaapLogin()
                if (!uaapResult.success) {
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

                _uiState.value = AuthUiState(
                    state = AuthState.Authenticated,
                    userId = creds.userId,
                    serviceGeneration = serviceGeneration,
                )
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
                _uiState.value = _uiState.value.copy(serviceGeneration = serviceGeneration)
                Analytics.trackSessionReconnectSuccess()
                Log.i(TAG, "✅ Auto-reconnect succeeded")
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
        serviceGeneration++
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
    }
}
