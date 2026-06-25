package tech.loveace.appv3.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 用户手动添加的俱乐部信息
 *
 * 与服务器返回的 [LaborClubInfo] 共用 clubId 作为唯一标识，
 * 通过 [source] 区分数据来源，通过 [status] 管理显隐状态。
 */
@Serializable
data class UserClub(
    @SerialName("clubId")
    val clubId: String,

    @SerialName("name")
    val name: String,

    @SerialName("typeName")
    val typeName: String? = null,

    @SerialName("source")
    val source: ClubSource = ClubSource.MANUAL,

    @SerialName("status")
    val status: ClubStatus = ClubStatus.ACTIVE,

    @SerialName("createdAt")
    val createdAt: Long = System.currentTimeMillis(),

    @SerialName("note")
    val note: String? = null
) {
    companion object {
        fun toLaborClubInfo(userClub: UserClub): LaborClubInfo =
            LaborClubInfo(
                id = userClub.clubId,
                name = userClub.name,
                typeName = userClub.typeName,
                ico = null,
                chairmanName = null,
                memberNum = 0
            )
    }
}

@Serializable
enum class ClubSource {
    @SerialName("server")
    SERVER,

    @SerialName("manual")
    MANUAL
}

@Serializable
enum class ClubStatus {
    @SerialName("active")
    ACTIVE,

    @SerialName("hidden")
    HIDDEN
}
