package tech.loveace.appv3.ui.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.local.UserClubStore
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.service.LaborClubService
import java.time.LocalDateTime

data class LaborClubUiState(
    val isLoading: Boolean = false,
    val progress: LaborClubProgressInfo? = null,
    val joinedActivities: List<LaborClubActivity> = emptyList(),
    val allActivities: List<LaborClubActivity> = emptyList(),
    val clubs: List<LaborClubInfo> = emptyList(),
    val signInResult: SignInResponse? = null,
    val applyResult: String? = null,
    val error: String? = null,
    val activityDetail: ActivityDetail? = null,
    val addClubResult: String? = null,
    val detailLoading: Boolean = false,
    // 预计算的分类列表，避免每次 UI 读取时重复解析时间
    val ongoingActivities: List<LaborClubActivity> = emptyList(),
    val finishedActivities: List<LaborClubActivity> = emptyList(),
    val availableActivities: List<LaborClubActivity> = emptyList(),
    val fullActivities: List<LaborClubActivity> = emptyList(),
    val notStartedActivities: List<LaborClubActivity> = emptyList(),
    val expiredActivities: List<LaborClubActivity> = emptyList(),
) {
    /** 添加活动 tab 的总数 */
    val addActivitiesTotalCount get() = availableActivities.size + fullActivities.size + notStartedActivities.size + expiredActivities.size

    fun isActivityJoined(activityId: String) = joinedActivities.any { it.id == activityId }

    companion object {
        /** 根据原始数据计算分类列表，仅在数据变化时调用一次 */
        fun computeCategories(
            joinedActivities: List<LaborClubActivity>,
            allActivities: List<LaborClubActivity>,
        ): CategorizedActivities {
            val now = LocalDateTime.now()
            val joinedIds = joinedActivities.map { it.id }.toSet()

            val ongoing = mutableListOf<LaborClubActivity>()
            val finished = mutableListOf<LaborClubActivity>()
            for (a in joinedActivities) {
                try {
                    val start = LocalDateTime.parse(a.startTime.replace(" ", "T"))
                    if (start.isAfter(now)) ongoing.add(a) else finished.add(a)
                } catch (_: Exception) { finished.add(a) }
            }

            val available = mutableListOf<LaborClubActivity>()
            val full = mutableListOf<LaborClubActivity>()
            val notStarted = mutableListOf<LaborClubActivity>()
            val expired = mutableListOf<LaborClubActivity>()
            for (a in allActivities) {
                if (joinedIds.contains(a.id)) continue
                try {
                    val signStart = LocalDateTime.parse(a.signUpStartTime.replace(" ", "T"))
                    val signEnd = LocalDateTime.parse(a.signUpEndTime.replace(" ", "T"))
                    val start = LocalDateTime.parse(a.startTime.replace(" ", "T"))
                    when {
                        signStart.isAfter(now) -> notStarted.add(a)
                        signEnd.isBefore(now) && start.isBefore(now) -> expired.add(a)
                        signStart.isBefore(now) && signEnd.isAfter(now) && start.isAfter(now) -> {
                            if (a.memberNum >= a.peopleNum) full.add(a) else available.add(a)
                        }
                        else -> expired.add(a)
                    }
                } catch (_: Exception) { expired.add(a) }
            }
            notStarted.sortBy {
                try { LocalDateTime.parse(it.signUpStartTime.replace(" ", "T")) } catch (_: Exception) { LocalDateTime.MAX }
            }
            return CategorizedActivities(ongoing, finished, available, full, notStarted, expired)
        }
    }
}

data class CategorizedActivities(
    val ongoing: List<LaborClubActivity>,
    val finished: List<LaborClubActivity>,
    val available: List<LaborClubActivity>,
    val full: List<LaborClubActivity>,
    val notStarted: List<LaborClubActivity>,
    val expired: List<LaborClubActivity>,
)

class LaborClubViewModel : ViewModel() {
    private var service: LaborClubService? = null
    private val _uiState = MutableStateFlow(LaborClubUiState())
    val uiState: StateFlow<LaborClubUiState> = _uiState.asStateFlow()

    fun init(service: LaborClubService) { this.service = service }

    fun loadAll() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                // 并发获取进度、已加入活动、服务器俱乐部列表、本地手动俱乐部
                val progressDef = async { svc.getProgress() }
                val joinedDef = async { svc.getJoinedActivities() }
                val clubsDef = async { svc.getJoinedClubs() }
                val manualDef = async { UserClubStore.getAll() }

                val progressResult = progressDef.await()
                val joinedResult = joinedDef.await()
                val clubsResult = clubsDef.await()
                val manualClubs = manualDef.await()

                val joinedActivities = joinedResult.data ?: emptyList()
                val serverClubs = clubsResult.data ?: emptyList()

                // 合并服务器俱乐部和手动添加的俱乐部
                val mergedClubs = mergeClubs(serverClubs, manualClubs)

                // 并发获取每个已加入活动的签到列表
                if (joinedActivities.isNotEmpty()) {
                    val signJobs = joinedActivities.map { activity ->
                        async {
                            try {
                                val signResult = svc.getSignList(activity.id)
                                if (signResult.success) activity.signList = signResult.data
                            } catch (e: Exception) { Log.w("LaborClubVM", "getSignList ${activity.id}", e) }
                        }
                    }
                    signJobs.awaitAll()
                }

                // 获取所有俱乐部（包括手动添加的）的活动列表
                val allActivities = mutableListOf<LaborClubActivity>()
                for (club in mergedClubs) {
                    val clubActivitiesResult = svc.getClubActivities(club.id)
                    if (clubActivitiesResult.success) {
                        allActivities.addAll(clubActivitiesResult.data ?: emptyList())
                    }
                }

                _uiState.value = run {
                    val cats = LaborClubUiState.computeCategories(joinedActivities, allActivities)
                    _uiState.value.copy(
                        isLoading = false,
                        progress = progressResult.data,
                        joinedActivities = joinedActivities,
                        allActivities = allActivities,
                        clubs = mergedClubs,
                        error = progressResult.error ?: joinedResult.error,
                        ongoingActivities = cats.ongoing,
                        finishedActivities = cats.finished,
                        availableActivities = cats.available,
                        fullActivities = cats.full,
                        notStartedActivities = cats.notStarted,
                        expiredActivities = cats.expired,
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    /** 合并服务器俱乐部和手动添加的俱乐部，以服务器为准去重 */
    private fun mergeClubs(
        server: List<LaborClubInfo>,
        manual: List<tech.loveace.appv3.data.model.UserClub>
    ): List<LaborClubInfo> {
        val serverIds = server.map { it.id }.toSet()
        val manualAsInfo = manual
            .filter { !serverIds.contains(it.clubId) }
            .map { tech.loveace.appv3.data.model.UserClub.toLaborClubInfo(it) }
        return server + manualAsInfo
    }

    /** 添加手动俱乐部 */
    fun addClub(name: String, clubId: String, typeName: String?, note: String?) {
        val trimmedId = clubId.trim()
        val trimmedName = name.trim()
        if (trimmedId.isEmpty() || trimmedName.isEmpty()) {
            _uiState.value = _uiState.value.copy(addClubResult = "俱乐部名称和ID不能为空")
            return
        }
        val club = tech.loveace.appv3.data.model.UserClub(
            clubId = trimmedId,
            name = trimmedName,
            typeName = typeName?.trim()?.takeIf { it.isNotEmpty() },
            source = tech.loveace.appv3.data.model.ClubSource.MANUAL,
            status = tech.loveace.appv3.data.model.ClubStatus.ACTIVE,
            note = note?.trim()?.takeIf { it.isNotEmpty() }
        )
        val success = UserClubStore.addClub(club)
        _uiState.value = _uiState.value.copy(
            addClubResult = if (success) "添加成功" else "该俱乐部已存在"
        )
        if (success) loadAll()
    }

    /** 移除手动添加的俱乐部 */
    fun removeManualClub(clubId: String) {
        UserClubStore.removeClub(clubId)
        loadAll()
    }

    fun clearAddClubResult() { _uiState.value = _uiState.value.copy(addClubResult = null) }

    fun applyActivity(activityId: String) {
        val svc = service ?: return
        viewModelScope.launch {
            val result = svc.applyActivity(activityId)
            _uiState.value = _uiState.value.copy(applyResult = if (result.success) "报名成功" else (result.error ?: "报名失败"))
            if (result.success) loadAll() // 刷新数据
        }
    }

    fun clearApplyResult() { _uiState.value = _uiState.value.copy(applyResult = null) }

    fun scanSignIn(qrData: String) {
        val svc = service ?: return
        val baseLng = 117.424733; val baseLat = 32.905237; val jitter = 0.0001
        val lng = baseLng + (Math.random() * 2 - 1) * jitter
        val lat = baseLat + (Math.random() * 2 - 1) * jitter
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, signInResult = null)
            val result = svc.scanSignIn(qrData, "$lng,$lat")
            _uiState.value = _uiState.value.copy(isLoading = false, signInResult = result.data, error = result.error)
            if (result.data?.isSuccess == true) loadAll()
        }
    }

    fun clearSignInResult() { _uiState.value = _uiState.value.copy(signInResult = null) }

    fun loadActivityDetail(activityId: String) {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(detailLoading = true, activityDetail = null)
            try {
                val result = svc.getActivityDetail(activityId)
                _uiState.value = _uiState.value.copy(
                    detailLoading = false,
                    activityDetail = result.data,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(detailLoading = false)
                Log.w("LaborClubVM", "loadActivityDetail failed", e)
            }
        }
    }

    fun clearActivityDetail() {
        _uiState.value = _uiState.value.copy(activityDetail = null)
    }
}
