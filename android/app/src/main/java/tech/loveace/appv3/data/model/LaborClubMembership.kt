package tech.loveace.appv3.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

@Serializable
data class LaborClubDirectoryItem(
    @SerialName("ID") val id: String = "",
    @SerialName("Name") val name: String = "",
    @SerialName("TypeID") val typeId: String = "",
    @SerialName("ProjectID") val projectId: String = "",
    @SerialName("PeopleNum") val peopleNum: Int = 0,
    @SerialName("MemberNum") val memberNum: Int = 0,
    @SerialName("PorjectName") val projectName: String = "",
    @SerialName("TypeName") val typeName: String = "",
    @SerialName("Ico") val iconUrl: String? = null,
    @SerialName("Desc") val description: String? = null,
    @SerialName("IsEnable") val isEnabled: Boolean = false,
    @SerialName("IsJoin") val isJoined: Boolean = false,
) {
    val canApply: Boolean get() = isEnabled && !isJoined
}

data class LaborClubApplication(
    val id: String = "",
    val clubId: String = "",
    val clubName: String = "",
    val reason: String = "",
    val addTime: String = "",
    val replyComment: String = "",
    val isAgree: Boolean? = null,
    val statusText: String = "",
) {
    val reviewStatus: LaborClubApplicationReviewStatus
        get() {
            val normalizedStatus = statusText.trim().lowercase()
            if (REJECTED_STATUS_WORDS.any(normalizedStatus::contains)) {
                return LaborClubApplicationReviewStatus.REJECTED
            }
            return when (isAgree) {
                true -> LaborClubApplicationReviewStatus.APPROVED
                false -> LaborClubApplicationReviewStatus.REJECTED
                null -> LaborClubApplicationReviewStatus.PENDING
            }
        }

    private companion object {
        val REJECTED_STATUS_WORDS = listOf("拒绝", "驳回", "未通过", "失效", "过期", "invalid", "expired")
    }
}

enum class LaborClubApplicationReviewStatus {
    PENDING,
    APPROVED,
    REJECTED,
}

enum class LaborClubMembershipStatus {
    JOINED,
    PENDING,
    APPROVED_SYNCING,
    NOT_JOINED,
    REJECTED,
    SUBMITTING,
}

data class LaborClubMembershipState(
    val status: LaborClubMembershipStatus = LaborClubMembershipStatus.NOT_JOINED,
    val latestApplication: LaborClubApplication? = null,
)

data class LaborClubSubmissionResolution(
    val membership: LaborClubMembershipState,
    val isStatusSyncing: Boolean,
)

fun resolveLaborClubMembership(
    joinedClubs: List<LaborClubInfo>,
    latestApplication: LaborClubApplication?,
    isSubmitting: Boolean = false,
): LaborClubMembershipState {
    if (joinedClubs.isNotEmpty()) {
        return LaborClubMembershipState(LaborClubMembershipStatus.JOINED, latestApplication)
    }
    if (isSubmitting) {
        return LaborClubMembershipState(LaborClubMembershipStatus.SUBMITTING, latestApplication)
    }
    val status = when (latestApplication?.reviewStatus) {
        LaborClubApplicationReviewStatus.PENDING -> LaborClubMembershipStatus.PENDING
        LaborClubApplicationReviewStatus.APPROVED -> LaborClubMembershipStatus.APPROVED_SYNCING
        LaborClubApplicationReviewStatus.REJECTED -> LaborClubMembershipStatus.REJECTED
        null -> LaborClubMembershipStatus.NOT_JOINED
    }
    return LaborClubMembershipState(status, latestApplication)
}

fun resolveLaborClubSubmission(
    joinedClubs: List<LaborClubInfo>,
    latestApplication: LaborClubApplication?,
    expectedClubId: String,
    previousApplication: LaborClubApplication? = null,
): LaborClubSubmissionResolution {
    val normalizedClubId = expectedClubId.trim()
    val confirmedApplication = latestApplication
        ?.takeIf { it.clubId.trim().equals(normalizedClubId, ignoreCase = true) }
        ?.takeUnless { previousApplication != null && sameApplicationRecord(it, previousApplication) }
    if (joinedClubs.isNotEmpty()) {
        return LaborClubSubmissionResolution(
            membership = resolveLaborClubMembership(joinedClubs, confirmedApplication),
            isStatusSyncing = false,
        )
    }
    if (confirmedApplication == null) {
        return LaborClubSubmissionResolution(
            membership = LaborClubMembershipState(LaborClubMembershipStatus.PENDING),
            isStatusSyncing = true,
        )
    }
    return LaborClubSubmissionResolution(
        membership = resolveLaborClubMembership(emptyList(), confirmedApplication),
        isStatusSyncing = false,
    )
}

private fun sameApplicationRecord(
    current: LaborClubApplication,
    previous: LaborClubApplication,
): Boolean {
    val currentId = current.id.trim()
    val previousId = previous.id.trim()
    if (currentId.isNotEmpty() && previousId.isNotEmpty()) {
        return currentId.equals(previousId, ignoreCase = true)
    }
    return current.clubId.trim().equals(previous.clubId.trim(), ignoreCase = true) &&
        current.addTime.trim() == previous.addTime.trim() &&
        current.reason.trim() == previous.reason.trim()
}

fun latestLaborClubApplication(applications: List<LaborClubApplication>): LaborClubApplication? =
    applications.maxByOrNull { applicationTimeKey(it.addTime) }

fun decodeLaborClubApplication(element: JsonElement): LaborClubApplication {
    val obj = element as? JsonObject ?: return LaborClubApplication()
    return LaborClubApplication(
        id = obj.stringValue("ID", "Id", "id"),
        clubId = obj.stringValue("ClubID", "ClubId", "clubID", "clubId"),
        clubName = obj.stringValue("ClubName", "Name"),
        reason = obj.stringValue("Reason"),
        addTime = obj.stringValue("AddTime"),
        replyComment = obj.stringValue("ReplyComment", "ExamComment", "Reply"),
        isAgree = obj.flexibleBoolean("IsAgree"),
        statusText = obj.stringValue("StateName", "StatusName", "ApplyStateName"),
    )
}

private fun applicationTimeKey(value: String): String {
    val digits = value.filter(Char::isDigit)
    return digits.padEnd(20, '0').take(20)
}

private fun JsonObject.stringValue(vararg keys: String): String = keys.firstNotNullOfOrNull { key ->
    this[key]?.jsonPrimitive?.contentOrNull
}?.trim().orEmpty()

private fun JsonObject.flexibleBoolean(key: String): Boolean? {
    val element = this[key] ?: return null
    if (element is JsonNull) return null
    val primitive = element.jsonPrimitive
    primitive.booleanOrNull?.let { return it }
    primitive.intOrNull?.let { return it != 0 }
    return when (primitive.contentOrNull?.trim()?.lowercase()) {
        "true", "1", "yes", "approved", "agree", "通过", "同意" -> true
        "false", "0", "no", "rejected", "refused", "拒绝", "驳回", "未通过", "失效" -> false
        else -> null
    }
}
