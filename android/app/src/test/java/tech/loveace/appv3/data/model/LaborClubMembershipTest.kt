package tech.loveace.appv3.data.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private val tolerantJson = Json { ignoreUnknownKeys = true }

class LaborClubMembershipTest {
    @Test
    fun `joined clubs always take priority over old applications`() {
        val state = resolveLaborClubMembership(
            joinedClubs = listOf(LaborClubInfo(id = "club-1")),
            latestApplication = LaborClubApplication(isAgree = false),
        )

        assertEquals(LaborClubMembershipStatus.JOINED, state.status)
    }

    @Test
    fun `submission refresh gives joined clubs priority before application sync`() {
        val resolution = resolveLaborClubSubmission(
            joinedClubs = listOf(LaborClubInfo(id = "club-1")),
            latestApplication = null,
            expectedClubId = "club-1",
        )

        assertEquals(LaborClubMembershipStatus.JOINED, resolution.membership.status)
        assertFalse(resolution.isStatusSyncing)
    }

    @Test
    fun `submission confirmation requires the latest application to match the selected club`() {
        val confirmed = resolveLaborClubSubmission(
            joinedClubs = emptyList(),
            latestApplication = LaborClubApplication(clubId = "CLUB-1", isAgree = null),
            expectedClubId = "club-1",
        )
        val notYetSynced = resolveLaborClubSubmission(
            joinedClubs = emptyList(),
            latestApplication = LaborClubApplication(clubId = "another-club", isAgree = null),
            expectedClubId = "club-1",
        )

        assertEquals(LaborClubMembershipStatus.PENDING, confirmed.membership.status)
        assertFalse(confirmed.isStatusSyncing)
        assertEquals(LaborClubMembershipStatus.PENDING, notYetSynced.membership.status)
        assertTrue(notYetSynced.isStatusSyncing)
    }

    @Test
    fun `resubmission does not confirm an unchanged rejected application`() {
        val rejected = LaborClubApplication(
            id = "apply-1",
            clubId = "club-1",
            reason = "参与劳动实践",
            addTime = "2026-07-16 10:00:00",
            isAgree = false,
        )
        val unchanged = resolveLaborClubSubmission(
            joinedClubs = emptyList(),
            latestApplication = rejected,
            expectedClubId = "club-1",
            previousApplication = rejected,
        )
        val newApplication = resolveLaborClubSubmission(
            joinedClubs = emptyList(),
            latestApplication = rejected.copy(id = "apply-2", addTime = "2026-07-17 12:00:00", isAgree = null),
            expectedClubId = "club-1",
            previousApplication = rejected,
        )

        assertTrue(unchanged.isStatusSyncing)
        assertFalse(newApplication.isStatusSyncing)
        assertEquals(LaborClubMembershipStatus.PENDING, newApplication.membership.status)
    }

    @Test
    fun `review status maps pending approved rejected and expired records`() {
        assertEquals(
            LaborClubMembershipStatus.PENDING,
            resolveLaborClubMembership(emptyList(), LaborClubApplication(isAgree = null)).status,
        )
        assertEquals(
            LaborClubMembershipStatus.APPROVED_SYNCING,
            resolveLaborClubMembership(emptyList(), LaborClubApplication(isAgree = true)).status,
        )
        assertEquals(
            LaborClubMembershipStatus.REJECTED,
            resolveLaborClubMembership(emptyList(), LaborClubApplication(isAgree = false)).status,
        )
        assertEquals(
            LaborClubMembershipStatus.REJECTED,
            resolveLaborClubMembership(
                emptyList(),
                LaborClubApplication(isAgree = null, statusText = "申请已失效"),
            ).status,
        )
    }

    @Test
    fun `application decoder accepts real response fields and flexible booleans`() {
        val application = decodeLaborClubApplication(
            Json.parseToJsonElement(
                """{
                    "ID":"apply-1",
                    "ClubID":"club-1",
                    "ClubName":"测试俱乐部",
                    "Reason":"参与劳动实践",
                    "AddTime":"2026-07-17 12:30:00",
                    "ReplyComment":"同意加入",
                    "IsAgree":1
                }""",
            ),
        )

        assertEquals("club-1", application.clubId)
        assertEquals("测试俱乐部", application.clubName)
        assertEquals("同意加入", application.replyComment)
        assertEquals(true, application.isAgree)

        val pending = decodeLaborClubApplication(Json.parseToJsonElement("""{"IsAgree":null}"""))
        assertNull(pending.isAgree)
    }

    @Test
    fun `latest application is selected by AddTime instead of response order`() {
        val latest = latestLaborClubApplication(
            listOf(
                LaborClubApplication(id = "newer", addTime = "2026-07-17T12:30:00"),
                LaborClubApplication(id = "older", addTime = "2026-06-01 09:00:00"),
                LaborClubApplication(id = "middle", addTime = "2026-07-01 18:00:00"),
            ),
        )

        assertEquals("newer", latest?.id)
    }

    @Test
    fun `directory ignores teacher data and does not block over capacity clubs`() {
        val club = tolerantJson.decodeFromString<LaborClubDirectoryItem>(
            """{
                "ID":"club-1",
                "Name":"测试俱乐部",
                "TypeID":"type-1",
                "ProjectID":"project-1",
                "PeopleNum":100,
                "MemberNum":101,
                "PorjectName":"劳动实践",
                "TypeName":"综合劳动",
                "Ico":null,
                "Desc":null,
                "IsEnable":true,
                "IsJoin":false,
                "teacherData":[{"ignored":true}]
            }""",
        )

        assertTrue(club.canApply)
        assertEquals(101, club.memberNum)
    }
}
