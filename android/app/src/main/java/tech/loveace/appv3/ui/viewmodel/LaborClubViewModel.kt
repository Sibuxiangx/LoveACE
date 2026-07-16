package tech.loveace.appv3.ui.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.service.LaborClubService
import java.time.LocalDateTime

data class LaborClubUiState(
    val isLoading: Boolean = false,
    val progress: LaborClubProgressInfo? = null,
    val joinedActivities: List<LaborClubActivity> = emptyList(),
    val allActivities: List<LaborClubActivity> = emptyList(),
    val clubs: List<LaborClubInfo> = emptyList(),
    val membership: LaborClubMembershipState = LaborClubMembershipState(),
    val clubStatusError: String? = null,
    val submittedStatusSyncing: Boolean = false,
    val clubDirectory: List<LaborClubDirectoryItem> = emptyList(),
    val isDirectoryLoading: Boolean = false,
    val directoryError: String? = null,
    val clubActionResult: String? = null,
    val clubSubmissionSucceeded: Boolean = false,
    val signInResult: SignInResponse? = null,
    val applyResult: String? = null,
    val error: String? = null,
    val activityDetail: ActivityDetail? = null,
    val detailLoading: Boolean = false,
    val ongoingActivities: List<LaborClubActivity> = emptyList(),
    val finishedActivities: List<LaborClubActivity> = emptyList(),
    val availableActivities: List<LaborClubActivity> = emptyList(),
    val fullActivities: List<LaborClubActivity> = emptyList(),
    val notStartedActivities: List<LaborClubActivity> = emptyList(),
    val expiredActivities: List<LaborClubActivity> = emptyList(),
) {
    val addActivitiesTotalCount get() = availableActivities.size + fullActivities.size + notStartedActivities.size + expiredActivities.size
    val isSubmittingClub get() = membership.status == LaborClubMembershipStatus.SUBMITTING

    fun isActivityJoined(activityId: String) = joinedActivities.any { it.id == activityId }

    companion object {
        fun computeCategories(
            joinedActivities: List<LaborClubActivity>,
            allActivities: List<LaborClubActivity>,
        ): CategorizedActivities {
            val now = LocalDateTime.now()
            val joinedIds = joinedActivities.map { it.id }.toSet()

            val ongoing = mutableListOf<LaborClubActivity>()
            val finished = mutableListOf<LaborClubActivity>()
            for (activity in joinedActivities) {
                try {
                    val start = LocalDateTime.parse(activity.startTime.replace(" ", "T"))
                    if (start.isAfter(now)) ongoing.add(activity) else finished.add(activity)
                } catch (_: Exception) {
                    finished.add(activity)
                }
            }

            val available = mutableListOf<LaborClubActivity>()
            val full = mutableListOf<LaborClubActivity>()
            val notStarted = mutableListOf<LaborClubActivity>()
            val expired = mutableListOf<LaborClubActivity>()
            for (activity in allActivities) {
                if (joinedIds.contains(activity.id)) continue
                try {
                    val signStart = LocalDateTime.parse(activity.signUpStartTime.replace(" ", "T"))
                    val signEnd = LocalDateTime.parse(activity.signUpEndTime.replace(" ", "T"))
                    val start = LocalDateTime.parse(activity.startTime.replace(" ", "T"))
                    when {
                        signStart.isAfter(now) -> notStarted.add(activity)
                        signEnd.isBefore(now) && start.isBefore(now) -> expired.add(activity)
                        signStart.isBefore(now) && signEnd.isAfter(now) && start.isAfter(now) -> {
                            if (activity.memberNum >= activity.peopleNum) full.add(activity) else available.add(activity)
                        }
                        else -> expired.add(activity)
                    }
                } catch (_: Exception) {
                    expired.add(activity)
                }
            }
            notStarted.sortBy {
                try {
                    LocalDateTime.parse(it.signUpStartTime.replace(" ", "T"))
                } catch (_: Exception) {
                    LocalDateTime.MAX
                }
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

private data class PendingClubSubmission(
    val clubId: String,
    val previousApplication: LaborClubApplication?,
)

class LaborClubViewModel : ViewModel() {
    private var service: LaborClubService? = null
    private var activeUserId = ""
    private var loadJob: Job? = null
    private var directoryJob: Job? = null
    private var clubApplyJob: Job? = null
    private var pendingClubSubmission: PendingClubSubmission? = null
    private val _uiState = MutableStateFlow(LaborClubUiState())
    val uiState: StateFlow<LaborClubUiState> = _uiState.asStateFlow()

    fun init(service: LaborClubService, userId: String) {
        val normalizedUserId = userId.trim()
        val userChanged = activeUserId != normalizedUserId
        val serviceChanged = this.service !== service
        if (userChanged || serviceChanged) {
            val retainedSubmission = pendingClubSubmission.takeUnless { userChanged }
            loadJob?.cancel()
            directoryJob?.cancel()
            clubApplyJob?.cancel()
            activeUserId = normalizedUserId
            pendingClubSubmission = retainedSubmission
            _uiState.value = LaborClubUiState()
        }
        this.service = service
    }

    fun loadAll() {
        val svc = service ?: return
        val userId = activeUserId.takeIf(String::isNotEmpty) ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                error = null,
                clubStatusError = null,
            )
            try {
                val progressDeferred = async { svc.getProgress() }
                val joinedDeferred = async { svc.getJoinedActivities() }
                val clubsDeferred = async { svc.getJoinedClubs() }

                val progressResult = progressDeferred.await()
                val joinedResult = joinedDeferred.await()
                val clubsResult = clubsDeferred.await()
                if (!isCurrentUser(userId)) return@launch

                val joinedActivities = joinedResult.data.orEmpty()
                var clubs = clubsResult.data.orEmpty()
                var latestApplication: LaborClubApplication? = null
                var clubStatusError = clubsResult.error
                var applicationStatusLoaded = false

                if (clubsResult.success && clubs.isEmpty()) {
                    val applicationResult = svc.getLatestClubApplication()
                    if (!isCurrentUser(userId)) return@launch
                    if (applicationResult.success) {
                        applicationStatusLoaded = true
                        latestApplication = applicationResult.data
                        if (latestApplication?.reviewStatus == LaborClubApplicationReviewStatus.APPROVED) {
                            val refreshedClubs = svc.getJoinedClubs()
                            if (!isCurrentUser(userId)) return@launch
                            if (refreshedClubs.success && !refreshedClubs.data.isNullOrEmpty()) {
                                clubs = refreshedClubs.data.orEmpty()
                            } else if (!refreshedClubs.success) {
                                clubStatusError = refreshedClubs.error
                            }
                        }
                    } else {
                        clubStatusError = applicationResult.error
                    }
                }

                if (joinedActivities.isNotEmpty()) {
                    joinedActivities.map { activity ->
                        async {
                            try {
                                val signResult = svc.getSignList(activity.id)
                                if (signResult.success) activity.signList = signResult.data
                            } catch (e: Exception) {
                                Log.w(TAG, "getSignList ${activity.id}", e)
                            }
                        }
                    }.awaitAll()
                }

                val activityGroups = clubs.map { club ->
                    async {
                        if (!isCurrentUser(userId)) return@async emptyList()
                        val result = svc.getClubActivities(club.id)
                        if (result.success) result.data.orEmpty() else emptyList()
                    }
                }.awaitAll()
                if (!isCurrentUser(userId)) return@launch
                val allActivities = activityGroups.flatten().distinctBy { it.id.trim().lowercase() }
                val categories = LaborClubUiState.computeCategories(joinedActivities, allActivities)
                val pendingSubmission = pendingClubSubmission
                val (membership, statusSyncing) = when {
                    clubs.isNotEmpty() -> {
                        pendingClubSubmission = null
                        resolveLaborClubMembership(clubs, latestApplication) to false
                    }
                    pendingSubmission != null && applicationStatusLoaded -> {
                        val resolution = resolveLaborClubSubmission(
                            joinedClubs = clubs,
                            latestApplication = latestApplication,
                            expectedClubId = pendingSubmission.clubId,
                            previousApplication = pendingSubmission.previousApplication,
                        )
                        if (!resolution.isStatusSyncing) pendingClubSubmission = null
                        resolution.membership to resolution.isStatusSyncing
                    }
                    pendingSubmission != null ->
                        LaborClubMembershipState(LaborClubMembershipStatus.PENDING) to true
                    else -> resolveLaborClubMembership(clubs, latestApplication) to false
                }

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    progress = progressResult.data,
                    joinedActivities = joinedActivities,
                    allActivities = allActivities,
                    clubs = clubs,
                    membership = membership,
                    clubStatusError = clubStatusError,
                    submittedStatusSyncing = statusSyncing,
                    error = progressResult.error ?: joinedResult.error,
                    ongoingActivities = categories.ongoing,
                    finishedActivities = categories.finished,
                    availableActivities = categories.available,
                    fullActivities = categories.full,
                    notStartedActivities = categories.notStarted,
                    expiredActivities = categories.expired,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (isCurrentUser(userId)) {
                    _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
                }
            }
        }
    }

    fun loadClubDirectory(force: Boolean = false) {
        val svc = service ?: return
        val userId = activeUserId.takeIf(String::isNotEmpty) ?: return
        if (!force && (_uiState.value.clubDirectory.isNotEmpty() || _uiState.value.isDirectoryLoading)) return
        directoryJob?.cancel()
        directoryJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isDirectoryLoading = true, directoryError = null)
            val result = svc.getClubDirectory()
            if (!isCurrentUser(userId)) return@launch
            _uiState.value = _uiState.value.copy(
                isDirectoryLoading = false,
                clubDirectory = result.data.orEmpty(),
                directoryError = result.error,
            )
        }
    }

    fun applyClub(clubId: String, reason: String) {
        val svc = service ?: return
        val userId = activeUserId.takeIf(String::isNotEmpty) ?: return
        if (_uiState.value.isSubmittingClub) return
        val club = _uiState.value.clubDirectory.firstOrNull { it.id.equals(clubId, ignoreCase = true) }
        if (club == null || !club.canApply) {
            _uiState.value = _uiState.value.copy(clubActionResult = "当前俱乐部不可申请")
            return
        }
        val normalizedReason = reason.trim()
        if (normalizedReason.isEmpty()) {
            _uiState.value = _uiState.value.copy(clubActionResult = "请填写申请理由")
            return
        }

        clubApplyJob?.cancel()
        clubApplyJob = viewModelScope.launch {
            val previousMembership = _uiState.value.membership
            _uiState.value = _uiState.value.copy(
                membership = resolveLaborClubMembership(
                    joinedClubs = _uiState.value.clubs,
                    latestApplication = previousMembership.latestApplication,
                    isSubmitting = true,
                ),
                clubActionResult = null,
                clubSubmissionSucceeded = false,
                submittedStatusSyncing = false,
            )

            val submitResult = svc.applyClub(club.id, normalizedReason)
            if (!isCurrentUser(userId)) return@launch
            if (!submitResult.success) {
                _uiState.value = _uiState.value.copy(
                    membership = previousMembership,
                    clubActionResult = submitResult.error ?: "申请提交失败",
                )
                return@launch
            }

            val applicationDeferred = async { svc.getLatestClubApplication() }
            val refreshedClubsDeferred = async { svc.getJoinedClubs() }
            val applicationResult = applicationDeferred.await()
            val refreshedClubsResult = refreshedClubsDeferred.await()
            if (!isCurrentUser(userId)) return@launch
            val refreshedClubs = if (refreshedClubsResult.success) {
                refreshedClubsResult.data.orEmpty()
            } else {
                _uiState.value.clubs
            }
            val latest = applicationResult.data.takeIf { applicationResult.success }
            val resolution = resolveLaborClubSubmission(
                joinedClubs = refreshedClubs,
                latestApplication = latest,
                expectedClubId = club.id,
                previousApplication = previousMembership.latestApplication,
            )
            pendingClubSubmission = if (resolution.isStatusSyncing) {
                PendingClubSubmission(club.id, previousMembership.latestApplication)
            } else {
                null
            }
            val message = if (resolution.isStatusSyncing) {
                "申请已提交，状态同步中"
            } else {
                when (resolution.membership.status) {
                    LaborClubMembershipStatus.PENDING -> "申请已提交，等待审批"
                    LaborClubMembershipStatus.APPROVED_SYNCING -> "审核已通过，正在同步俱乐部信息"
                    LaborClubMembershipStatus.JOINED -> "申请已通过，俱乐部信息已同步"
                    LaborClubMembershipStatus.REJECTED ->
                        resolution.membership.latestApplication?.replyComment?.ifBlank { "申请状态已更新" }
                            ?: "申请状态已更新"
                    else -> "申请状态已更新"
                }
            }
            _uiState.value = _uiState.value.copy(
                clubs = refreshedClubs,
                membership = resolution.membership,
                submittedStatusSyncing = resolution.isStatusSyncing,
                clubActionResult = message,
                clubSubmissionSucceeded = true,
            )
            if (resolution.membership.status == LaborClubMembershipStatus.JOINED) loadAll()
        }
    }

    fun consumeClubSubmissionSuccess() {
        _uiState.value = _uiState.value.copy(clubSubmissionSucceeded = false)
    }

    fun clearClubActionResult() {
        _uiState.value = _uiState.value.copy(clubActionResult = null)
    }

    fun applyActivity(activityId: String) {
        val svc = service ?: return
        viewModelScope.launch {
            val result = svc.applyActivity(activityId)
            _uiState.value = _uiState.value.copy(
                applyResult = if (result.success) "报名成功" else (result.error ?: "报名失败"),
            )
            if (result.success) loadAll()
        }
    }

    fun clearApplyResult() {
        _uiState.value = _uiState.value.copy(applyResult = null)
    }

    fun scanSignIn(qrData: String) {
        val svc = service ?: return
        val baseLng = 117.424733
        val baseLat = 32.905237
        val jitter = 0.0001
        val lng = baseLng + (Math.random() * 2 - 1) * jitter
        val lat = baseLat + (Math.random() * 2 - 1) * jitter
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, signInResult = null)
            val result = svc.scanSignIn(qrData, "$lng,$lat")
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                signInResult = result.data,
                error = result.error,
            )
            if (result.data?.isSuccess == true) loadAll()
        }
    }

    fun clearSignInResult() {
        _uiState.value = _uiState.value.copy(signInResult = null)
    }

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
                Log.w(TAG, "loadActivityDetail failed", e)
            }
        }
    }

    fun clearActivityDetail() {
        _uiState.value = _uiState.value.copy(activityDetail = null)
    }

    private fun isCurrentUser(userId: String): Boolean = activeUserId == userId

    private companion object {
        const val TAG = "LaborClubVM"
    }
}
