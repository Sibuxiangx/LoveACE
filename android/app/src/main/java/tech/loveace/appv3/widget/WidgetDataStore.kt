package tech.loveace.appv3.widget

import android.content.Context
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Widget 数据存储 — 使用文件存储，跨进程可靠
 * 
 * 为什么不用 DataStore/SharedPreferences：
 * - DataStore 默认不支持多进程
 * - SharedPreferences 的 MODE_MULTI_PROCESS 已废弃且不可靠
 * - Widget 运行在独立进程，需要跨进程读写
 * 
 * 文件存储是最简单可靠的跨进程方案
 */
object WidgetDataStore {
    private const val DIR_NAME = "widget_cache"
    private const val FILE_SEMESTER = "semester.json"
    private const val FILE_COURSES = "courses.json"

    private fun getDir(context: Context): File {
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun saveSemesterJson(context: Context, json: String) {
        writeAtomically(File(getDir(context), FILE_SEMESTER), json)
    }

    fun saveCourses(context: Context, json: String) {
        writeAtomically(File(getDir(context), FILE_COURSES), json)
    }

    fun loadSemesterJson(context: Context): String? {
        val file = File(getDir(context), FILE_SEMESTER)
        return if (file.exists()) file.readText() else null
    }

    fun loadCoursesJson(context: Context): String? {
        val file = File(getDir(context), FILE_COURSES)
        return if (file.exists()) file.readText() else null
    }

    private fun writeAtomically(file: File, content: String) {
        val temporary = File.createTempFile(file.name, ".tmp", file.parentFile)
        try {
            temporary.writeText(content)
            try {
                Files.move(
                    temporary.toPath(),
                    file.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    file.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } finally {
            temporary.delete()
        }
    }
}
