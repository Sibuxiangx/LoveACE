package tech.loveace.appv3.data.local

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import tech.loveace.appv3.data.model.ClubSource
import tech.loveace.appv3.data.model.ClubStatus
import tech.loveace.appv3.data.model.UserClub

/**
 * 用户手动添加的俱乐部本地存储
 *
 * 使用 SharedPreferences 存储 JSON 序列化后的列表。
 * 俱乐部数量极少（通常 < 20），KV 存储足够且无需引入 Room。
 */
object UserClubStore {
    private const val PREF_NAME = "loveace_user_clubs"
    private const val KEY_CLUBS = "clubs"

    private lateinit var prefs: SharedPreferences
    private val json = Json { ignoreUnknownKeys = true }

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    }

    /** 获取所有手动添加的俱乐部（仅包含 ACTIVE 状态） */
    fun getAll(): List<UserClub> {
        val raw = prefs.getString(KEY_CLUBS, null) ?: return emptyList()
        return try {
            json.decodeFromString<List<UserClub>>(raw)
                .filter { it.status == ClubStatus.ACTIVE && it.source == ClubSource.MANUAL }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 获取所有手动添加的俱乐部（包含 HIDDEN 状态，用于管理页面） */
    fun getAllIncludingHidden(): List<UserClub> {
        val raw = prefs.getString(KEY_CLUBS, null) ?: return emptyList()
        return try {
            json.decodeFromString(raw)
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 添加俱乐部，若已存在则返回 false */
    fun addClub(club: UserClub): Boolean {
        val current = getAllIncludingHidden().toMutableList()
        if (current.any { it.clubId == club.clubId }) return false
        current.add(club)
        save(current)
        return true
    }

    /** 移除俱乐部 */
    fun removeClub(clubId: String) {
        val current = getAllIncludingHidden().filter { it.clubId != clubId }
        save(current)
    }

    /** 更新俱乐部状态 */
    fun updateStatus(clubId: String, status: ClubStatus) {
        val current = getAllIncludingHidden().toMutableList()
        val index = current.indexOfFirst { it.clubId == clubId }
        if (index != -1) {
            current[index] = current[index].copy(status = status)
            save(current)
        }
    }

    private fun save(clubs: List<UserClub>) {
        prefs.edit().putString(KEY_CLUBS, json.encodeToString(clubs)).apply()
    }
}
